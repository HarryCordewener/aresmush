module AresMUSH
  module Pf2e

    class PF2DisplayCombatSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.char_not_found')
          return
        end

        outcome = Pf2e::Sheet.viewable?(enactor, char, 'combat')
                    .and_then { Pf2e::Sheet.available(char, 'combat') }

        if outcome.err?
          client.emit_failure t(outcome.key, outcome.args.transform_keys(&:to_sym))
          return
        end

        rendered = Pf2e::SheetReads.holding(char) { PF2CombatSheetTemplate.new(char, client).render }

        client.emit rendered
      end

    end

  end
end
