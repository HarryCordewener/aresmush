module AresMUSH
  module Pf2e

    # `sheet/why <figure>` - the arithmetic behind one number on the sheet.
    class PF2StatBreakdownCmd
      include CommandHandler

      attr_accessor :target, :figure

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.figure = downcase_arg(args.arg1)
        self.target = trim_arg(args.arg2)
      end

      def check_figure
        return t('pf2e.which_figure') if self.figure.blank?

        nil
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.char_not_found')
          return
        end

        outcome = Pf2e::Sheet.viewable?(enactor, char, 'combat')

        if outcome.err?
          client.emit_failure t(outcome.key, outcome.args.transform_keys(&:to_sym))
          return
        end

        found = Pf2e::Stat.identify(self.figure)

        if !found
          client.emit_failure t('pf2e.no_such_figure', :figure => self.figure)
          return
        end

        kind, name = found

        client.emit PF2StatBreakdownTemplate.new(label(kind, name), Pf2e::Stat.of(char, kind, name)).render
      end

      def label(kind, name)
        (name || kind.to_s.tr('_', ' ')).to_s.split.map(&:capitalize).join(' ')
      end
    end
  end
end
