module AresMUSH
  module Scenes
    
    def self.custom_char_card_fields(char, viewer)

      base_info = char.pf2_base_info
      faith_info = char.pf2_faith

      return_hash = {
        ancestry: base_info['ancestry'],
        heritage: base_info['heritage'],
        charclass: base_info['charclass']
      }

      # Some characters will have rules they live by, add to character card if present.
      edicts = faith_info['edicts']
      anathema = faith_info['anathema']

      return_hash[:edicts] = edicts.join("%r") if edicts
      return_hash[:anathema] = anathema.join("%r") if anathema

      # A few characters have things players need to know about in combat.
      # Warnings like these should take the form warn_ so that they cna be matched by a CSS class if desired.

      if Array(char.pf2_special).include? Pf2e::Effects::VOID_HEALING_SPECIAL
        return_hash[:warn_nh] = "Void Healing: Harmed by vitality and healed by void effects."
      end

      return_hash
    end
  end
end
