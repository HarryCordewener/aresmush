module AresMUSH
  module Pf2e

    class PF2EncounterEndCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
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

        Pf2e::Encounters::Ending.end!(encounter).each do |event|
          client.emit_ooc Pf2e::Telling.render(event)
        end

        encounter = PF2Encounter[encounter.id]
        Pf2e::Encounters::Announce.tell(encounter, t('pf2e.encounter_complete', :id => encounter.id), :room => enactor_room)

      end
    end
  end
end
