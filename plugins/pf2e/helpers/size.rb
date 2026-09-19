module AresMUSH
  module Pf2e

    # How big a character is, and how far they reach.
    #
    # Their ancestry sets it, and an effect can change it: Shrink makes them tiny, Enlarge one size larger.
    # Foundry's `CreatureSize` rule (`creature-size.ts`) is read unchanged - a size by name, or one step
    # up or down within a limit - and reach follows the size unless the rule says otherwise. What the
    # character is answers to `self:size:<index>` and `self:size:<word>`, which is how a predicate asks.
    module Size

      SIZES = %w{tiny sm med lg huge grg}.freeze
      WORDS = %w{tiny small medium large huge gargantuan}.freeze

      # The ancestry records a letter.
      LETTERS = { 'T' => 'tiny', 'S' => 'sm', 'M' => 'med', 'L' => 'lg', 'H' => 'huge', 'G' => 'grg' }.freeze

      # Reach by size, for a tall creature, which a character is.
      REACH = { 'tiny' => 0, 'sm' => 5, 'med' => 5, 'lg' => 10, 'huge' => 15, 'grg' => 20 }.freeze

      def self.natural(char)
        LETTERS[(char.pf2_movement || {})['Size'].to_s.upcase] || 'med'
      end

      # What the character is now: `{ 'size' => 'sm', 'reach' => 5 }`.
      def self.of(char)
        SheetReads.memo(char, :size) do
          size = natural(char)
          reach = REACH[size]

          rules(char).each do |row, context|
            before = size
            size = resized(size, Formula.value_or_word(row['value'], context), row)
            reach = reached(reach, before, size, row['reach'], context)
          end

          { 'size' => size, 'reach' => reach }
        end
      end

      def self.rules(char)
        options = Effects.character_facts(char)
        context = Effects.context(char)

        (Effects.feats(char) + Effects.items(char) + ActiveEffects.sources(char)).flat_map do |source|
          Rules.of_kind(source, 'CreatureSize').select { |row| Predicate.test(row['predicate'], options) }
                                               .map { |row| [ row, context.merge('item' => source['item'] || {}) ] }
        end
      end

      # A size by name, or one step - within a limit where the rule sets one.
      def self.resized(size, value, row)
        at = SIZES.index(size)

        case value
        when 1
          return size if row['maximumSize'] && at >= SIZES.index(abbreviated(row['maximumSize'])).to_i

          SIZES[[ at + 1, SIZES.size - 1 ].min]
        when -1
          return size if row['minimumSize'] && at <= SIZES.index(abbreviated(row['minimumSize'])).to_i

          SIZES[[ at - 1, 0 ].max]
        else
          abbreviated(value) || size
        end
      end

      def self.abbreviated(value)
        word = value.to_s.downcase

        return word if SIZES.include?(word)

        SIZES[WORDS.index(word)] if WORDS.include?(word)
      end

      # Reach grows with a larger size and shrinks with a smaller one, unless the rule says what it is.
      def self.reached(reach, before, after, rule, context)
        if rule.is_a?(Hash)
          change = Formula.value(rule['add'] || rule['upgrade'] || rule['override'], context).to_i

          return [ reach + change, 0 ].max if rule.key?('add')
          return [ reach, change ].max if rule.key?('upgrade')
          return [ change, 0 ].max if rule.key?('override')
        end

        grew = SIZES.index(after) <=> SIZES.index(before)

        return [ REACH[after], reach ].max if grew.positive?
        return [ REACH[after], reach ].min if grew.negative?

        reach
      end

      def self.facts(char)
        size = of(char)['size']
        index = SIZES.index(size)

        [ "self:size:#{index}", "self:size:#{WORDS[index]}" ]
      end
    end
  end
end
