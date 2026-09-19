module AresMUSH
  class Pf2eHP < Ohm::Model
    include ObjectModel


    attribute :ancestry_hp, :type => DataType::Integer, :default => 0
    attribute :charclass_hp, :type => DataType::Integer, :default => 0
    attribute :damage, :type => DataType::Integer, :default => 0
    attribute :temp_max, :type => DataType::Integer, :default => 0
    attribute :temp_current, :type => DataType::Integer, :default => 0
    attribute :temp_hp, :type => DataType::Integer, :default => 0
    # Which effect the temporary hit points came from, so ending that effect takes them away and ending
    # some other one does not (`rule-element/temp-hp.ts`).
    attribute :temp_hp_source


    reference :character, "AresMUSH::Character"



    ##### CLASS METHODS #####

    def self.display_character_hp(char)
      hp = char.hp

      return "---" if !hp

      current = get_current_hp(char)
      max = get_max_hp(char)
      percent = max.zero? ? 0 : ((current.to_f / max.to_f) * 100).to_i
      hp_color = "%xg" if percent > 75
      hp_color = "%xc" if percent.between?(50,75)
      hp_color = "%xy" if percent.between?(25,50)
      hp_color = "%xr" if percent < 25
      "#{hp_color}#{current}%xn / #{max} (#{percent}%)"

    end

    # `kind` is what the damage was: `fire`, `S`, whatever the attack dealt. Given one, the character's
    # immunities, weaknesses and resistances are applied before any of it lands - which is the point of
    # damage having a kind at all.
    # `options` are the circumstances of what is being done, which is how a bonus to healing from
    # Treat Wounds applies to that and not to every point of healing: Robust Health's own rule is
    # predicated on `action:treat-wounds`.
    def self.modify_damage(char, amount, healing=false, is_dm=false, kind=nil, options=[])
      amount = Pf2e::IWR.apply(Pf2e::IWR.of(char), amount, kind)['amount'] if kind && !healing
      Pf2e::Turns.damaged(char, kind) if kind && !healing
      amount = healed(char, amount, options) if healing

      hp = get_hp_obj(char)
      max_hp = get_max_hp(char)
      existing_damage = hp.damage

      if healing
        if (existing_damage == max_hp)
          Pf2e.set_condition(char, 'Wounded', 1 + Pf2e.condition_level(char, 'Wounded'))
          Pf2e.remove_condition(char, 'Dying')
        end

        # What an effect took and says cannot be healed stays taken while the effect lasts.
        floor = [ Pf2e::HitPointLoss.unrecoverable(char), max_hp ].min
        hp.update(damage: (existing_damage - amount).clamp(floor, max_hp))
        return
      end

      # Deduct from temp_hp first, if any, overflow goes to HP.

      temp_hp = hp.temp_hp

      # Amount expects an integer, conversion not required.

      damage = temp_hp - amount

      hp.temp_hp = [ damage, 0 ].max

      # A hit the temporary pool swallowed whole still spent it, and the reduced pool has to be
      # written down or the same temporary hit points soak every hit that comes.
      unless damage.negative?
        hp.save
        return
      end

      if damage.negative?

        extra_damage = damage.abs
        hp.temp_hp = 0

        new_damage = existing_damage + extra_damage

        # Check to see if this damage puts the character in Dying.
        if (new_damage >= max_hp && is_dm)
          hp.damage = max_hp

          # Reduced to nothing: Dying 1, one higher for each point of Wounded already carried.
          # Doomed lowers the value at which that kills them.
          dying_value = 1 + Pf2e.condition_level(char, 'Wounded')
          doomed_value = Pf2e.condition_level(char, 'Doomed')
          fatal_at = 4 - doomed_value

          if dying_value >= fatal_at
            char.update(pf2_is_dead: true)
            Pf2e.set_condition char, 'Dying', dying_value.clamp(0, fatal_at)
          else
            Pf2e.set_condition char, 'Dying', dying_value
          end

          hp.save
          return
        end

        hp.damage = new_damage
        hp.save
      end
    end

    # What the character recovers, given what they were given. Theirs rather than the healer's - Robust
    # Health recovers more from Treat Wounds whoever is doing the treating - and never below nothing.
    def self.healed(char, amount, options)
      (amount + Pf2e::Stat.total(char, 'healing', nil, options)).clamp(0, nil)
    end

    def self.get_hp_obj(char)
      char.hp
    end

    # The DC to recover from dying: 10 plus the dying value, less whatever an effect took off it.
    # Toughness and Defy Death both lower it, and both say so themselves as a write, so nothing here
    # names either.
    def self.recovery_dc(char)
      10 + Pf2e.condition_level(char, 'Dying') + Pf2e::Paths.held(char, 'dying_recovery_dc').to_i
    end

    # Hit points before anything modifies them. Constitution belongs here rather than in a modifier
    # because it is counted per level; Drained's own row multiplies by level to match.
    #
    # A character who has not committed base info has no HP row yet, and approving one used to raise
    # `undefined method 'ancestry_hp' for nil`. No row means no hit points.
    def self.base_max_hp(char)
      hp = get_hp_obj(char)

      return 0 unless hp

      con_mod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Constitution"))

      (hp.charclass_hp + con_mod) * char.pf2_level + hp.ancestry_hp
    end

    def self.get_max_hp(char)
      Pf2e::Stat.total(char, 'hp')
    end

    # The arithmetic as well as the answer, for a sheet that shows a player why Drained cost them 40.
    def self.max_hp_breakdown(char)
      Pf2e::Stat.of(char, 'hp')
    end

    def self.get_current_hp(char)
      hp = get_hp_obj(char)

      return 0 unless hp

      get_max_hp(char) - hp.damage.to_i
    end

    def self.factory_default(char)
      # This may or may not exist, nothing to do if not.
      hp = char.hp
      return unless hp

      hp.damage = 0
      hp.ancestry_hp = 0
      hp.charclass_hp = 0
      hp.temp_max = 0
      hp.temp_current = 0
      hp.temp_hp = 0

      hp.save
    end

  end
end
