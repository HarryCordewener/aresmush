module AresMUSH
  module Pf2e

    # Hit points an effect or a condition takes, rather than damage dealt: Strain Mind costs hit points to
    # use, and being drained costs more each time it worsens.
    #
    # Foundry's `LoseHitPoints` (`lose-hit-points.ts`): the loss happens as the effect begins, is not
    # damage - no resistance, no temporary hit points soaking it - and, where the rule says the hit points
    # are not recoverable, they cannot be healed while it lasts. A rule reevaluated on update, which is
    # Drained's, loses the difference whenever its value rises.
    #
    # Foundry keeps current hit points apart from the maximum, so lowering the maximum leaves the current
    # alone and Drained has to take both. Here what is kept is the damage taken, so lowering the maximum
    # already lowers what is left: the loss is only what goes beyond the drop in the maximum the same
    # change made, or Drained would be counted twice.
    module HitPointLoss

      # What a source's rules would take, worked out against its own item: a condition's badge, an
      # effect's rank.
      def self.rows(char, name, rules, item)
        source = Effects.source(name, Array(rules), 'item' => item)

        Rules.contributions([ source ], 'LoseHitPoints', Effects.options(char), Effects.context(char))
      end

      def self.lose(char, amount, max_before = nil)
        hp = char.hp

        return unless hp

        max = Pf2eHP.get_max_hp(char)
        amount -= [ max_before.to_i - max, 0 ].max if max_before

        return unless amount.positive?

        hp.update(:damage => [ hp.damage.to_i + amount, max ].min)
      end

      def self.max_hp(char)
        char.hp ? Pf2eHP.get_max_hp(char) : nil
      end

      # An effect has begun. `max_before` is the maximum before it did.
      def self.effect_began(char, effect, max_before = nil)
        total = rows(char, effect.name, ActiveEffects.info(effect.name)['rules'], ActiveEffects.instance_item(effect))
                  .sum { |one| one['value'] }

        lose(char, total, max_before)
      end

      # A condition was set or changed value. Only a rule that says it is reevaluated loses again as the
      # value rises; any other took what it takes when the condition first arrived.
      def self.condition_changed(char, name, before, after, max_before = nil)
        rules = Global.read_config('pf2e_conditions', name, 'rules')

        return unless takes?(rules)

        worth = ->(value) { rows(char, name, rules, 'badge' => { 'value' => value.to_i }) }
        now = worth.call(after)
        was = before.nil? ? [] : worth.call(before)

        total = now.each_with_index.sum do |one, index|
          prior = was[index]

          next 0 if prior && !one['again']

          one['value'] - (prior ? prior['value'] : 0)
        end

        lose(char, total, max_before)
      end

      def self.takes?(rules)
        Array(rules).any? { |row| row['key'] == 'LoseHitPoints' }
      end

      # What cannot be healed while the thing that took it lasts: a Quicksilver Mutagen's cost.
      def self.unrecoverable(char)
        Rules.contributions(Effects.sources(char), 'LoseHitPoints', Effects.options(char), Effects.context(char))
             .reject { |one| one['recoverable'] }.sum { |one| one['value'] }
      end
    end
  end
end
