module AresMUSH
  module Pf2e

    # A night's rest and the day's preparations, for someone as they stand in an encounter: the night's
    # Hit Points, an end to what lasts less than a day, the day's once-a-day uses, a full focus pool, the
    # day's spells from what they have prepared, reagents, and what they invest. The GM rests them with
    # `+e/rest`, as often as the story says a night has passed.
    def self.rest(holder)
      # What the last day's preparations made lapses before this day's are made.
      Equipment.lapse!(holder, 'rest')
      Pf2eHP.modify_damage(holder, get_daily_healing(holder), true)
      ActiveEffects.rested(holder)
      TurnState.reset(holder, 'rest')

      magic = holder.magic

      if magic
        daily_refresh_focus_pool(magic)
        Pf2emagic.generate_spells_today(holder)
        magic.update(revelation_locked: false)
      end

      daily_refresh_reagents(holder)
      do_daily_investiture(holder)

      # Their reagents are refreshed before what they prepared is made of them.
      Alchemy.at_rest!(holder)
    end

    # A full night's rest recovers Constitution modifier times level, doubled by Fast Recovery and its
    # like. Foundry keeps that as a multiplier their rules add to, so what an effect wrote is one less
    # than the multiplier it means (`system.attributes.hp.recoveryMultiplier`).
    # A night's rest: the Constitution modifier, at least 1, for each level - twice over with Fast
    # Recovery.
    def self.get_daily_healing(char)
      con_mod = [ Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Constitution")), 1 ].max

      con_mod * [ char.pf2_level.to_i, 1 ].max * recovery_multiplier(char)
    end

    def self.recovery_multiplier(char)
      1 + Pf2e::Paths.held(char, 'recovery_multiplier').to_i
    end

    SNARES_BY_RANK = { 'expert' => 4, 'master' => 6, 'legendary' => 8 }.freeze

    # The day's reagents: an alchemist's batches, `[ total, allocated, remaining ]`, and a snare-maker's
    # snares, `[ total, remaining ]`. An alchemist is one by their Advanced Alchemy whether or not their
    # reagents were ever recorded, which chargen does not do.
    def self.daily_refresh_reagents(char)
      reagents = (char.pf2_reagents || {}).dup
      reagents['alchemist'] ||= [ 0, 0, 0 ] if Pf2e::Alchemy.alchemist?(char)

      return nil if reagents.empty?

      if reagents['alchemist']
        total = Pf2e::Alchemy.capacity(char)
        allocated = char.pf2_alloc_reagents.to_i

        reagents['alchemist'] = [ total, allocated, total - allocated ]
      end

      if reagents['snares']
        # Snares prepared each day, by Crafting: 4 for an expert, 6 for a master, 8 for a legend.
        snares_today = SNARES_BY_RANK[Pf2eSkills.get_skill_prof(char, 'Crafting').to_s.downcase].to_i

        reagents['snares'] = [ snares_today, snares_today ]
      end

      char.update(pf2_reagents: reagents)
    end

    # Daily preparations fill the pool.
    def self.daily_refresh_focus_pool(magic)
      magic.update(focus_pool: { 'current' => Pf2emagic.focus_pool_max(magic) })
    end

    def self.do_daily_investiture(char)

      char_wp_list = Pf2egear::Inventory.held(char, 'weapons')
      char_a_list = Pf2egear::Inventory.held(char, 'armor')
      char_mi_list = Pf2egear.items_in_inventory(char.magic_items.to_a)

      investable_list = char_wp_list + char_a_list + char_mi_list

      investable_list.each { |item| item.update(invested: false) }

      to_invest = investable_list.select {|i| i.invest_on_refresh }

      to_invest.each { |item| item.update(invested: true) }

      return nil
    end

  end
end
