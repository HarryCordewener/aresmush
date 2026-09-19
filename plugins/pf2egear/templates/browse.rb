module AresMUSH
  module Pf2egear

    class Pf2eBrowseGearTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :category, :list

      def initialize(char, category, list)
        @category = category
        @char = char
        @list = list

        super File.dirname(__FILE__) + "/browse.erb"
      end

      def title
        t('pf2egear.browse_title', :category => category.capitalize)
      end

      def item_list
        fmt_list = []

        @list.each_pair do |key, value|
          iname = key
          ibulk = value['bulk']
          iprice = value['price']
          fmt_list << format_item(@char, @category, iname, ibulk, iprice)
        end

        fmt_list
      end

      def header_row
        "#{left('%xhItem Name%xn', 45)}%b#{left("%xhBulk%xn", 8)}%b#{left("%xhCost%xn", 15)}"
      end

      def format_item(char, category, name, bulk, price)
        if category == ("weapons" || "armor")
          prof = Pf2e.is_proficient?(char, category, name) ? "" : "%xh%xx"
        else
          prof = ""
        end

        # A rune has no bulk of its own: it is etched onto something that does.
        fmt_bulk = bulk.nil? ? "-" : (bulk == 0.1 ? "L" : bulk.to_i)
        fmt_price = Pf2egear.display_money(price)

        "#{prof}#{left(name, 45)}%b#{left(fmt_bulk, 8)}%b#{left(fmt_price, 15)}%xn"
      end
    end
  end
end
