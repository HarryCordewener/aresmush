module AresMUSH
  module Pf2e
    class PF2ConditionSetCmd
      include CommandHandler

      attr_accessor :target, :condition, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.target = trimmed_list_arg(args.arg1)
        self.condition = titlecase_arg(args.arg2)
        self.value = integer_arg(args.arg3)
      end

      def required_args
        [ self.target, self.condition ]
      end

      # Matched the way a player types it, and held as the catalogue spells it.
      def check_valid_condition
        condition_list = Global.read_config('pf2e_conditions').keys
        self.condition = Pf2e.canonical_condition(self.condition)
        return nil if condition_list.include? self.condition
        return t('pf2e.condition_not_found', :options => condition_list.sort.join(", "))
      end

      def check_valid_value
        # If self.value is set, it should be 1-5, or 0 to clear the condition.
        return nil if !self.value
        return nil if self.value.between?(0,5)
        return t('pf2e.bad_value', :item => 'a condition')
      end

      def handle

        # Staff, or the GM of the encounter the targets are in. A target may be a combatant's id.
        encounter = Pf2e::Combatants.encounter_here(enactor)
        target_list = ActiveEffects.targets(client, enactor, self.target)

        return if target_list.empty?

        unless Pf2e.can_damage_pc?(enactor, target_list.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        condition_details = Global.read_config('pf2e_conditions', self.condition)

        if condition_details['value'] && !self.value
          client.emit_failure t('pf2e.condition_needs_value')
          return
        end

        # A condition another holds in place cannot be cleared on its own: Unconscious stays while Dying
        # does. Each target answers for itself.
        _refused, done = target_list.partition do |char|
          Pf2e::CharState.emit_error!(client, Pf2e.set_condition(char, self.condition, self.value))
        end

        return if done.empty?

        client.emit_success t('pf2e.condition_set_ok',
          :condition => self.condition,
          :target => done.map { |t| t.name }.sort.join(", ")
        )

      end

    end
  end
end
