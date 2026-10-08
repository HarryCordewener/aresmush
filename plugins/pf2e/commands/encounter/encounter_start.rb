module AresMUSH
  module Pf2e

    # `+e/start [<stat>][=<encounter id>]` - starts an encounter in the scene, rolling initiative on the
    # stat, and carrying on from the encounter named: whoever was in that one starts this one as they left
    # it. Started during an exploration, it ends the exploration, carries on from it, and brings everyone
    # exploring into the fight.
    class PF2InitiateCombatCmd
      include CommandHandler

      attr_accessor :init, :from

      def parse_args
        stat, _, from = cmd.args.to_s.partition('=')

        self.init = titlecase_arg(stat.strip.empty? ? nil : stat.strip)
        self.from = from.strip.delete_prefix('#').empty? ? nil : from.strip.delete_prefix('#')
      end

      # Only a GM starts an encounter: staff, or anyone whose role may run them.
      def check_is_gm
        return nil if enactor.is_admin? || enactor.has_permission?('run_encounters')

        t('pf2e.encounter_start_gm_only')
      end

      def check_from
        return nil unless self.from
        return nil if PF2Encounter[self.from]

        t('pf2e.bad_id', :type => 'encounter')
      end

      def check_is_approved
        return nil if enactor.is_approved?
        return t('dispatcher.not_allowed')
      end

      def handle
        # Demand that the organizer be in a scene.

        scene = enactor_room.scene

        if !scene
          client.emit_failure t('pf2e.must_be_in_scene')
          return
        end

        # Only one encounter can be active in a scene at a time. An exploration gives way to the fight
        # that starts during it, which carries on from it.

        active_encounter = PF2Encounter.scene_active_encounter(scene)
        exploring = Exploration.exploring?(active_encounter) ? active_encounter : nil

        if active_encounter && !exploring
          client.emit_failure t('pf2e.scene_has_active_encounter', :id => active_encounter.id)
          return
        end

        # Initiative is Perception unless the GM names something else.
        init_stat = Pf2e.initiative_stat(self.init || 'Perception')

        unless init_stat
          client.emit_failure t('pf2e.bad_initiative_stat', :stat => self.init)
          return
        end

        # Do it.

        if exploring
          Pf2e::Encounters::Ending.end!(exploring).each { |event| client.emit_ooc Pf2e::Telling.render(event) }
          tell(scene, PF2Encounter[exploring.id], t('pf2e.explore_ended', :id => exploring.id))
        end

        encounter = PF2Encounter.create(
          owner: enactor,
          organizer: enactor.name,
          scene: scene,
          init_stat: init_stat,
          carries_on_from: exploring ? exploring.id : self.from
        )

        tell(scene, encounter, PF2EncounterStart.new(encounter).render)

        # Everyone exploring comes into the fight, rolling initiative as their activity has it.
        Exploration.bring_into(encounter, PF2Encounter[exploring.id]).each { |line| tell(scene, encounter, line) } if exploring
      end

      # To the room, the encounter's log and the scene's, as an OOC line.
      def tell(scene, encounter, message)
        enactor_room.emit message
        PF2Encounter.send_to_encounter(encounter, message)
        Scenes.add_to_scene(scene, message, Game.master.system_character, false, true)
      end

    end

  end
end
