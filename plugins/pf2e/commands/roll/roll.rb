module AresMUSH
  module Pf2e

    class PF2RollCommand
      include CommandHandler

      attr_accessor :mods, :dc, :string, :doing

      # `roll <dice + modifiers>[/<dc>][/<what you are doing>]`, in any order after the first slash: a
      # number is the DC and anything else is a circumstance, so a player need not remember which
      # comes first.
      def parse_args
        parts = cmd.args.to_s.split('/').map(&:strip)

        self.string = trim_arg(parts.first)
        self.mods = Pf2e.roll_terms(parts.first)

        rest = parts.drop(1).reject(&:empty?)
        numbers, words = rest.partition { |part| part.match?(/\A\d+\z/) }

        self.dc = numbers.first&.to_i
        self.doing = words
      end

      def required_args
        [ self.string ]
      end

      def check_valid_dc
        return nil if !self.dc
        if self.dc.between?(5,50)
          return nil
        else
          return t('pf2e.dc_must_be_integer')
        end
      end

      def handle

        roll = Pf2e.parse_roll_string(enactor, self.mods, Pf2e.circumstances(self.doing))
        list = roll['list']
        result = roll['result']
        total = roll['total']

        # Determine degree of success if DC is given
        degree = self.dc ? Pf2e.get_degree(list, result, total, self.dc, roll['checks']) : ""

        dc_string = self.dc ? "against DC #{self.dc} " : ""
        doing_string = self.doing.any? ? " (#{self.doing.join(', ')})" : ""

        roll_msg = t('pf2e.die_roll',
                  :roller => "%xh#{enactor.name}%xn",
                  :string => "#{self.string}#{doing_string}",
                  :dc => dc_string,
                  :parsed => result.join(" + "),
                  :result => total,
                  :degree => degree
                )

        if cmd.switch == "me"
          client.emit "(%xgPRIVATE%xn) " + roll_msg
        else
          Pf2e.broadcast_roll(enactor_room, roll_msg)
        end

        Global.logger.info "PF2 ROLL: #{roll_msg}"
      end

    end
  end
end
