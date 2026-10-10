module AresMUSH
  module Pf2e

    # What a creature's ability deals and the save against it, read from its stat block's words:
    # Constrict's "(2d10+17) bludgeoning, DC 40 Fortitude", or a breath's "deals 12d6 fire damage to each
    # creature within the area (DC 34 Reflex save)".
    #
    # Such a save is basic, as an area's and a Constrict's are. An ability whose words give the outcomes
    # one by one is not, and is left to the GM.
    module CreatureAbilities

      FORMULA = '\d+d\d+(?:\s*[+-]\s*\d+)?'.freeze

      LISTED = /\A\(?(?<formula>#{FORMULA})\)? (?<type>[a-z]+)(?: damage)?, DC (?<dc>\d+) (?:basic )?(?<save>Fortitude|Reflex|Will)/

      TOLD = /(?<formula>#{FORMULA}) (?<type>[a-z]+) damage[^%]{0,200}?\(DC (?<dc>\d+) (?:basic )?(?<save>Fortitude|Reflex|Will)/

      OUTCOMES = /Critical Success|Critical Failure/

      #   { 'formula' => '2d10+17', 'type' => 'bludgeoning', 'dc' => 40, 'save' => 'fortitude' }, or nil
      def self.damage_save(text)
        text = text.to_s

        return nil if text.match?(OUTCOMES)

        found = text.match(LISTED) || text.match(TOLD)

        return nil unless found && found[:type] != 'persistent'

        { 'formula' => found[:formula].delete(' '), 'type' => found[:type], 'dc' => found[:dc].to_i,
          'save' => found[:save].downcase }
      end
    end
  end
end
