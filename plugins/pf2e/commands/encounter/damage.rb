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

        # Staff, or the GM of the encounter here, damage whoever is in it. A target may be a combatant's id.
        encounter = Pf2e::Combatants.encounter_here(enactor)
        targets = ActiveEffects.targets(client, enactor, self.target)

        return if targets.empty?

        if !enactor.is_admin? && !Pf2e.can_damage_pc?(enactor, targets.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        # Whether the damage may kill is a Plotmaster's or staff's to say, and /ndc is them saying it may
        # not. From anyone else it never does.
        is_dc = !self.is_ndc && Pf2e::Gm.plotmaster?(enactor)

        dropped = Pf2e::Acting.report

        ok_char_list = targets.map do |holder|
          standing = Pf2e::Acting.still_up(holder)
          held = Pf2e::Harm.damage(holder, self.damage, self.kind, :is_dm => is_dc)

          Pf2e::Actors.of(holder).notify_damage(self.damage, enactor.name)
          Pf2e::Acting.dropped(Pf2e::Combatants::Combatant.new(holder, holder.name, nil), standing, dropped, held['fate'])

          holder.name
        end

        client.emit_success t('pf2e.damage_applied_ok', :list => ok_char_list.sort.join(", "), :amount => self.damage)

        # The room is told who it dropped, as a Strike tells it.
        Pf2e::Telling.lines(dropped['lines']).each { |line| enactor_room.emit line.strip }

      end

    end
  end
end
