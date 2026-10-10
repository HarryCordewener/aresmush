module AresMUSH
  module Pf2e

    # What a weapon's traits make of one Strike with it, beyond what its dice say: which of its edges is
    # used, whether it is meant to kill, and what the Strikes before it this turn give it.
    #
    #   versatile    deals the other kind of damage where that is said: `/piercing`.
    #   nonlethal    a lethal weapon is used not to kill, or a nonlethal one to kill, at 2 less to hit.
    #   volley       2 less to hit a target said to be inside its volley range: `/volley`.
    #   sweep        1 more to hit once it has been swung at someone else this turn.
    #   backswing    1 more to hit after a miss with it this turn.
    #   forceful     a weapon die's worth more damage on the second Strike with it in a turn, and twice
    #                that from the third.
    #   backstabber  1 precision damage to someone off-guard, 2 from a +3 weapon.
    #   reload       how many actions it takes to load again once shot.
    #
    # An attack is the hash the Strike code reads (`Pf2eCombat.attack_descriptor`, `Npcs.strikes`), and
    # the Strikes before it are what `TurnState` keeps of the turn: `{ 'strike', 'target', 'hit' }`.
    module WeaponTraits

      KINDS = { 'b' => 'bludgeoning', 'p' => 'piercing', 's' => 'slashing' }.freeze
      NONLETHAL = 'nonlethal'.freeze
      TWO_HANDS = [ 'two-handed', 'two-hands', 'two-hand', '2h' ].freeze

      def self.traits(attack)
        Array(attack['traits']).map { |trait| Domains.slug(trait) }
      end

      def self.trait?(attack, name)
        traits(attack).any? { |trait| trait == name || trait.start_with?("#{name}-") }
      end

      # ------------------------------------------------------------------------------
      # The Strike as it is made

      # The kind of damage it deals as it stands, by name.
      def self.kind(attack)
        own = attack['damage'] ? Array(attack['damage']).first.to_a[1] : attack['damage_type']

        KINDS[own.to_s.downcase] || own.to_s.downcase
      end

      # The kinds a versatile weapon may deal instead of its own.
      def self.versatile(attack)
        traits(attack).filter_map { |trait| KINDS[trait[/\Aversatile-([bps])\z/, 1]] }
      end

      # The attack as its wielder said they make it: the kind of damage a versatile weapon deals, and
      # whether the blow is meant to kill. An error where the weapon cannot be used that way.
      def self.wielded(attack, words)
        said = Array(words).map { |word| Domains.slug(word) }
        wanted = (said & KINDS.values).first

        if wanted && wanted != kind(attack)
          unless versatile(attack).include?(wanted)
            return Err.new(:not_versatile, 'pf2e.strike_not_versatile', 'weapon' => attack['name'],
                                                                         'kinds' => ([ kind(attack) ] + versatile(attack)).join(' or '))
          end

          attack = of_kind(attack, wanted)
        end

        # Used against its nature - a blade to subdue, a fist to kill - it is 2 less to hit.
        if said.include?(NONLETHAL) && !trait?(attack, NONLETHAL)
          return attack.merge('traits' => Array(attack['traits']) + [ NONLETHAL ], 'against' => 'Nonlethal')
        end

        if said.include?('lethal') && trait?(attack, NONLETHAL)
          return attack.merge('traits' => Array(attack['traits']).reject { |trait| Domains.slug(trait) == NONLETHAL }, 'against' => 'Lethal')
        end

        attack
      end

      def self.of_kind(attack, wanted)
        return attack.merge('damage_type' => KINDS.key(wanted).upcase) unless attack['damage']

        first, *rest = attack['damage']

        attack.merge('damage' => [ [ first[0], wanted, first[2] ] ] + rest)
      end

      # Whether the wielder said they hold it in two hands.
      def self.two_hands?(words)
        (Array(words).map { |word| Domains.slug(word) } & TWO_HANDS).any?
      end

      # ------------------------------------------------------------------------------
      # What it adds to the roll to hit

      def self.modifier(source, value)
        { 'source' => source, 'slug' => Domains.slug(source), 'type' => 'circumstance', 'value' => value }
      end

      def self.earlier_with(attack, earlier)
        Array(earlier).select { |one| one['strike'] == attack['name'] }
      end

      # `words` is what was said of this Strike, and `made` the attack as `wielded` left it.
      def self.attack_modifiers(made, earlier, target, words)
        said = Array(words).map { |word| Domains.slug(word) }
        mine = earlier_with(made, earlier)
        found = []

        found << modifier('Sweep', 1) if trait?(made, 'sweep') && mine.any? { |one| one['target'] != target }
        found << modifier('Backswing', 1) if trait?(made, 'backswing') && mine.any? && !mine.last['hit']
        found << modifier('Volley', -2) if trait?(made, 'volley') && said.include?('volley')
        found << modifier(made['against'], -2) if made['against']

        found
      end

      # ------------------------------------------------------------------------------
      # What it adds to the damage

      def self.dice(attack)
        return 1 + attack['striking'].to_i unless attack['damage']

        Array(attack['damage']).first.to_a.first.to_s[/\A(\d+)d/, 1].to_i.clamp(1, 10)
      end

      # Rows as the damage code takes its flat modifiers: forceful's is a circumstance bonus to the
      # weapon's own damage, and backstabber's precision damage of its own.
      def self.damage_modifiers(attack, earlier, off_guard)
        found = []
        before = earlier_with(attack, earlier).size

        if trait?(attack, 'forceful') && before.positive?
          found << { 'source' => 'Forceful', 'value' => dice(attack) * [ before, 2 ].min, 'damage_type' => nil, 'category' => nil,
                     'critical' => nil }
        end

        if trait?(attack, 'backstabber') && off_guard
          found << { 'source' => 'Backstabber', 'value' => attack['rune'].to_i >= 3 ? 2 : 1, 'damage_type' => nil,
                     'category' => 'precision', 'critical' => nil, 'creates' => true }
        end

        found
      end

      # ------------------------------------------------------------------------------
      # Loading

      # How many actions it takes to load again: its own figure, or a creature's `reload-1`.
      def self.reload(attack)
        return attack['reload'].to_i if attack['reload']

        traits(attack).filter_map { |trait| trait[/\Areload-(\d)\z/, 1] }.first.to_i
      end
    end
  end
end
