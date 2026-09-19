module AresMUSH
  module Pf2e

    # An action as a player reads it: what it costs, what it is, and - where using it puts an effect on
    # them - the command that takes that effect on.
    class PF2ActionViewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :name, :info

      def initialize(char, name)
        @char = char
        @name = name
        @info = Actions.info(name)

        super File.dirname(__FILE__) + "/action_view.erb"
      end

      def cost
        Actions.cost(@name)
      end

      def traits
        traits = Array(@info['traits'])

        traits.empty? ? nil : traits.map { |one| one.split('-').map(&:capitalize).join(' ') }.join(', ')
      end

      # How often it can be used, in the rules' own terms: once per day, once per 10 minutes.
      PERIODS = { 'day' => 'day', 'round' => 'round', 'turn' => 'turn', 'PT1M' => 'minute',
                  'PT10M' => '10 minutes', 'PT1H' => 'hour', 'P1W' => 'week' }.freeze

      def frequency
        often = @info['frequency']

        return nil unless often

        times = often['max'].to_i == 1 ? 'once' : "#{often['max']} times"

        "#{times} per #{PERIODS[often['per'].to_s] || often['per']}"
      end

      # Where its text is: its own, or the feat's for a feat that is an action.
      def description
        text = @info['description'] || Global.read_config('pf2e_feats', @name, 'shortdesc')

        text.to_s
      end

      def effect
        @info['self_effect']
      end

      def lasts
        duration = ActiveEffects.info(effect)['duration'] || {}

        return 'until it is ended' if duration['unit'].to_s == 'unlimited'
        return 'until the encounter ends' if duration['unit'].to_s == 'encounter'

        "#{duration['value']} #{duration['unit']}"
      end

      # Whether the one looking can use it, and if not, why - so the command below it is not offered to
      # someone it would refuse.
      def usable?
        Actions.usable(@char, @name).ok?
      end
    end
  end
end
