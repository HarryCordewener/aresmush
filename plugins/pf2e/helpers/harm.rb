module AresMUSH
  module Pf2e

    # Damage and healing, for a character or a creature in an encounter.
    #
    # A character's hit points are `Pf2eHP`, which knows about dying, wounds and temporary hit points; a
    # creature's are its stat block's maximum less what it has taken. What either resists is worked out
    # before anything lands.
    module Harm

      # `{ 'amount' => what they took after resistances, 'applied' => the resistances that counted }`
      def self.damage(holder, amount, kind = nil, is_dm: false)
        return Npcs.damage(holder, amount, kind) if Pf2e.npc?(holder)

        held = kind ? IWR.apply(IWR.of(holder), amount.to_i, kind) : { 'amount' => amount.to_i, 'applied' => [] }

        Pf2eHP.modify_damage(holder, amount.to_i, false, is_dm, kind)

        held
      end

      def self.heal(holder, amount, options = [])
        return Npcs.heal(holder, amount) if Pf2e.npc?(holder)

        Pf2eHP.modify_damage(holder, amount.to_i, true, false, nil, options)

        amount.to_i
      end

      # `12 / 20`, for whoever may see it.
      def self.hit_points(holder)
        return "#{holder.hp_left} / #{holder.max_hp}" if Pf2e.npc?(holder)

        holder.hp ? "#{Pf2eHP.get_current_hp(holder)} / #{Pf2eHP.get_max_hp(holder)}" : '---'
      end
    end
  end
end
