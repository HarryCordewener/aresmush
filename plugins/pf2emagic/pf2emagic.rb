$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2emagic

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2emagic", "shortcuts")
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when "addspell"
        return PF2ChargenSpellsCmd
      when "prepared"
        return PF2DisplayPreparedCmd
      when "prepare"
        # A switch names a book a feat keeps (prepare/esotericpolymath), or a feat that changes what
        # a slot holds (prepare/splitslot, prepare/spellmastery). Each feat's data names its own.
        return PF2PrepareSpellCmd unless cmd.switch
        return SlotFeats.switch?(cmd.switch) ? PF2PrepareSlotFeatCmd : PF2PrepareFromBookCmd
      when "unprepare"
        return cmd.switch ? PF2UnprepareSlotFeatCmd : PF2UnprepareSpellCmd
      when "spell"
        case cmd.switch
        when "search"
          return PF2SearchSpellCmd
        when "eligible"
          return PF2SpellEligibleCmd
        when "learn"
          return PF2LearnSpellCmd
        when nil
          return PF2DisplaySpellCmd
        end
      when "magic"
        return PF2MagicDisplayCmd
      when "spellbook"
        return PF2MagicSpellbookCmd
      when "repertoire"
        return PF2MagicRepertoireCmd
      when 'dfont'
        return PF2DivineFontCmd
      end
    end

    def self.get_event_handler(event_name)
      nil
    end

    def self.get_web_request_handler(request)
      nil
    end

  end
end
