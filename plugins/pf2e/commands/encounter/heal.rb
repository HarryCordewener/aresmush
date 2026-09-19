module AresMUSH
  module Pf2e
    class PF2HealPlayerCmd
      include CommandHandler

      attr_accessor :target, :damage, :action

      # `heal <who>=<how much>` or `<how much> <what you did>`. What the healer was doing decides
      # whether a bonus to healing applies - Robust Health recovers more from Treat Wounds than from a
      # potion - the same way a kind of damage decides what resists it.
      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.target = trimmed_list_arg(args.arg1)

        amount, _, named = args.arg2.to_s.strip.partition(' ')

        self.damage = integer_arg(amount)
        self.action = named.strip.empty? ? nil : named.strip
      end

      def required_args
        [ self.target, self.damage ]
      end

      def check_is_approved
        return nil if (enactor.is_admin? || enactor.is_approved?)
        return t('dispatcher.not_allowed')
      end

      def check_valid_damage
        return nil if self.damage > 0
        return t('pf2e.bad_value', :item => 'healing amount')
      end

      def handle

        # This command does not check to see if players are capable of healing.
        # It may be necessary to lock this command if players are in an encounter.

        targets = ActiveEffects.targets(client, enactor, self.target)

        return if targets.empty?

        ok_char_list = targets.map do |holder|
          Pf2e::Harm.heal(holder, self.damage, Pf2e.circumstances([ self.action ].compact))
          holder.name
        end

        client.emit_success t('pf2e.healing_applied_ok', :list => ok_char_list.sort.join(", "), :amount => self.damage)

      end


    end
  end
end
