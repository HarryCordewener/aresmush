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

        # Do it.

        encounter.update(is_active: false)

        # Whatever could not outlast the fight ends with it.
        Pf2e::ActiveEffects.encounter_ended(encounter).each do |event|
          client.emit_ooc t(event['key'], **Pf2e::CharState.symbolize(event['args']))
        end

        # So do the turn's counts, what may be used once an encounter, a trust given for this fight, and
        # the cover and concealment set on its combatants.
        Pf2e::Turns.holders(encounter).each do |holder|
          Pf2e::TurnState.reset(holder, 'encounter')
          Pf2e::TurnState.write(holder, 'turn' => {})
        end
        encounter.update(:trusted => [], :cover => {}, :concealment => {})

        @message = t('pf2e.encounter_complete', :id => encounter.id)

        # Emit to the room.
        enactor_room.emit @message

        # Log message to the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log the message to the scene as an OOC message.
        Scenes.add_to_scene(scene, @message, Game.master.system_character, false, true)

      end
    end
  end
end
