module AresMUSH
  module Pf2e

    # Which of someone's weapons have been shot and not loaded again. A weapon with a reload of 1 or
    # more is loaded as a fight starts, is not once it is shot, and takes that many actions to load.
    module Loading

      KEY = 'unloaded'.freeze

      def self.held(holder)
        Array(TurnState.of(holder)[KEY])
      end

      def self.unloaded?(holder, attack)
        WeaponTraits.reload(attack).positive? && held(holder).include?(attack['name'])
      end

      def self.shot(holder, attack)
        return unless WeaponTraits.reload(attack).positive?

        TurnState.write(holder, KEY => (held(holder) + [ attack['name'] ]).uniq)
      end

      def self.load(holder, attack)
        TurnState.write(holder, KEY => held(holder) - [ attack['name'] ])
      end

      # The attack to load: the one named among those that need it, or the first that does.
      def self.reload(holder, attacks, term = nil)
        waiting = attacks.select { |attack| held(holder).include?(attack['name']) }
        wanted = Domains.slug(term)

        return waiting.first if wanted.empty?

        waiting.find { |attack| Domains.slug(attack['name']).include?(wanted) }
      end
    end
  end
end
