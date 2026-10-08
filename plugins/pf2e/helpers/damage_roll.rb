module AresMUSH
  module Pf2e

    # Damage rolled: the dice of an attack or a spell, thrown, per kind of damage.
    #
    # `Damage.of` builds a character's attack damage as instances - dice and a flat amount per kind, kept
    # in the piles a critical hit treats differently. A creature's Strike and a spell say theirs as
    # formulas. Both come out of here the same shape, one row per kind:
    #
    #   [ { 'type' => 'slashing', 'category' => nil, 'amount' => 9, 'formula' => '1d8+4' } ]
    #
    # A critical hit doubles, which is the rule's default: the doubling pile's total twice, then what
    # never doubles, then what only a critical adds. What deadly and fatal add is `Damage`'s to say, for
    # a character's weapon and a creature's alike, so the roll and the sheet's critical line agree.
    module DamageRoll

      WORDS = { 'b' => 'bludgeoning', 'p' => 'piercing', 's' => 'slashing' }.freeze

      def self.kind(type)
        WORDS[type.to_s.downcase] || type.to_s
      end

      # A character's attack: `instances` as `Damage.of` built them.
      def self.of_instances(instances, critical, attack = {})
        instances = Damage.critical_instances(instances, attack) if critical

        rows = instances.filter_map do |instance|
          doubling = written(instance['dice'], instance['modifier'])
          fixed = written(instance['fixed_dice'], instance['fixed_modifier'])
          extra = critical ? written(instance['crit_only_dice'], instance['crit_only_modifier']) : ''

          # The whole of what this kind of damage rolls, which persistent damage rolls again each turn. An
          # instance that is a critical hit's alone deals nothing on a hit.
          formula = [ critical ? doubled(doubling) : doubling, fixed, extra ].reject(&:empty?).join('+')

          next nil if formula.empty?

          amount = (throw_dice(instance['dice']).sum + instance['modifier'].to_i) * (critical ? 2 : 1) +
                   throw_dice(instance['fixed_dice']).sum + instance['fixed_modifier'].to_i +
                   (critical ? throw_dice(instance['crit_only_dice']).sum + instance['crit_only_modifier'].to_i : 0)

          { 'type' => kind(instance['damage_type']), 'category' => instance['category'],
            'amount' => [ amount, 0 ].max, 'formula' => formula.gsub('+-', '-') }
        end

        merged(rows)
      end

      # A creature's Strike or a spell: `[ [ '1d6+2', 'slashing', category ] ]`.
      def self.of_formulas(formulas, critical, attack = {})
        rows = Array(formulas).each_with_index.map do |(formula, type, category), index|
          # Fatal upsizes the weapon's own dice, which are the first formula's.
          formula = fatal_formula(formula, attack) if critical && index.zero?

          { 'type' => kind(type), 'category' => category,
            'amount' => [ Pf2e.roll_formula(formula) * (critical ? 2 : 1), 0 ].max,
            'formula' => critical ? doubled(formula) : formula.to_s }
        end

        rows += critical_extra_rows(attack, rows.first) if critical

        merged(rows)
      end

      # Deadly's and fatal's critical-only dice, undoubled, of the weapon's own kind of damage.
      def self.critical_extra_rows(attack, weapon_row)
        Damage.critical_extras(attack).map do |count, die|
          { 'type' => weapon_row ? weapon_row['type'] : kind(attack['damage_type']), 'category' => nil,
            'amount' => Pf2e.roll_dice(count, die.delete('d').to_i).sum, 'formula' => "#{count}#{die}" }
        end
      end

      # A creature's damage beyond its Strike's own formula - an ability's dice, a flat bonus - each in
      # the pile a critical hit treats it by: doubled with the rest, never doubled, or only on a critical.
      def self.of_extras(extras, critical)
        rows = Array(extras).map do |one|
          next nil if one['bucket'] == 'crit_only' && !critical

          times = critical && one['bucket'] == 'doubling' ? 2 : 1
          formula = times == 2 ? doubled(one['formula']) : one['formula'].to_s

          { 'type' => kind(one['type']), 'category' => one['category'],
            'amount' => [ Pf2e.roll_formula(one['formula']) * times, 0 ].max, 'formula' => formula }
        end

        rows.compact
      end

      # A basic save's outcome: half on a success, double on a critical failure, nothing on a critical
      # success. Rolled once, then scaled, which is the rule.
      BASIC = { 3 => 0, 2 => 0.5, 1 => 1, 0 => 2 }.freeze

      def self.scaled(rows, degree)
        factor = BASIC.fetch(degree, 1)

        rows.map { |row| row.merge('amount' => (row['amount'] * factor).floor) }
      end

      def self.throw_dice(dice)
        Array(dice).flat_map { |count, die| Pf2e.roll_dice(count.to_i, die.to_s.delete('d').to_i) }
      end

      # The weapon's dice at the fatal size: `1d8+4` is `1d12+4`. The extra fatal die is added apart,
      # undoubled, with deadly's.
      def self.fatal_formula(formula, attack)
        die = Damage.trait_die(attack, 'fatal')

        return formula unless die

        formula.to_s.sub(/(\d*)d(\d+)/) { "#{$1.empty? ? 1 : $1}d#{die}" }
      end

      # A formula with its like terms added up: `2d6+1d6+1d6+2+1` is `4d6+3`. One with anything but dice
      # and numbers added together is left as it is.
      def self.summed(formula)
        terms = formula.to_s.delete(' ').split('+')

        return formula.to_s unless terms.all? { |term| term.match?(/\A(\d*d\d+|\d+)\z/) }

        dice = terms.grep(/d/).each_with_object(Hash.new(0)) do |term, counts|
          count, die = term.split('d')
          counts["d#{die}"] += count.to_s.empty? ? 1 : count.to_i
        end
        flat = terms.grep_v(/d/).sum(&:to_i)

        parts = dice.map { |die, count| "#{count}#{die}" }
        parts << flat.to_s if flat.positive? || parts.empty?
        parts.join('+')
      end

      # A pile of dice and a flat amount as a formula: `2d6+4`.
      def self.written(dice, modifier)
        terms = Array(dice).map { |count, die| "#{count}#{die}" }
        terms << modifier.to_i.to_s unless modifier.to_i.zero?

        terms.join('+').gsub('+-', '-')
      end

      # A formula twice over, as a critical hit's persistent damage is: `1d6+1` is `2d6+2`.
      def self.doubled(formula)
        formula.to_s.gsub(/(\d*)d(\d+)|(\d+)/) do
          $2 ? "#{($1.to_s.empty? ? 1 : $1.to_i) * 2}d#{$2}" : ($3.to_i * 2).to_s
        end
      end

      # One row per kind and category.
      def self.merged(rows)
        rows.group_by { |row| [ row['type'], row['category'] ] }.map do |(type, category), group|
          { 'type' => type, 'category' => category, 'amount' => group.sum { |row| row['amount'] },
            'formula' => group.map { |row| row['formula'] }.compact.join('+') }
        end.reject { |row| row['amount'].zero? && row['type'].to_s.empty? }
      end

      # `9 slashing + 3 fire`.
      def self.shown(rows)
        rows.map { |row| [ row['amount'], row['category'], row['type'] ].compact.join(' ') }.join(' + ')
      end
    end
  end
end
