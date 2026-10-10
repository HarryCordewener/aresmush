module AresMUSH
  module Pf2e

    # A creature made stronger or weaker than its stat block: Monster Core's elite and weak adjustments,
    # applied as Foundry applies them. Each is a row, and the stat block a creature fights with is its
    # own with its row applied - so its Strikes, saves, abilities and level all answer adjusted, and
    # taking the adjustment off is reading the stat block without it.
    #
    #   by      what every figure and DC moves by
    #   hp      what its hit points move by, by the level it started at
    #   level   the level it becomes
    module Adjustments

      ROWS = {
        'elite' => {
          'by' => 2,
          'hp' => ->(level) { level >= 20 ? 30 : level >= 5 ? 20 : level >= 2 ? 15 : 10 },
          'level' => ->(level) { level < 1 ? level + 2 : level + 1 }
        },
        'weak' => {
          'by' => -2,
          'hp' => ->(level) { level >= 21 ? -30 : level >= 6 ? -20 : level >= 3 ? -15 : level >= 1 ? -10 : 0 },
          'level' => ->(level) { level == 1 ? -1 : [ level - 1, -1 ].max }
        }
      }.freeze

      # What a GM says to take an adjustment off.
      NONE = %w{normal none base}.freeze

      # What an ability deals, where its words say it: `4d6 fire damage`, or a listed `(1d8+6) bludgeoning,`.
      # Damage on top of something else's - `an extra 1d6` - is that thing's, and persistent damage is not
      # the first of what an ability deals. Built when asked for, because `CreatureAbilities` loads later.
      def self.dealt
        @dealt ||= /(?<!extra )(?<!additional )(?<formula>#{CreatureAbilities::FORMULA})(?=\)? (?!persistent)[a-z]+(?: damage|,))/
      end

      # A DC an ability names, which a flat check's is not.
      DC = /\bDC (\d+)\b(?! flat)/

      # An ability it cannot use every round deals twice the difference.
      LIMITED = /\bFrequency\b|\bonce per\b|can't use [^.%]{1,60} again/i

      def self.names
        ROWS.keys
      end

      # The adjustment a GM named, `nil` for taking one off, or `:unknown`.
      def self.named(word)
        word = word.to_s.strip.downcase

        return nil if NONE.include?(word)

        ROWS.key?(word) ? word : :unknown
      end

      # The stat block with the adjustment applied, as a block of its own.
      def self.apply(block, name)
        row = ROWS[name.to_s]

        return block unless row

        by = row['by']
        level = block['level'].to_i
        moved = lambda { |value| value.nil? ? nil : value.to_i + by }

        block.merge(
          'adjustment' => name.to_s,
          'level' => row['level'].call(level),
          'hp' => [ block['hp'].to_i + row['hp'].call(level), 1 ].max,
          'ac' => moved.call(block['ac']),
          'perception' => moved.call(block['perception']),
          'saves' => (block['saves'] || {}).transform_values(&moved),
          'skills' => block['skills']&.transform_values(&moved),
          'strikes' => block['strikes']&.map { |strike| strike(strike, by) },
          'spellcasting' => block['spellcasting']&.map { |one| one.merge('dc' => moved.call(one['dc']), 'attack' => moved.call(one['attack'])) },
          'actions' => block['actions']&.map { |ability| ability.merge('text' => words(ability['text'], by)) }
        ).compact
      end

      # A Strike two better or worse, in its bonus and in the first of what it deals.
      def self.strike(strike, by)
        first, *rest = Array(strike['damage'])
        damage = first ? [ [ plus(first[0], by), *first[1..] ] ] + rest : []

        strike.merge('bonus' => strike['bonus'].to_i + by, 'damage' => damage)
      end

      # An ability's words with its DCs and what it deals moved.
      def self.words(text, by)
        return text if text.nil?

        amount = text.match?(LIMITED) ? by * 2 : by

        text.gsub(DC) { "DC #{$1.to_i + by}" }.gsub(self.dealt) { plus($~[:formula], amount) }
      end

      # A formula with a flat amount more or less: `1d8+6` and 2 is `1d8+8`, `1d6` and -2 is `1d6-2`.
      def self.plus(formula, amount)
        found = formula.to_s.delete(' ').match(/\A(.*?)([+-]\d+)?\z/)
        flat = found[2].to_i + amount

        "#{found[1]}#{flat.zero? ? '' : format('%+d', flat)}"
      end

      # What a spell deals from whoever casts it, which for an adjusted creature is the first of it four
      # more or less, or two where the spell is a cantrip, which it casts at will.
      def self.spell_damage(caster, mechanics, formulas)
        row = ROWS[(caster.respond_to?(:adjustment) ? caster.adjustment : nil).to_s]

        return formulas unless row && formulas.any?

        by = mechanics['rank'].to_i.zero? ? row['by'] : row['by'] * 2
        (first, *kept), *rest = formulas

        [ [ plus(first, by), *kept ] ] + rest
      end
    end
  end
end
