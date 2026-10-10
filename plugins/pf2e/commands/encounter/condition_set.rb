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
        return nil if condition_list.include?(self.condition) || self.condition == Pf2e::DEAD
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

        return death(target_list, encounter) if self.condition == Pf2e::DEAD

        condition_details = Global.read_config('pf2e_conditions', self.condition)

        if condition_details['value'] && !self.value
          client.emit_failure t('pf2e.condition_needs_value')
          return
        end

        # Drained and Doomed outlast the encounter: a Plotmaster's or staff's to give a character, and
        # anyone's to ease.
        if Gm::LASTING.include?(self.condition) && !Gm.plotmaster?(enactor) &&
           target_list.any? { |char| Gm.character?(char) && self.value.to_i > Pf2e.condition_level(char, self.condition) }
          client.emit_failure t('pf2e.condition_not_lasting', :condition => self.condition)
          return
        end

        # A condition another holds in place cannot be cleared on its own: Unconscious stays while Dying
        # does. Each target answers for itself.
        _refused, done = target_list.partition do |char|
          Pf2e::CharState.emit_error!(client, Pf2e.set_condition(char, self.condition, self.value))
        end

        return if done.empty?

        # What is part of what someone is - a zombie's slowness, an effect's condition - stays while that
        # does, and whoever cleared it is told.
        kept = self.value == 0 ? done.select { |char| Pf2e.held_conditions(char).key?(self.condition) } : []
        kept.each do |char|
          client.emit_ooc t('pf2e.condition_kept', :condition => self.condition, :target => char.name,
                                                  :from => Pf2e.held_conditions(char)[self.condition]['granted_by'])
        end

        return if (done - kept).empty?

        client.emit_success t(self.value == 0 ? 'pf2e.condition_cleared_ok' : 'pf2e.condition_set_ok',
          :condition => self.condition,
          :target => (done - kept).map { |t| t.name }.sort.join(", ")
        )

      end

      # `dead` is a Plotmaster's or staff's to say of a character, and `dead/0` any GM's to take back.
      # Either is told as what happened in the fight.
      def death(target_list, encounter)
        return client.emit_failure(t('pf2e.dead_not_creature')) unless target_list.all? { |char| Gm.character?(char) }

        raising = self.value == 0

        unless raising || Gm.plotmaster?(enactor)
          return client.emit_failure(t('pf2e.condition_not_lasting', :condition => self.condition))
        end

        changed = target_list.select { |char| Pf2e.dead?(char) == raising }
        changed.each { |char| raising ? Pf2eHP.revive(char) : Pf2eHP.kill(char) }

        return client.emit_failure(t('pf2e.dead_nothing_to_do')) if changed.empty?

        lines = changed.map { |char| t(raising ? 'pf2e.act_revived' : 'pf2e.act_dead', :target => char.name).strip }.join('%r')

        if encounter
          Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], lines, :room => enactor_room, :story => true)
        else
          enactor_room.emit lines
        end
      end

    end
  end
end
