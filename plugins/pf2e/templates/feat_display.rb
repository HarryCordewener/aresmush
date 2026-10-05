module AresMUSH
  module Pf2e
    class PF2eFeatDisplay < ErbTemplateRenderer
      include CommonTemplateFields
      include PagedTemplate

      attr_accessor :paginator, :title

      def initialize(paginator, title, cmd = nil)
        @paginator = paginator
        @title = title
        @cmd = cmd

        super File.dirname(__FILE__) + "/feat_display.erb"
      end

      def title
        @title
      end

    end
  end
end
