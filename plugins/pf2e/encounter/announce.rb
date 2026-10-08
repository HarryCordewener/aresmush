module AresMUSH
  module Pf2e
    module Encounters

      # What an encounter says to everyone in it: the room its scene is played in, its own log, and its
      # scene's log. Its GM may be elsewhere when they say it; the scene is where it is.
      #
      # What happens - a Strike, a spell, an effect ending as a turn starts - is the story of the scene,
      # and goes in its log as a system line, which the log kept when the scene is shared includes. The
      # bookkeeping - who joins, whose turn, cover set, the encounter starting and ending - goes in as an
      # OOC line, which the shared log leaves out. That is how the game's own combat logs.
      module Announce
        def self.tell(encounter, message, room: nil, story: false)
          scene = encounter.scene
          (scene&.room || room)&.emit message
          PF2Encounter.send_to_encounter(encounter, message)
          log(scene, message, :story => story)
        end

        def self.log(scene, message, story: false)
          return unless scene

          if story
            Scenes.add_to_scene(scene, message)
          else
            Scenes.add_to_scene(scene, message, Game.master.system_character, false, true)
          end
        end
      end
    end
  end
end
