module AresMUSH
  module Pf2e

    # A creature played by the book, the way a GM who knows its stat block plays it: its auras as the
    # fight starts, what it does to whoever it holds, its breath on everyone when it is back, a follow-up
    # the moment the Strike that lists it hits, each thing its stat block gives it at least once, and its
    # reactions when something sets them off. Every step is a command the GM types.
    module CreaturePlay

      AREA = DamageAbout::AREA

      def creature_turn(row)
        ref = "##{row['id']}"
        mind = minds[row['npc']]

        auras(ref, row) unless mind['auras']
        mind['auras'] = true

        while actions_left(row).positive? && standing.any?
          before = actions_used(row)
          step = next_step(row, mind)

          break unless step

          step.call
          # A step that cost nothing and changed nothing would be taken forever.
          mind['idle'] = actions_used(row) == before ? mind['idle'].to_i + 1 : 0
          break if mind['idle'] > 2
        end

        mind['idle'] = 0
        type(@gm, "e/creature #{ref}")
      end

      def minds
        @minds ||= Hash.new { |held, id| held[id] = { 'done' => [], 'turns' => 0 } }
      end

      def standing
        @party.reject { |char| down?(char) }
      end

      def actions_used(row)
        TurnState.turn(Pf2eNpc[row['npc']])['actions'].to_i
      end

      def actions_left(row)
        TurnState.actions(Pf2eNpc[row['npc']]) - actions_used(row)
      end

      def abilities(row)
        Array(Pf2eNpc[row['npc']].stat_block['actions'])
      end

      def ability(row, name)
        abilities(row).find { |one| one['name'].casecmp?(name) || Domains.slug(one['name']).start_with?(Domains.slug(name)) }
      end

      def held_by(row)
        Holding.held_by(encounter, row['name'])
      end

      def cost_of(one)
        one['type'].to_s == 'action' ? (one['cost'] || 1).to_i.clamp(1, 3) : 0
      end

      # Whoever is not already inside something, with the most hit points left.
      def quarry(row)
        open = standing.reject { |char| Holding.inside(state_of(char)) }

        (open.any? ? open : standing).max_by { |char| hp_of(char) }
      end

      # The creature's auras that call for a save, with everyone standing inside them.
      def auras(ref, row)
        abilities(row).select { |one| Array(one['traits']).include?('aura') && CreatureAbilities.saving(one['text']) }.each do |one|
          type(@gm, "e/as #{ref}=enter #{one['name']}=#{standing.map(&:name).join(',')}") if standing.any?
        end
      end

      # What a GM who knows the stat block does next with the actions it has left.
      def next_step(row, mind)
        ref = "##{row['id']}"
        left = actions_left(row)
        holding = held_by(row)
        outside = holding.reject { |one| Holding.inside(one.holder) }

        if outside.any?
          swallow = ability(row, 'Swallow Whole')
          return -> { type(@gm, "e/as #{ref}=act swallow whole=#{outside.first.label}") } if swallow && !mind['swallowed']&.include?(outside.first.label) && mark(mind, 'swallowed', outside.first.label)

          crush = ability(row, 'Greater Constrict') || ability(row, 'Constrict')
          return -> { type(@gm, "e/as #{ref}=act #{crush['name']}") } if crush && !mind['crushed'] && (mind['crushed'] = true)
        end

        breath = ready(row, left).find { |one| one['text'].to_s.match?(AREA) && CreatureAbilities.saves?(one['text']) }
        return -> { type(@gm, "e/as #{ref}=act #{breath['name']}=#{standing.map(&:name).join(',')}") } if breath && standing.any? && used(mind, breath)

        fresh = ready(row, left).reject { |one| mind['done'].include?(one['name']) || follow_up?(one) || held_only?(one) }.first
        return -> { type(@gm, "e/as #{ref}=act #{fresh['name']}=#{quarry(row).name}") } if fresh && used(mind, fresh)

        spell = (mind['spells'] ||= creature_spells(Pf2eNpc[row['npc']].stat_block)).first
        return -> { mind['spells'].shift; type(@gm, "e/as #{ref}=cast #{spell}=#{quarry(row).name}") } if spell && left >= 2

        -> { strike_and_follow(row, mind) }
      end

      def mark(mind, key, label)
        (mind[key] ||= []) << label
      end

      def used(mind, one)
        mind['done'] << one['name']
        mind['crushed'] = nil
        true
      end

      # Abilities it can pay for now: not passive, not a reaction, and not still coming back.
      def ready(row, left)
        npc = Pf2eNpc[row['npc']]
        waiting = Recharge.ready(npc)

        abilities(row).select do |one|
          %w{action free}.include?(one['type'].to_s) && cost_of(one) <= left && waiting[one['name']].to_i <= encounter.round.to_i
        end
      end

      def follow_up?(one)
        !Acting::FOLLOW_UPS[Domains.slug(one['name']).sub(/-\d+-feet\z/, '')].nil?
      end

      # What is only for someone it holds, which `next_step` uses when it holds someone.
      def held_only?(one)
        %w{constrict greater-constrict swallow-whole}.include?(Domains.slug(one['name'])) || one['name'] == 'Rend'
      end

      # A Strike with the next of its attacks in turn, and what follows a hit: the follow-up its Strike
      # lists, at once, and Rend after two hits running.
      def strike_and_follow(row, mind)
        npc = Pf2eNpc[row['npc']]
        target = quarry(row)
        strikes = Array(npc.stat_block['strikes'])
        rend = ability(row, 'Rend')
        chosen = rend ? strikes.find { |one| one['name'].casecmp?(MonsterAbilities.header(rend['text'])['words'].first.to_s) } : nil
        chosen ||= strikes[mind['turns'] % [ strikes.size, 1 ].max]
        mind['turns'] += 1

        creature_strikes(row, target, chosen && chosen['name'])

        last = TurnState.turn(Pf2eNpc[row['npc']])['last'] || {}

        return unless last['hit'] && !down?(target)

        follow = Array(last['effects']).find { |effect| Acting::FOLLOW_UPS.key?(Domains.slug(effect)) }
        type(@gm, "e/as ##{row['id']}=act #{follow}=#{target.name}") if follow && (actions_left(row).positive? || follow.start_with?('Improved'))

        hits = Array(TurnState.turn(Pf2eNpc[row['npc']])['strikes']).last(2)
        twice = rend && hits.size == 2 && hits.all? { |one| one['hit'] && one['target'] == target.name }
        type(@gm, "e/as ##{row['id']}=act rend=#{target.name}") if twice && actions_left(row).positive?
      end

      # A Strike, and the player's answer to it with what the game offers: Nimble Dodge where it would
      # turn the hit, then Shield Block behind a raised shield.
      def creature_strikes(row, target, with = nil)
        type(@gm, "e/as ##{row['id']}=strike #{target.name}#{with ? "=#{with}" : ''}")

        AttackAnswers.offered(state_of(target)).first(1).each { |name| attempt(target, :act, name, "e/act #{name.downcase}") }
        attempt(target, :act, 'Shield Block', 'e/act shield block') if ShieldBlock.offered?(state_of(target))
      end

      # From each of its lists, its highest spell that does something in a fight, and a cantrip.
      def creature_spells(block)
        Array(block['spellcasting']).flat_map do |casting|
          spells = casting['spells'] || {}
          rank = spells.keys.reject { |key| key.to_s == '0' }.max_by(&:to_i)
          high = rank ? Array(spells[rank]).find { |spell| fighting?(spell) } || Array(spells[rank]).first : nil

          [ high, Array(spells['0']).find { |spell| fighting?(spell) } ].compact
        end.uniq
      end

      # ------------------------------------------------------------------------------
      # What the creatures do out of turn

      # After a player has done something: a creature with a Reactive Strike answers a spell or a ranged
      # attack with it, once a round, and one reduced to nothing uses its Ferocity.
      def gm_reacts!(char, kind)
        Combatants.rows(encounter).select { |row| row['npc'] && Pf2eNpc[row['npc']] }.each do |row|
          npc = Pf2eNpc[row['npc']]
          spent = TurnState.turn(npc)['reaction']

          if npc.hp_left.to_i <= 0
            type(@gm, "e/as ##{row['id']}=act ferocity") if ability(row, 'Ferocity') && !spent && Pf2e.condition_level(npc, 'Wounded') < 3
          elsif kind == :spell && !spent && ability(row, 'Reactive Strike') && !down?(char) && !minds[row['npc']]['reacted']&.include?(encounter.round)
            mark(minds[row['npc']], 'reacted', encounter.round)
            type(@gm, "e/as ##{row['id']}=act reactive strike=#{char.name}")
          end
        end
      end

      # What a player held by a creature does before anything else: cut their way out from inside, or
      # Escape.
      def struggle(char)
        state = state_of(char)

        return false unless Holding.held?(state)

        by = Holding.by(state)
        keeper = by ? Combatants.rows(encounter).find { |row| row['name'] == by } : nil

        if Holding.inside(state) && keeper && !@tried[char.id].key?([ :strike, 'from inside' ])
          attempt(char, :strike, 'from inside', "e/strike ##{keeper['id']}")
        else
          attempt(char, :act, 'Escape', 'e/act escape')
        end

        true
      end
    end
  end
end
