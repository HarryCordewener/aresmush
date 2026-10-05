module AresMUSH
  module Pf2emagic
    # prepare/<book> [<rank>=]<spell>: the day's pick from a book a feat keeps, such as
    # prepare/esotericpolymath. The switch is the book's own, from its feat's data.
    class PF2PrepareFromBookCmd
      include CommandHandler

      attr_accessor :rank, :spell_name

      def parse_args
        if cmd.args.to_s.include?("=")
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)

          self.rank = trim_arg(args.arg1)
          self.spell_name = titlecase_arg(args.arg2)
        else
          self.spell_name = titlecase_arg(cmd.args)
        end
      end

      def required_args
        [ self.spell_name ]
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        outcome = Pf2emagic.pick_from_book(enactor, cmd.switch, self.spell_name, self.rank)

        return if Pf2e::CharState.emit_error!(client, outcome)

        pick = outcome.state

        client.emit_success t("pf2emagic.pick_#{pick['as']}", :spell => pick['spell'], :rank => pick['rank'])
      end
    end
  end
end
