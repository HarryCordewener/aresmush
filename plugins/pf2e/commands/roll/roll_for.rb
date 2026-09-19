module AresMUSH
  module Pf2e

    class PF2RollForCommand
      include CommandHandler

      attr_accessor :mods, :dc, :string, :target, :doing

      # The same shape as `roll`: after the first slash, a number is the DC and anything else is a
      # circumstance.
      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.target = trim_arg(args.arg1)

        parts = args.arg2.to_s.split('/').map(&:strip)

        self.string = trim_arg(parts.first)
        self.mods = Pf2e.roll_terms(parts.first)

        rest = parts.drop(1).reject(&:empty?)
        numbers, words = rest.partition { |part| part.match?(/\A\d+\z/) }

        self.dc = numbers.first&.to_i
        self.doing = words
      end

      def check_valid_dc
        return nil if !self.dc
        if self.dc.between?(5,50)
          return nil
        else
          return t('pf2e.dc_must_be_integer')
        end
      end

      def required_args
        [ self.mods, self.target ]
      end

      def handle
        subject = Pf2e.get_character(self.target, enactor)

        if !subject
          client.emit_failure t('pf2e.not_found')
          return
        end

        roll = Pf2e.parse_roll_string(subject, self.mods, Pf2e.circumstances(self.doing))
        list = roll['list']
        result = roll['result']
        total = roll['total']

        # Determine degree of success if DC is given
        degree = self.dc ? Pf2e.get_degree(list, result, total, self.dc, roll['checks']) : ""

        dc_string = self.dc ? "against DC #{self.dc} " : ""

        roll_msg = t('pf2e.die_roll',
                  :roller => "%xy#{enactor.name}%xn (for %xh#{subject.name}%xn)",
                  :string => self.string,
                  :dc => dc_string,
                  :parsed => result.join(" + "),
                  :result => total,
                  :degree => degree
                )

        Pf2e.broadcast_roll(enactor_room, roll_msg)

        Global.logger.info "PF2 ROLL: #{roll_msg}"
      end

    end
  end
end
