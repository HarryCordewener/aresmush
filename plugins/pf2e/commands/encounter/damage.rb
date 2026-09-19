module AresMUSH
  module Pf2e
    class PF2DamagePlayerCmd
      include CommandHandler

      attr_accessor :target, :damage, :is_ndc, :kind

      # `damage <who>=<how much>` or `<how much> <kind>`, so a resistance has something to resist. A
      # kind nobody names is damage of no kind, which nothing resists.
      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.target = list_arg(args.arg1)

        amount, _, named = args.arg2.to_s.strip.partition(' ')

        self.damage = integer_arg(amount)
        self.kind = named.strip.empty? ? nil : named.strip.downcase
        self.is_ndc = cmd.switch_is?("ndc")
      end

      def required_args
        [ self.target, self.damage ]
      end

      def check_valid_damage
        return nil if self.damage > 0
        return t('pf2e.bad_value', :item => 'damage')
      end

      def handle

        # Staff can damage anyone, anytime; a GM, whoever is in their encounter. A target may be a
        # combatant's id.
        encounter = Pf2e::Combatants.encounter_here(enactor)

        if !enactor.is_admin? && !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        targets = ActiveEffects.targets(client, enactor, self.target)

        return if targets.empty?

        if !enactor.is_admin? && !Pf2e.can_damage_pc?(enactor, targets.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        # The /ndc switch means nothing unless the enactor may kill a character: it says whether damage
        # can bring on the Dead condition.
        is_dc = self.is_ndc ? false : enactor.has_permission?("kill_pc")

        ok_char_list = targets.map do |holder|
          Pf2e::Harm.damage(holder, self.damage, self.kind, :is_dm => is_dc)

          unless Pf2e.npc?(holder)
            Login.notify holder, :pf2_damage, t('pf2e.you_took_damage', :amount => self.damage, :source => enactor.name), 0
          end

          holder.name
        end

        client.emit_success t('pf2e.damage_applied_ok', :list => ok_char_list.sort.join(", "), :amount => self.damage)

      end

    end
  end
end
