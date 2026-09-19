module AresMUSH
  module Pf2e

    # The actions a character can use, grouped by what they cost, with the ones that put an effect on them
    # marked - those are the ones `action/use` does something with.
    class PF2ActionAvailableTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :mode

      def initialize(char, mode)
        @char = char
        @mode = mode
        @names = Actions.available(char, mode)

        super File.dirname(__FILE__) + "/action_available.erb"
      end

      def title
        heading = @mode ? @mode.capitalize : 'All'

        "#{heading} Actions For #{@char.name}"
      end

      # What each group is called, in the order a turn uses them.
      GROUPS = [ [ 'one action', 'One Action' ], [ 'two actions', 'Two Actions' ],
                 [ 'three actions', 'Three Actions' ], [ 'free action', 'Free Actions' ],
                 [ 'reaction', 'Reactions' ], [ 'activity', 'Activities' ] ].freeze

      def groups
        by_cost = @names.group_by { |name| Actions.cost(name) }

        GROUPS.map { |cost, label| [ label, Array(by_cost[cost]) ] }.reject { |_label, names| names.empty? }
      end

      def any?
        @names.any?
      end

      # Two to a line, marking the ones that put an effect on whoever uses them.
      def rows(names)
        names.map { |name| left(Actions.info(name)['self_effect'] ? "#{name}*" : name, 38) }
             .each_slice(2).map { |pair| "%b%b#{pair.join}" }
      end
    end
  end
end
