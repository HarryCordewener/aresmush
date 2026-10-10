module AresMUSH
  module Pf2e

    # `+e/explore[=<encounter id>]` - starts an exploration in the scene: an encounter without initiative
    # or turns, carrying on from the encounter named, as a fight can. A fight started while it runs takes
    # over from it (`+e/start`).
    class PF2ExploreCmd
      include CommandHandler

      attr_accessor :from

      def parse_args
        self.from = cmd.args.to_s.strip.delete_prefix('=').strip.delete_prefix('#')
        self.from = nil if self.from.empty?
      end

      def check_is_approved
        return nil if enactor.is_approved?

        t('dispatcher.not_allowed')
      end

      def check_from
        return nil unless self.from
        return nil if PF2Encounter[self.from]

        t('pf2e.bad_id', :type => 'encounter')
      end

      def handle
        scene = enactor_room.scene

        return client.emit_failure(t('pf2e.must_be_in_scene')) unless scene

        active = PF2Encounter.scene_active_encounter(scene)

        if active
          key = Exploration.exploring?(active) ? 'pf2e.explore_already' : 'pf2e.explore_fight_on'
          return client.emit_failure(t(key, :id => active.id))
        end

        encounter = PF2Encounter.create(owner: enactor, organizer: enactor.name, scene: scene,
                                        mode: Exploration::MODE, carries_on_from: self.from)

        message = t('pf2e.explore_started', :id => encounter.id, :gm => enactor.name)

        enactor_room.emit message
        PF2Encounter.send_to_encounter(encounter, message)
        Scenes.add_to_scene(scene, message, Game.master.system_character, false, true)
      end
    end
  end
end
