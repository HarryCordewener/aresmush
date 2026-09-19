module AresMUSH
  module Pf2e

    # What a character is under, how long each has left, and what it brought with it.
    class PF2EffectListTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char

      def initialize(char)
        @char = char
        @effects = ActiveEffects.on(char).sort_by(&:name)

        super File.dirname(__FILE__) + "/effect_list.erb"
      end

      def title
        "Effects On #{@char.name}"
      end

      def any?
        @effects.any?
      end

      def rows
        @effects.map { |effect| format_row(effect) }
      end

      def format_row(effect)
        rank = effect.level.to_i > 0 ? " (rank #{effect.level})" : ''
        badge = effect.badge ? " [#{effect.badge}]" : ''
        from = effect.granted_by ? ", from #{effect.granted_by}" : ''
        by = effect.applied_by ? " - #{effect.applied_by}" : ''

        "%b%b#{item_color}#{effect.name}%xn#{rank}#{badge}: #{ActiveEffects.remaining(effect)}#{from}#{by}"
      end

      # The conditions they have, since an effect's own consequences are usually one.
      def conditions
        labels = Pf2e.condition_labels(@char)

        labels.empty? ? nil : "%b%b#{labels.join(', ')}"
      end
    end

    # What an effect does: how long it lasts, what it asks, and its own words.
    class PF2EffectViewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :name, :info

      def initialize(name, info)
        @name = name
        @info = info

        super File.dirname(__FILE__) + "/effect_view.erb"
      end

      def lasts
        duration = @info['duration'] || {}

        return 'until it is ended' if duration['unit'].to_s == 'unlimited'
        return 'until the encounter ends' if duration['unit'].to_s == 'encounter'

        "#{duration['value']} #{duration['unit']}"
      end

      def level
        @info['level']
      end

      # What someone applying it has to say, if anything.
      def asks
        sets = Array(@info['rules']).select { |row| row['key'] == 'ChoiceSet' }

        return nil if sets.empty?

        sets.map { |row|
          listed = Array(row['choices']).select { |one| one.is_a?(Hash) }.map { |one| one['value'] }

          listed.empty? ? 'a choice' : listed.join(' / ')
        }.join('; ')
      end

      # How many of its rules this engine reads, so nobody mistakes an effect that does nothing here for
      # one that does nothing at all.
      def read
        count = Array(@info['rules']).size

        count.zero? ? 'none of its rules are read here yet' : "#{count} rules read"
      end

      def description
        @info['description'].to_s
      end
    end
  end
end
