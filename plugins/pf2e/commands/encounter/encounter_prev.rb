module AresMUSH
  module Pf2e

    class PF2EncounterPrevCmd
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

        return client.emit_failure(t('pf2e.explore_no_turns')) if Pf2e::Exploration.exploring?(encounter)

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        initlist = Pf2e::Combatants.all(encounter)
        moved = Pf2e::Encounters::Turn.move('prev', :size => initlist.size,
                                            :at => encounter.next_init, :round => encounter.round)

        return if Pf2e::CharState.emit_error!(client, moved)

        this_init = moved.state['current']
        next_init = moved.state['upcoming']

        encounter.update(:round => moved.state['round']) if moved.state['new_round']

        @message = t('pf2e.advance_init',
          :current => initlist[this_init].label,
          :next => initlist[next_init].label,
          :init => initlist[this_init].init.to_i,
          :round => t(moved.state['label'])
        )

        Pf2e::Encounters::Announce.tell(encounter, @message, :room => enactor_room)

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

      end


    end
  end
end
