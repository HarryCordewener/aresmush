module AresMUSH
  module Pf2e

    class PF2EncounterStart < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_start.erb"
      end

      def title
        t('pf2e.encounter_start_title')
      end

      def init_stat
        @encounter.init_stat
      end

      def encounter_id
        @encounter.id
      end

      def organizer
        PF2Encounter.gm_of(@encounter)&.name || @encounter.organizer
      end

      # What the room is to do: join, or - for a fight that takes over from an exploration, which has
      # brought everyone in already - nothing but play on.
      def instruction
        from = @encounter.carries_on_from ? PF2Encounter[@encounter.carries_on_from] : nil
        key = Exploration.exploring?(from) ? 'pf2e.encounter_start_from_exploring' : 'pf2e.encounter_start_join'

        t(key, :help => "#{title_color}help initiative%xn")
      end

      def roll_init_cmd
        "init/join #{encounter_id}[=<alternate stat>]"
      end

    end
  end
end
