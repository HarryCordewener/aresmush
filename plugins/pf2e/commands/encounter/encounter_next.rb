module AresMUSH
  module Pf2e

    class PF2EncounterNextCmd
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

        initlist = Pf2e::Combatants.all(encounter)

        # Whose turn is ending, before the order moves: an effect that lasts until the end of someone's
        # turn ends now.
        ending = Pf2e::ActiveEffects.current_turn(encounter)
        ending_round = encounter.round

        moved = Pf2e::Encounters::Turn.move('next', :size => initlist.size,
                                           :at => encounter.next_init, :round => encounter.round)

        return if Pf2e::CharState.emit_error!(client, moved)

        this_init = moved.state['current']
        next_init = moved.state['upcoming']
        new_round = moved.state['new_round']

        encounter.update(:round => moved.state['round']) if new_round

        round_text = new_round ? t('pf2e.new_round', :round => moved.state['round']) : t(moved.state['label'])

        @message = t('pf2e.advance_init',
          :current => initlist[this_init].label,
          :next => initlist[next_init].label,
          :init => initlist[this_init].init.to_i,
          :round => round_text
        )

        # Emit to the room.
        enactor_room.emit @message

        # Log message to the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log the message to the scene as an OOC message.
        Scenes.add_to_scene(scene, @message, Game.master.system_character, false, true)

        # If the current initiative is a PC, shoot them a global notifier.

        holder = initlist[this_init].holder
        current_is_char = holder && !initlist[this_init].creature? ? holder : nil

        if current_is_char
          @init_msg = t('pf2e.your_init', :id => encounter.id)
          Global.notifier.notify_ooc(:char_init, @init_msg) do |c|
            c && c == current_is_char
          end
        end

        # Update the encounter object.

        encounter.update(next_init: next_init)

        # Time has passed: what ran out ends, what heals heals, what burns burns. The room is told each.
        Pf2e::Turns.advanced(encounter, ending, ending_round, initlist[this_init].label,
                             moved.state['round']).each do |event|
          notice = t(event['key'], **Pf2e::CharState.symbolize(event['args']))

          enactor_room.emit notice
          PF2Encounter.send_to_encounter(encounter, notice)
        end

        # The one whose turn it is hears what matters to it; a creature's reminder goes to the GM. Read
        # again, because the turn starting has just changed what it holds.
        holder = Pf2e::Combatants.at(encounter, this_init)&.holder

        if holder
          reminder = Pf2e::Turns.reminder(holder, moved.state['round'])
          Pf2e::Actors.of(holder).hears_own_turn? ? Login.emit_ooc_if_logged_in(holder, reminder) : client.emit_ooc(reminder)
        end

      end


    end
  end
end
