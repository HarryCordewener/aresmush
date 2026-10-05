module AresMUSH
  module Pf2e
    class PF2SkillsListTemplate < ErbTemplateRenderer
      include CommonTemplateFields
      include PagedTemplate

      attr_accessor :sections

      # sections is a list of [heading, items] pairs; a nil heading prints the items on their own.
      # Given a paginator of more than one page, the footer is its page bar and next-page hint.
      # A note prints under the list, set apart by a blank line either side.
      def initialize(sections, title = nil, paginator = nil, cmd = nil, note = nil)
        @sections = sections
        @title = title
        @paginator = paginator
        @cmd = cmd
        @note = note

        super File.dirname(__FILE__) + "/skills_list.erb"
      end

      def title
        @title || t('pf2e.skills_list_title')
      end

      def note_block
        @note ? "%r%r#{@note}" : ""
      end

      def list_footer
        @paginator && @paginator.total_pages > 1 ? page_footer : footer
      end

      def body
        @sections.map { |heading, items| format_section(heading, items) }.join("%r")
      end

      def format_section(heading, items)
        heading_line = heading ? "%r#{title_color}#{heading}%xn" : ""

        heading_line + items.each_with_index.map { |item, i| format_page_items(item, i) }.join
      end

      def format_page_items(item, i)
        linebreak = i % 3 == 0 ? "%r" : ""
        "#{linebreak}#{left(item,26)}"
      end

    end
  end
end
