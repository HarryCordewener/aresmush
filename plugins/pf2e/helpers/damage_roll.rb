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
    # never doubles, then what only a critical adds. A deadly weapon adds its die on a critical and a
    # fatal one raises its dice and adds one more (`weapon.ts`), which a character's and a creature's
    # weapon both do.
    module DamageRoll

      WORDS = { 'b' => 'bludgeoning', 'p' => 'piercing', 's' => 'slashing' }.freeze

      def self.kind(type)
        WORDS[type.to_s.downcase] || type.to_s
      end

      # A character's attack: `instances` as `Damage.of` built them.
      def self.of_instances(instances, critical, attack = {})
        instances = fatal(instances, attack) if critical

        rows = instances.map do |instance|
          doubling = throw_dice(instance['dice']) + [ instance['modifier'].to_i ]
          fixed = throw_dice(instance['fixed_dice']) + [ instance['fixed_modifier'].to_i ]
          extra = critical ? throw_dice(instance['crit_only_dice']) + [ instance['crit_only_modifier'].to_i ] : []

          amount = doubling.sum * (critical ? 2 : 1) + fixed.sum + extra.sum
          formula = written(instance['dice'], instance['modifier'])

          { 'type' => kind(instance['damage_type']), 'category' => instance['category'],
            'amount' => [ amount, 0 ].max, 'formula' => critical ? doubled(formula) : formula }
        end

        rows += deadly(attack, rows.first) if critical

        merged(rows)
      end

      # A creature's Strike or a spell: `[ [ '1d6+2', 'slashing', category ] ]`.
      def self.of_formulas(formulas, critical, attack = {})
        rows = Array(formulas).map do |formula, type, category|
          formula = fatal_formula(formula, attack) if critical

          { 'type' => kind(type), 'category' => category,
            'amount' => [ Pf2e.roll_formula(formula) * (critical ? 2 : 1), 0 ].max,
            'formula' => critical ? doubled(formula) : formula.to_s }
        end

        rows += deadly(attack, rows.first) if critical

        merged(rows)
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

      # A deadly weapon's extra die on a critical: one, two with greater striking, three with major. It
      # deals the weapon's own kind of damage, which is the first row's.
      def self.deadly(attack, weapon_row)
        die = trait_die(attack, 'deadly')

        return [] unless die

        count = [ attack['striking'].to_i, 1 ].max

        [ { 'type' => weapon_row ? weapon_row['type'] : kind(attack['damage_type']), 'category' => nil,
            'amount' => Pf2e.roll_dice(count, die).sum, 'formula' => "#{count}d#{die}" } ]
      end

      # A fatal weapon's dice become the fatal size on a critical, and it rolls one more of them.
      def self.fatal(instances, attack)
        die = trait_die(attack, 'fatal')

        return instances unless die && instances.first

        base = instances.first.dup
        count = base['dice'].to_a.sum { |one| one.first.to_i }
        base['dice'] = [ [ count + 1, "d#{die}" ] ]

        [ base ] + instances.drop(1)
      end

      def self.fatal_formula(formula, attack)
        die = trait_die(attack, 'fatal')

        return formula unless die

        formula.to_s.sub(/(\d*)d(\d+)/) { "#{($1.empty? ? 1 : $1.to_i) + 1}d#{die}" }
      end

      def self.trait_die(attack, name)
        found = Array(attack['traits']).map(&:to_s).find { |one| one.start_with?("#{name}-") }

        found ? found[/d(\d+)\z/, 1].to_i : nil
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
