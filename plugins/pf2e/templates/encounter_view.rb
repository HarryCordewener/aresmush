module AresMUSH
  module Pf2e

    class PF2EncounterViewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      def initialize(encounter, client)
        @encounter = encounter
        @client = client

        super File.dirname(__FILE__) + "/encounter_view.erb"
      end

      def title
        t(exploring? ? 'pf2e.exploration_view_title' : 'pf2e.initiative_view_title', :id => @encounter.id)
      end

      # An exploration has no initiative; it lists what each is doing instead.
      def exploring?
        Pf2e::Exploration.exploring?(@encounter)
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def header_line
        return "%b#{left("Id", 4)}%b#{left("Name", 24)}%b#{left("Activity", 20)}%b#{left("Conditions", 25)}" if exploring?

        "%b#{left("Id", 4)}#{left("Init", 5)}%b#{left("Name", 24)}%b#{left("Conditions, cover", 40)}"
      end

      def initiative_list

        list = []

        Pf2e::Combatants.all(@encounter).each do |one|
          list << format_init_list_item(one)
        end

        list

      end

      # A combatant's id, what it is under, and the cover and concealment set on it.
      def format_init_list_item(one)
        initiative = one.init.to_i
        name = one.label
        holder = one.holder
        number = one.number
        conditions = holder ? Pf2e.condition_labels(holder, false) : []
        cover = (@encounter.cover || {})[number.to_s]
        concealment = (@encounter.concealment || {})[number.to_s]
        said = conditions + [ cover ? "#{cover} cover" : nil, concealment ].compact

        if exploring?
          activity = holder.respond_to?(:exploration_activity) ? holder.exploration_activity : nil
          return "%b#{left("##{number}", 4)}%b#{left(name, 24)}%b#{left(activity || '-', 20)}%b#{left(conditions.join(", "), 25)}"
        end

        "%b#{left("##{number}", 4)}#{left(initiative, 5)}%b#{left(name, 24)}%b#{left(said.join(", "), 40)}"
      end

      def difficulty
        exploring? ? '' : Pf2e::Difficulty.shown(@encounter)
      end

      def trusted
        Array(@encounter.trusted)
      end

    end
  end
end
