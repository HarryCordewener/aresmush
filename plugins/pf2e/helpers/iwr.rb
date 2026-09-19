module AresMUSH
  module Pf2e

    # What a character shrugs off, and what hurts them more.
    #
    # Immunity, weakness and resistance are the other side of the damage work: damage now has a kind, so
    # something can care what kind it is. Twenty-six rules on the things we stock declare one - a Charm
    # of Resistance, an Aeon Stone, and the immunities Blinded and Deafened carry.
    #
    # The arithmetic is theirs (`system/damage/iwr.ts`) and has three steps in an order that matters:
    #
    #   1. Immunity to the kind takes the whole of it.
    #   2. The **highest** applicable weakness adds its value - once, not once per weakness.
    #   3. The **highest** applicable resistance subtracts, and damage does not go below nothing.
    #
    # Taking the highest rather than the sum is the same shape as modifier stacking, and for the same
    # reason: two resistances of 5 are resistance 5.
    module IWR

      KINDS = %w{Immunity Weakness Resistance}.freeze

      # Immunity to a kind of damage takes all of it; immunity to something else - a trait, a condition -
      # is not about damage at all, and those are held so a predicate can ask.
      def self.of(char)
        SheetReads.memo(char, :iwr) { gather(char) }
      end

      def self.gather(char)
        sources = Effects.sources(char)
        options = Effects.options(char)
        context = Effects.context(char)

        KINDS.each_with_object({}) do |kind, out|
          out[kind.downcase] = Rules.declarations(sources, options, kind, context)
        end
      end

      # What `amount` of `kind` damage comes to for this character, and what did it.
      #
      #   { 'amount' =>, 'applied' => [ { 'category' =>, 'type' =>, 'adjustment' => } ] }
      def self.apply(held, amount, kind, categories = [])
        against = ([ kind ] + Array(categories)).compact.map { |one| Domains.slug(one) }
        applied = []

        return immune(amount, against, held, applied) if immune?(held, against)

        amount = weaken(amount, against, held, applied)
        amount = resist(amount, against, held, applied)

        { 'amount' => amount, 'applied' => applied }
      end

      def self.immune?(held, against)
        matching(held['immunity'], against).any?
      end

      def self.immune(amount, against, held, applied)
        found = matching(held['immunity'], against).first

        applied << { 'category' => 'immunity', 'type' => Array(found['type']).join('/'),
                     'adjustment' => -amount }

        { 'amount' => 0, 'applied' => applied }
      end

      def self.weaken(amount, against, held, applied)
        found = highest(held['weakness'], against)

        return amount unless found

        applied << { 'category' => 'weakness', 'type' => found['type'], 'adjustment' => found['value'] }

        amount + found['value'].to_i
      end

      def self.resist(amount, against, held, applied)
        found = highest(held['resistance'], against)

        return amount unless found

        taken = [ found['value'].to_i, amount ].min
        applied << { 'category' => 'resistance', 'type' => found['type'], 'adjustment' => -taken }

        amount - taken
      end

      # `all-damage` is resistance to everything, which is what Unstoppable Juggernaut grants. A type may
      # also be a list - vitality or void - and then any of them matches.
      EVERYTHING = 'all-damage'.freeze

      # An entry either names kinds of damage or describes them with a predicate, and one that does both
      # has to satisfy both. The facts a description is tested against are the damage's own.
      def self.matching(entries, against)
        facts = against.map { |one| "damage:type:#{one}" }

        Array(entries).select do |entry|
          named = names(entry)

          next Predicate.test(entry['definition'], facts) if named.empty?

          named.any? { |one| reaches?(one, against) } &&
            (entry['definition'].nil? || Predicate.test(entry['definition'], facts))
        end
      end

      def self.names(entry)
        Array(entry['type']).map { |named| Domains.slug(named) }
      end

      def self.reaches?(named, against)
        named == EVERYTHING || against.include?(named)
      end

      def self.highest(entries, against)
        matching(entries, against).max_by { |entry| entry['value'].to_i }
      end
    end
  end
end
