module AresMUSH
  module Pf2e

    # What a character's gear and feats offer, and which of it is on.
    #
    # An option is on by default, because an item you are wearing should do what it says. One a player
    # has switched by hand says so, so they can tell their own choice from the default.
    class PF2RollOptionsTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      # `combatant` is who a GM is reading them for in an encounter - `#5` - or nothing for a character
      # reading their own.
      def initialize(declared, combatant = nil)
        @declared = declared
        @combatant = combatant

        super File.dirname(__FILE__) + "/roll_options.erb"
      end

      def any?
        @declared.any?
      end

      def title
        @combatant ? "Circumstances #{@combatant} Has" : 'Circumstances Your Gear And Feats Offer'
      end

      # The command that switches one, for whoever is reading.
      def switch
        @combatant ? "+e/option #{@combatant}=<name>/off" : 'sheet/option <name>=off'
      end

      def back
        @combatant ? '/default' : '=default'
      end

      def none
        @combatant ? "Nothing #{@combatant} has offers a circumstance of its own." : 'Nothing you are carrying offers a circumstance of its own.'
      end

      def rows
        @declared.sort_by { |one| one['option'].to_s }.map { |one| format_row(one) }
      end

      def format_row(one)
        state = one['on'] ? "#{item_color}on%xn" : 'off'
        note = one['chosen'] ? ' (your choice)' : ''
        note = ' (needs something we cannot check)' if !one['reachable'] && !one['chosen']
        note = ' (locked)' if one['locked']

        "%b%b#{left(one['option'], 40)}#{left(state, 6)}#{one['source']}#{note}#{choices(one)}"
      end

      # An option with a choice among values says which is set and what else it could be.
      def choices(one)
        values = Array(one['choices']).map { |each| each['value'] }

        return '' if values.empty?

        "\n%b%b%b%bset to #{item_color}#{one['selected']}%xn, of #{values.join(', ')}"
      end
    end
  end
end
