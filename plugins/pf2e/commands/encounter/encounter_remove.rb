module AresMUSH
  module Pf2e

    class PF2EncounterRemoveCmd
      include CommandHandler

      attr_accessor :name, :encounter_id

      def parse_args
        args = trimmed_list_arg(cmd.args, "=")

        # If only one arg is given, encounter_id is the nil.
        args.unshift(nil) unless args[1]

        self.encounter_id = args[0] ? integer_arg(args[0]) : nil
        self.name = args[1]
      end

      def required_args
        [ self.name ]
      end

      def handle
        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene
        found = Pf2e::Encounters::Finder.find(enactor, scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        found = Pf2e::Combatants.find(encounter, self.name)

        return if Pf2e::CharState.emit_error!(client, found)

        leaving = found.state

        # Whoever leaves holds nobody any longer.
        freed = Pf2e::Telling.lines(Pf2e::Holding.let_go(encounter, leaving.label))
        Pf2e::Encounters::Announce.tell(encounter, freed.join('%r'), :room => enactor_room, :story => true) if freed.any?

        Pf2e::Combatants.leave(encounter, leaving.number)

        # A creature removed from the fight is gone, with whatever it was under.
        leaving.holder.delete if leaving.creature?

        client.emit_success t('pf2e.encounter_remove_ok', :encounter => encounter.id, :name => leaving.label)

      end

    end
  end
end
