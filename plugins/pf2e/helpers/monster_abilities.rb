module AresMUSH
  module Pf2e

    # What the abilities many creatures share actually do. A stat block gives each as a line of its own
    # figures - `(1d8) bludgeoning, DC 17 basic Fortitude`, `Medium, (1d6+2) bludgeoning, Rupture 9` - and
    # the same words of rules beneath it every time; a row here is those rules, run with those figures.
    #
    #   several   it is aimed at as many as the GM names
    #   refusal   what it needs before it can be used at all, answered as an error where that is missing
    #   run       what it does, into the report
    #
    # An ability with no row is announced with its words, for the GM to run.
    module MonsterAbilities

      SAVES = 'Fortitude|Reflex|Will'.freeze
      SIZES = %w{tiny small medium large huge gargantuan}.freeze

      # The figures on an ability's first line.
      #
      #   { 'damage' => [ [ '1d8+1', 'bludgeoning' ], [ '1d6', 'acid' ] ], 'dc' => 17, 'save' => 'fortitude',
      #     'basic' => true, 'rupture' => 5, 'size' => 'medium', 'escape_dc' => 22, 'words' => [ 'hoof' ] }
      def self.header(text)
        line = text.to_s.split('%r').first.to_s
        out = { 'damage' => [], 'words' => [] }

        line.split(/,\s*/).each do |part|
          part = part.strip

          if (found = part.match(/\ADC (\d+)\s*(basic)?\s*(#{SAVES})/i))
            out.merge!('dc' => found[1].to_i, 'basic' => !found[2].nil?, 'save' => found[3].downcase)
          elsif (found = part.match(/\A\(?(#{CreatureAbilities::FORMULA})\)?\s+([a-z]+)(?:\s+damage)?\b/i))
            out['damage'] << [ found[1].delete(' '), found[2].downcase ]
          elsif (found = part.match(/\ARupture (\d+)/i)) then out['rupture'] = found[1].to_i
          elsif (found = part.match(/\Aescape dc\s*=?\s*(\d+)/i)) then out['escape_dc'] = found[1].to_i
          elsif (found = part.match(/\A(#{SIZES.join('|')})\b/i)) then out['size'] = found[1].downcase
          else out['words'] << part
          end
        end

        out
      end

      def self.formulas(header)
        header['damage'].map { |formula, type| [ formula, type, nil, [ 'damage' ] ] }
      end

      SIZE_WORDS = { 'tiny' => 0, 'small' => 1, 'medium' => 2, 'large' => 3, 'huge' => 4, 'gargantuan' => 5 }.freeze

      # How big someone is, as a place in the order of sizes: a creature's stat block's size, and a
      # character's as their ancestry and their effects leave it.
      def self.size_of(holder)
        return Size::SIZES.index(Size.of(holder)['size']) unless Actors.of(holder).creature?

        SIZE_WORDS.fetch(holder.stat_block['size'].to_s.downcase, SIZE_WORDS['medium'])
      end

      # `makes one Fangs Strike and two Tail Strikes`, `Strides and makes a Strike`: the Strikes an
      # ability's words say it makes, in order, where they say so plainly - by name, or `nil` for its first.
      # One whose Strike has rules of its own - a penalty, more damage, what a hit then does - is the GM's.
      NUMBERS = { 'a' => 1, 'an' => 1, 'one' => 1, 'two' => 2, 'three' => 3 }.freeze
      STRIKES = /\bmak(?:es?|ing)\b[^.%]*?\b(#{NUMBERS.keys.join('|')})\s+(?:([a-z][a-z' -]*?)\s+)?Strikes?\b(?:\s+and\s+(#{NUMBERS.keys.join('|')})\s+([a-z][a-z' -]*?)\s+Strikes?\b)?/i
      NOT_PLAIN = /penalty|bonus|different target|instead|rather than|compares|counts? as|\bextra\b|\badditional\b|if (?:it|the|both|either|any)[^.%]*\bhits?\b|on a (?:hit|success|failure)|it has grabbed/i

      def self.strikes_in(own, holder)
        text = own['text'].to_s
        found = text.match?(NOT_PLAIN) ? nil : text.match(STRIKES)

        return [] unless found

        named = [ [ found[1], found[2] ], [ found[3], found[4] ] ].reject { |count, _strike| count.nil? }
                  .flat_map { |count, strike| [ strike && strike.strip ] * NUMBERS[count.downcase] }

        named.all? { |strike| strike.nil? || Acting.attack_for(holder, strike) } ? named : []
      end

      # `makes up to four vine Strikes, each against a different target`: the Strike it is made with where
      # the words name one, the most targets where they give a number, and whether the Strikes move the
      # multiple attack penalty on by one or by each of them. Nothing where the Strikes carry a penalty
      # or a bonus of their own, which is the GM's.
      MANY = NUMBERS.merge('four' => 4, 'five' => 5, 'six' => 6).freeze
      EACH = /\beach against a different (?:target|creature|enemy|foe)\b/i
      EACH_STRIKE = /\b(?:makes?|attempts?) (?:(?:up to )?(a number of|an?|#{MANY.keys.join('|')}) )?(?:([a-z][a-z' -]*?) )?Strikes?\b(.*?),? each against/i

      def self.strike_each(own, holder)
        sentence = CreatureAbilities.sentences(own['text'].to_s).find { |one| one.match?(EACH) }
        found = sentence&.match(EACH_STRIKE)

        return nil unless found && !found[3].match?(/penalty|bonus/i)
        return nil if found[2] && !Acting.attack_for(holder, found[2].strip)

        { 'weapon' => found[2]&.strip, 'most' => found[1].to_s.match?(/\Aan?\z/i) ? nil : MANY[found[1].to_s.downcase],
          'as_one' => own['text'].to_s.match?(/counts? as one attack/i) }
      end

      # `must succeed at a DC 21 Fortitude save or be pulled adjacent to the harpy, where they make a jaws
      # Strike`: the Strike made at whoever fails the save, by name where the words name it.
      # What lasts until someone makes a Strike is no Strike of this ability's.
      SAVE_OR_STRIKE = /must succeed (?:at|on) an? DC \d+ (?:Fortitude|Reflex|Will) (?:save|saving throw) or (?:(?!\buntil\b)[^.%])*?\bmakes? an? (?:([a-z][a-z' -]*?) )?Strike\b/i

      # ------------------------------------------------------------------------------
      # The abilities

      # Constrict: the listed damage to any number of creatures it has grabbed or restrained, each with a
      # basic save against the listed DC.
      CONSTRICT = {
        'several' => true,
        'refusal' => ->(use) { use.held.empty? ? use.holds_nobody : nil },
        'run' => ->(use) { use.held.each { |target| use.save(target, use.header) } }
      }.freeze

      # Swallow Whole: a creature it holds in its jaws, of the listed size or smaller, on an Athletics
      # check against their Reflex DC. Whoever is swallowed is held inside it: grabbed, slowed, taking the
      # listed damage now and at the end of each of their turns, until they Escape or cut their way out.
      SWALLOW = {
        'refusal' => lambda do |use|
          target = use.held.first

          return use.holds_nobody unless target
          return Err.new(:swallow_full, 'pf2e.swallow_full', 'actor' => use.actor.label) if use.full?

          size_of(target.holder) > SIZE_WORDS.fetch(use.header['size'], 5) ? use.too_big(target) : nil
        end,
        'run' => lambda do |use|
          target = use.held.first

          use.inside!(target) if use.check(target, 'Athletics', 'reflex') >= Degree::SUCCESS
        end
      }.freeze

      # Engulf: everyone in its path saves against the listed DC, and whoever fails is held inside it as
      # the swallowed are, to be escaped at the DC it lists.
      ENGULF = {
        'several' => true,
        'refusal' => ->(use) { use.targets.empty? ? use.needs_target : nil },
        'run' => lambda do |use|
          use.targets.each do |target|
            degree = use.save(target, use.header.merge('damage' => []))

            use.inside!(target) if degree && degree <= Degree::FAILURE
          end
        end
      }.freeze

      # Trample: the damage of the listed Strike to each creature it runs over, against a basic Reflex
      # save at the listed DC.
      TRAMPLE = {
        'several' => true,
        'refusal' => ->(use) { use.targets.empty? ? use.needs_target : nil },
        'run' => lambda do |use|
          attack = use.attack(use.header['words'].first)
          dealt = Array(attack && attack['damage']).map { |formula, type, _category| [ formula, type ] }

          use.targets.each { |target| use.save(target, use.header.merge('damage' => dealt)) }
        end
      }.freeze

      # Rend: the listed Strike's damage again, to an enemy it has hit with that Strike twice running
      # this turn.
      REND = {
        'refusal' => lambda do |use|
          strike = use.header['words'].first.to_s
          last = Array(TurnState.turn(use.actor.holder)['strikes']).last(2)
          target = use.targets.first&.label || (last.last || {})['target']
          twice = last.size == 2 && last.all? { |one| one['hit'] && one['strike'].to_s.casecmp?(strike) && one['target'] == target }

          twice ? nil : Err.new(:rend_needs_hits, 'pf2e.rend_needs_hits', 'actor' => use.actor.label, 'strike' => strike)
        end,
        'run' => lambda do |use|
          attack = use.attack(use.header['words'].first)
          target = use.targets.first || use.combatant(Array(TurnState.turn(use.actor.holder)['strikes']).last['target'])
          check = Check.of(use.actor.holder, 'attack', attack, [])

          Acting.deal(use.at(target), target, Actors.of(use.actor.holder).strike_damage(attack, check, false), use.out)
        end
      }.freeze

      # Ferocity: reduced to nothing, it stays on its feet at 1 Hit Point and is wounded one more; at
      # Wounded 3 it cannot.
      FEROCITY = {
        'when_down' => true,
        'refusal' => lambda do |use|
          holder = use.actor.holder

          return Err.new(:ferocity_not_down, 'pf2e.ferocity_not_down', 'actor' => use.actor.label) if holder.hp_left.to_i.positive?

          Pf2e.condition_level(holder, 'Wounded') >= 3 ? Err.new(:ferocity_wounded, 'pf2e.ferocity_wounded', 'actor' => use.actor.label) : nil
        end,
        'run' => lambda do |use|
          holder = use.actor.holder

          holder.update(:damage => holder.max_hp - 1)
          Pf2e.set_condition(holder, 'Wounded', Pf2e.condition_level(holder, 'Wounded') + 1)
          use.out['lines'] << Telling.event('pf2e.ferocity_up', :actor => use.actor.label,
                                                               :wounded => Pf2e.condition_level(holder, 'Wounded'))
        end
      }.freeze

      # Throw Rock: a ranged Strike with its rock, which is all of the action.
      THROW_ROCK = {
        'paid' => true,
        'refusal' => ->(use) { use.targets.empty? ? use.needs_target : nil },
        'run' => ->(use) { use.strike(use.targets.first, 'rock', true) }
      }.freeze

      # An ability whose words are the Strikes it makes: each is made, further into the multiple attack
      # penalty than the last, for what the ability costs.
      SEVERAL_STRIKES = {
        'refusal' => ->(use) { use.targets.empty? ? use.needs_target : nil },
        'run' => lambda do |use|
          strikes_in(use.own, use.actor.holder).each { |strike| use.strike(use.targets.first, strike, false) }
        end
      }.freeze

      # An ability that Strikes each of the targets named, none further into the multiple attack penalty
      # than the first: the penalty moves on once they are all made.
      STRIKE_EACH = {
        'several' => true,
        'refusal' => lambda do |use|
          most = strike_each(use.own, use.actor.holder)['most']

          return use.needs_target if use.targets.empty?

          most && use.targets.size > most ? Err.new(:too_many_targets, 'pf2e.act_too_many_targets', 'action' => use.name, 'most' => most) : nil
        end,
        'run' => lambda do |use|
          each = strike_each(use.own, use.actor.holder)
          made = TurnState.turn(use.actor.holder)['attacks'].to_i

          use.targets.each do |target|
            use.strike(target, each['weapon'], false)
            TurnState.attacks_at(use.actor.holder, made)
          end

          TurnState.attacks_at(use.actor.holder, made + (each['as_one'] ? 1 : use.targets.size))
        end
      }.freeze

      # An ability whose Strike is made at whoever fails its save.
      STRIKE_ON_FAILURE = {
        'several' => true,
        'refusal' => ->(use) { use.targets.empty? ? use.needs_target : nil },
        'run' => lambda do |use|
          figures = CreatureAbilities.saving(use.own['text'])
          weapon = use.own['text'].to_s[SAVE_OR_STRIKE, 1]

          use.targets.each do |target|
            degree = use.save(target, figures)

            use.strike(target, weapon, false) if degree && degree <= Degree::FAILURE
          end
        end
      }.freeze

      ROWS = {
        'constrict' => CONSTRICT,
        'greater-constrict' => CONSTRICT,
        'swallow-whole' => SWALLOW,
        'engulf' => ENGULF,
        'trample' => TRAMPLE,
        'rend' => REND,
        'ferocity' => FEROCITY,
        'throw-rock' => THROW_ROCK
      }.freeze

      # The row for an ability, by its name, or - where its words are plainly the Strikes it makes - the
      # row for that.
      def self.row(name, own = nil, holder = nil)
        found = ROWS[Domains.slug(name).sub(/-\d+-feet\z/, '')]

        return found if found
        return nil unless own && holder
        return STRIKE_EACH if strike_each(own, holder)
        return STRIKE_ON_FAILURE if own['text'].to_s.match?(SAVE_OR_STRIKE) && CreatureAbilities.saving(own['text'])

        strikes_in(own, holder).empty? ? nil : SEVERAL_STRIKES
      end

      # One use of an ability: who uses it, on whom, and the stat block's entry for it.
      Use = Struct.new(:scene, :name, :own, :targets, :out, :paid) do
        def actor
          scene.actor
        end

        def header
          @header ||= MonsterAbilities.header(own['text'])
        end

        # Those it holds among those named, or everyone it holds where nobody is named.
        def held
          holding = Holding.held_by(scene.encounter, actor.label)

          targets.empty? ? holding : holding.select { |one| targets.any? { |named| named.label == one.label } }
        end

        def holds_nobody
          Err.new(:hold_none, 'pf2e.hold_none', 'actor' => actor.label, 'action' => name)
        end

        def needs_target
          Err.new(:no_target, 'pf2e.act_needs_target')
        end

        def too_big(target)
          Err.new(:swallow_too_big, 'pf2e.swallow_too_big', 'actor' => actor.label, 'target' => target.label,
                                                           'size' => header['size'])
        end

        # Whether it already holds inside it someone as large as it can swallow.
        def full?
          limit = MonsterAbilities::SIZE_WORDS.fetch(header['size'], 5)

          Holding.held_by(scene.encounter, actor.label).any? do |one|
            inside = Holding.inside(one.holder)

            inside && inside['kind'] == name && MonsterAbilities.size_of(one.holder) >= limit
          end
        end

        def at(target)
          Acting::Scene.new(scene.encounter, actor, target, scene.enactor, scene.permitted)
        end

        def combatant(label)
          Combatants.find(scene.encounter, label).state
        end

        def attack(word)
          Acting.attack_for(actor.holder, word)
        end

        # A target's save against the listed DC, with the listed damage where there is any. Answers the
        # degree.
        def save(target, figures)
          mechanics = { 'save' => figures['save'], 'basic' => figures['basic'], 'traits' => Array(own['traits']),
                        'outcomes' => CreatureAbilities.spoken_outcomes(own['text'].to_s) }

          Acting.spell_save(at(target), name, mechanics, figures['dc'], MonsterAbilities.formulas(figures), out)
        end

        # The creature's skill check against one of the target's defences, as an attack where the ability
        # is one. Answers the degree.
        def check(target, skill, against)
          attacks = Array(own['traits']).include?('attack')
          rolled = Check.of(actor.holder, 'skill', skill, attacks ? TurnState.map_options(actor.holder) : [])
          defence = Resolve.defence(target.holder, against, :options => Resolve.seen_as(actor.holder, 'origin'))
          result = Resolve.roll(rolled, :dc => defence['dc'], :extra => attacks ? Acting.attack_penalty(actor.holder) : [])

          out['lines'] << Acting.check_line(at(target), name, skill, result, { 'against' => against }, defence, defence['dc'])
          out['detail'] += Acting.detail_lines(name, skill, result, defence)

          result['degree']
        end

        # Holds the target inside the creature, and deals what being there deals, now.
        def inside!(target)
          Holding.put_inside(target.holder, actor.label, header.slice('damage', 'rupture', 'escape_dc').merge('kind' => name))
          out['lines'] << Telling.event('pf2e.hold_inside', :target => target.label, :actor => actor.label, :kind => name)
          Holding.digest(scene.encounter, target, out)
        end

        # A Strike that is part of the ability, told with the rest of it. `spent` is whether the Strike
        # costs an action of its own. A reaction's Strike is outside the multiple attack penalty, and
        # spends the reaction itself.
        def strike(target, weapon, spent)
          reacting = own['type'] == 'reaction'
          self.paid = true if reacting
          done = Acting.strike(at(target), weapon, [], :spent => spent, :reaction => reacting ? name : nil, :quiet => true)

          return out['lines'] << Telling.event(done.key, done.args) if done.err?

          %w{lines gm detail}.each { |part| out[part] += done.state[part] }
        end
      end

      # Uses a creature's ability that has a row: refused where its needs are not met, and otherwise
      # announced, run and paid for.
      def self.use(scene, name, own, targets)
        use = Use.new(scene, name, own, Array(targets), Acting.report)
        row = row(name, own, scene.actor.holder)
        refused = row['refusal']&.call(use)

        return refused if refused

        use.out['about'] = DamageAbout.of_ability(own)
        Acting.announce(scene, name, own, use.targets, use.out, :brief => true)
        Recharge.used(scene, name, own, use.out)
        row['run'].call(use)
        Acting.paid(scene, name, own, use.out) unless row['paid'] || use.paid

        Ok.new(:state => use.out)
      end
    end
  end
end
