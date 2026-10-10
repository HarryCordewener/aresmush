module AresMUSH
  module Pf2e

    # A creature of the GM's own making, described on one line (`+e/add <name>=<description>`): its
    # figures first, then each other part after a semicolon, named by its first word.
    #
    #   ac 18 hp 30 fort 8 ref 9 will 5 perception 7 level 2 speed 25 str 4;
    #   skills athletics 8, stealth 9; immune poison; weak fire 5; resist physical 3 except silver;
    #   traits humanoid, human; size medium; senses darkvision;
    #   strike shortsword +9 1d6+4 piercing (agile, finesse);
    #   ranged shortbow +9 1d6 piercing (range 60, deadly d10);
    #   ability Fire Breath [2]: The bandit breathes fire that deals 4d6 fire damage (DC 20 basic Reflex save).
    #
    # What it answers is a stat block of the bestiary's shape, so a creature described fights as one
    # from the bestiary does.
    module Described

      # The figures, by the words a GM writes them with, and where each goes in a stat block.
      FIGURES = [
        { 'words' => %w{ac}, 'at' => [ 'ac' ] },
        { 'words' => %w{hp}, 'at' => [ 'hp' ] },
        { 'words' => %w{hardness}, 'at' => [ 'hardness' ] },
        { 'words' => %w{level lvl}, 'at' => [ 'level' ] },
        { 'words' => %w{perception per}, 'at' => [ 'perception' ] },
        { 'words' => %w{fort fortitude}, 'at' => %w{saves fortitude} },
        { 'words' => %w{ref reflex}, 'at' => %w{saves reflex} },
        { 'words' => %w{will}, 'at' => %w{saves will} },
        { 'words' => %w{speed land}, 'at' => %w{speeds land} }
      ] + %w{fly swim climb burrow}.map { |kind| { 'words' => [ kind ], 'at' => [ 'speeds', kind ] } } +
          %w{str dex con int wis cha}.map { |ability| { 'words' => [ ability ], 'at' => [ 'abilities', ability ] } }

      NEEDED = %w{ac hp}.freeze

      COSTS = { '1' => [ 'action', 1 ], '2' => [ 'action', 2 ], '3' => [ 'action', 3 ], 'reaction' => [ 'reaction', nil ],
                'free' => [ 'free', nil ], 'passive' => [ 'passive', nil ] }.freeze

      STRIKE = /\A(?<name>.+?)\s+(?<bonus>[+-]?\d+)\s+(?<damage>\d*d\d+.*?|\d+\s.*?)(?:\s*\((?<traits>[^)]*)\))?\z/i
      DAMAGE = /\A(?<formula>\d*d\d+(?:\s*[+-]\s*\d+)?|\d+)\s+(?<persistent>persistent\s+)?(?<type>[a-z][a-z -]*)\z/i
      ABILITY = /\A(?<name>[^\[:]+?)\s*(?:\[(?<cost>[^\]]+)\])?\s*:\s*(?<text>.+)\z/m

      # Each part after the figures, by its first word: where it goes, and how its words are read.
      PARTS = {
        'skills' => ->(block, words) { valued(words).then { |read| read && block.merge('skills' => read.transform_keys { |skill| titled(skill) }) } },
        'immune' => ->(block, words) { block.merge('immunities' => listed(words).map { |one| slug(one) }) },
        'weak' => ->(block, words) { resisted(words).then { |read| read && block.merge('weaknesses' => read) } },
        'resist' => ->(block, words) { resisted(words).then { |read| read && block.merge('resistances' => read) } },
        'traits' => ->(block, words) { block.merge('traits' => listed(words).map { |one| slug(one) }) },
        'senses' => ->(block, words) { block.merge('senses' => listed(words).map(&:downcase)) },
        'size' => ->(block, words) { block.merge('size' => words.downcase) },
        'rarity' => ->(block, words) { block.merge('rarity' => words.downcase) },
        'strike' => ->(block, words) { strike(words).then { |read| read && block.merge('strikes' => Array(block['strikes']) + [ read ]) } },
        'ranged' => ->(block, words) { strike(words).then { |read| read && block.merge('strikes' => Array(block['strikes']) + [ read ]) } },
        'ability' => ->(block, words) { ability(words).then { |read| read && block.merge('actions' => Array(block['actions']) + [ read ]) } },
        'shield' => ->(block, words) { shield(words).then { |read| read && shielded(block, read) } }
      }.freeze

      ALIASES = { 'skill' => 'skills', 'immunities' => 'immune', 'immunity' => 'immune', 'weakness' => 'weak',
                  'weaknesses' => 'weak', 'resistance' => 'resist', 'resistances' => 'resist', 'trait' => 'traits',
                  'melee' => 'strike', 'sense' => 'senses' }.freeze

      # What a part that could not be read is refused as.
      REFUSALS = { 'strike' => :described_strike, 'ranged' => :described_strike, 'ability' => :described_ability,
                   'shield' => :described_shield }.freeze

      SHIELD = /\A(?:(?<name>.*?[a-z].*?)\s+)?(?<hardness>\d+)\s+(?<hp>\d+)(?:\s+\+?(?<ac>\d+))?\z/i
      BLOCKS = 'Trigger The creature has its shield raised and takes damage from a physical attack.%r' \
               "Effect The shield prevents the creature from taking damage up to the shield's Hardness. " \
               'The creature and the shield each take any remaining damage.'.freeze

      # The stat block described, an error saying which part could not be read, or nothing where the
      # words are no description at all - a name, as `+e/add goblin warrior=Grik` gives one.
      def self.read(name, text)
        first, *parts = text.to_s.split(';').map(&:strip).reject(&:empty?)
        block = figures(name, first)

        return nil unless block

        missing = NEEDED.reject { |field| block.key?(field) }

        return Err.new(:described_needs, 'pf2e.described_needs', 'missing' => missing.join(' and ')) if missing.any?

        parts.reduce(Ok.new(:state => block)) do |outcome, part|
          outcome.and_then { |so_far| part_of(so_far, part) }
        end
      end

      def self.figures(name, text)
        read = text.to_s.downcase.scan(/([a-z]+)\s*([+-]?\d+)/).each_with_object({}) do |(word, value), out|
          figure = FIGURES.find { |one| one['words'].include?(word) }

          next unless figure

          *path, last = figure['at']
          path.reduce(out) { |held, key| held[key] ||= {} }[last] = value.to_i
        end

        return nil unless read['ac']

        { 'name' => name, 'level' => 0, 'perception' => 0, 'traits' => [] }.merge(read).merge(
          'saves' => { 'fortitude' => 0, 'reflex' => 0, 'will' => 0 }.merge(read['saves'] || {})
        )
      end

      def self.part_of(block, part)
        word, _, words = part.partition(/\s+/)
        kind = ALIASES[word.downcase] || word.downcase
        reader = PARTS[kind]

        return Err.new(:described_part, 'pf2e.described_part', 'words' => part, 'parts' => PARTS.keys.join(', ')) unless reader

        read = words.strip.empty? ? nil : reader.call(block, words.strip)

        return Ok.new(:state => read) if read

        key = REFUSALS[kind] || :described_part

        Err.new(key, "pf2e.#{key}", 'words' => words.strip, 'parts' => PARTS.keys.join(', '))
      end

      # ------------------------------------------------------------------------------
      # How a part's words are read

      def self.listed(words)
        words.split(',').map(&:strip).reject(&:empty?)
      end

      # `fire 5, cold iron 10` as what each is worth, or nothing where one has no number.
      def self.valued(words)
        read = listed(words).map { |one| one.match(/\A(.+?)\s+[+-]?(\d+)\z/) }

        read.all? ? read.to_h { |found| [ found[1], found[2].to_i ] } : nil
      end

      # `physical 10 except silver, cold 5`: what each is worth, with what a resistance lets through.
      EXCEPTING = /\A(?<type>.+?)\s+[+-]?(?<value>\d+)(?:\s+except\s+(?<except>.+))?\z/i

      def self.resisted(words)
        read = listed(words).map { |one| one.match(EXCEPTING) }

        return nil unless read.all?

        read.to_h do |found|
          excepted = found[:except].to_s.split(/\s+or\s+|\s+and\s+/).map { |one| slug(one) }

          [ slug(found[:type]), excepted.empty? ? found[:value].to_i : { 'value' => found[:value].to_i, 'except' => excepted } ]
        end
      end

      def self.slug(word)
        word.strip.downcase.gsub(/\s+/, '-')
      end

      def self.titled(word)
        word.strip.split(/\s+/).map(&:capitalize).join(' ')
      end

      # `shortsword +9 1d6+4 piercing plus 1d6 fire (agile, range 60)`
      def self.strike(words)
        found = words.match(STRIKE)
        damage = found ? found[:damage].split(/\s+plus\s+/i).map { |one| one.strip.match(DAMAGE) } : []

        return nil unless found && damage.any? && damage.all?

        { 'name' => titled(found[:name]), 'bonus' => found[:bonus].to_i,
          'damage' => damage.map { |one| [ one[:formula].delete(' '), slug(one[:type]), one[:persistent] ? 'persistent' : nil ] },
          'traits' => listed(found[:traits].to_s).map { |one| slug(one).sub(/\Arange-(\d+)\z/, 'range-increment-\1') } }
      end

      # `tower shield 5 20 +3`: a name if it has one, its Hardness and Hit Points, and what it adds to AC
      # raised where that is not 2.
      def self.shield(words)
        found = words.match(SHIELD)

        found && { 'name' => titled(found[:name] || 'Shield'), 'hardness' => found[:hardness].to_i, 'hp' => found[:hp].to_i,
                   'ac' => (found[:ac] || 2).to_i }
      end

      # A creature with a shield blocks with it.
      def self.shielded(block, shield)
        listed = Array(block['actions'])
        blocks = listed.any? { |one| one['name'].casecmp?(ShieldBlock::NAME) }
        reaction = { 'name' => ShieldBlock::NAME, 'type' => 'reaction', 'cost' => nil, 'traits' => [], 'text' => BLOCKS }

        block.merge('shield' => shield, 'actions' => blocks ? listed : listed + [ reaction ])
      end

      # `Fire Breath [2]: The bandit breathes fire...`
      def self.ability(words)
        found = words.match(ABILITY)
        type, cost = found ? COSTS[(found[:cost] || '1').strip.downcase] : nil

        return nil unless type

        { 'name' => found[:name].strip, 'type' => type, 'cost' => cost, 'traits' => [], 'text' => found[:text].strip }
      end
    end
  end
end
