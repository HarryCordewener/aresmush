module AresMUSH
  module Pf2e

    # Where a figure on the sheet came from.
    #
    # A modifier the stacking rule switched off is still shown, marked, because "you already have a
    # better item bonus" is the answer to the question a player is asking when they wonder why their
    # new ring changed nothing.
    class PF2StatBreakdownTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      def initialize(label, breakdown)
        @label = label
        @breakdown = breakdown

        super File.dirname(__FILE__) + "/stat_breakdown.erb"
      end

      def title
        "#{@label}: #{signed(@breakdown['total'])}"
      end

      def base
        "#{left("#{item_color}Base%xn", 34)}#{@breakdown['base']}"
      end

      def rows
        @breakdown['modifiers'].map { |row| format_row(row) }
      end

      def format_row(row)
        note = row['enabled'] ? '' : ' (overridden)'

        "#{left("#{row['source']} #{item_color}[#{row['type']}]%xn", 34)}#{signed(row['value'])}#{note}"
      end

      # Bonuses the character has but is not getting right now, because they hold only while doing
      # something in particular. Naming the circumstance is the point: it is how a player learns that
      # their Skeleton Key does nothing until they say they are picking a lock.
      def conditional
        Array(@breakdown['conditional']).map { |row| format_conditional(row) }
      end

      def format_conditional(row)
        "#{left("#{row['source']} #{item_color}[#{row['type']}]%xn", 34)}" \
          "#{signed(row['value'])} #{item_color}only with%xn #{Array(row['when']).map { |w| describe(w) }.join(', ')}"
      end

      # A predicate as something a player can read. A plain requirement is printed as it stands; a
      # compound one is left in its own shape rather than turned into prose that might mislead.
      def describe(statement)
        statement.is_a?(String) ? statement : statement.to_s
      end

      def signed(value)
        value.to_i.negative? ? value.to_s : "+#{value}"
      end
    end
  end
end
