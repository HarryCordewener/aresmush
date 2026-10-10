module AresMUSH
  module Pf2e

    # What a fight's GM may and may not do for the kind of GM they are, tried through the commands they
    # would type: an event runner's limits, and a Plotmaster's or staff's reach.
    module GmProbes

      CUSTOM = 'Straw Ogre=ac 18 hp 60 level 3 fort 11 ref 6 will 7 perception 7; resist bludgeoning 5; weak fire 5; ' \
               'immune sleep; strike club +12 1d10+6 bludgeoning (reach 10); ' \
               'ability Sweep [2]: Each creature within reach takes 2d6 bludgeoning damage (DC 20 basic Reflex save).'.freeze

      def gm_probes!
        plotmaster = Gm.plotmaster?(Character[@gm.id])

        scan_probe
        adjust_probe
        plotmaster ? plotmaster_probes : runner_probes
      end

      def refused?(outcome, key, args = {})
        outcome.failures.include?(clean(t(key, **args)))
      end

      # The newest creature in the order, which a probe has just added.
      def newest
        Combatants.rows(encounter).select { |row| row['npc'] }.max_by { |row| row['id'].to_i }
      end

      def scan_probe
        probe('the scan lists each creature to the GM, and is refused to a player') do
          shown = type(@gm, 'e/scan').said.join("\n")
          # A row gives the id and then the name without it, as long as the column is.
          listed = foes.all? { |row| shown.include?(row['name'].sub(/ ##{row['id']}\z/, '')[0, 18].strip) }
          player = type(@party.first, 'e/scan')

          [ listed && refused?(player, 'pf2e.not_organizer'), "listed #{listed}; a player was told #{player.status}" ]
        end
      end

      def adjust_probe
        ref, npc = aim

        probe('a creature made elite mid-fight gains 2 AC and keeps the hit points it has lost') do
          came_as = Pf2eNpc[npc.id].adjustment
          type(@gm, "e/adjust #{ref}=normal")
          type(@gm, "damage #{ref}=1")
          before = Pf2eNpc[npc.id]
          ac, lost = Npcs.stat(before, 'ac')['total'], before.damage
          type(@gm, "e/adjust #{ref}=elite")
          elite = Pf2eNpc[npc.id]
          raised = Npcs.stat(elite, 'ac')['total']
          type(@gm, "e/adjust #{ref}=weak")
          lowered = Npcs.stat(Pf2eNpc[npc.id], 'ac')['total']
          type(@gm, "e/adjust #{ref}=#{came_as || 'normal'}")

          [ raised == ac + 2 && lowered == ac - 2 && elite.damage == lost && elite.max_hp > before.max_hp,
            "AC #{ac}, elite #{raised}, weak #{lowered}; damage #{lost} -> #{elite.damage}; hit points #{before.max_hp} -> #{elite.max_hp}" ]
        end
      end

      # ------------------------------------------------------------------------------
      # An event runner

      def runner_probes
        victim = @party[1]

        probe('an event runner is refused a creature outside Monster Core') do
          tried = type(@gm, 'e/add guard')
          [ refused?(tried, 'pf2e.creature_not_open', :creature => 'Guard'), tried.status ]
        end

        probe('an event runner is refused a creature of their own making') do
          tried = type(@gm, "e/add #{CUSTOM}")
          [ refused?(tried, 'pf2e.creature_custom_not_open'), tried.status ]
        end

        probe('an event runner cannot give a character Doomed or Drained, or say they are dead') do
          tried = %w{doomed/1 drained/1 dead}.map { |what| type(@gm, "condition/set #{victim.name}=#{what}") }
          held = conditions_of(state_of(victim)).keys & %w{Doomed Drained}

          [ tried.none?(&:ok?) && held.empty? && !Pf2e.dead?(state_of(victim)), "#{tried.map(&:status)}; holds #{held}" ]
        end

        probe('what would kill a character in an event runner\'s fight leaves them unconscious') do
          type(@gm, "condition/set #{victim.name}=wounded/3")
          type(@gm, "damage #{victim.name}=#{hp_of(victim)}")
          state = state_of(victim)
          held = conditions_of(state)
          spared = !Pf2e.dead?(state) && !held.key?('Dying') && held.key?('Unconscious')
          type(@gm, "heal #{victim.name}=#{max_hp_of(victim)}")
          type(@gm, "condition/set #{victim.name}=wounded/0")

          [ spared && hp_of(victim).positive?, "dead #{Pf2e.dead?(state)}; held #{held.keys}; healed to #{hp_of(victim)}" ]
        end
      end

      # ------------------------------------------------------------------------------
      # A Plotmaster, or staff

      def plotmaster_probes
        victim = @party[1]

        probe('a Plotmaster adds a creature from any book, and takes it out again') do
          added = type(@gm, 'e/add guard')
          row = newest
          removed = type(@gm, "encounter/remove ##{row['id']}")

          [ added.ok? && row['name'].start_with?('Guard') && removed.ok?, "#{added.status}; #{removed.status}" ]
        end

        probe('a creature of the GM\'s own making resists, is weak and is immune as described') do
          added = type(@gm, "e/add #{CUSTOM}")
          row = newest
          npc = Pf2eNpc[row['npc']]
          took = lambda do |kind|
            before = Pf2eNpc[npc.id].damage
            type(@gm, "damage ##{row['id']}=10 #{kind}")
            Pf2eNpc[npc.id].damage - before
          end
          dealt = %w{bludgeoning fire slashing}.map { |kind| took.call(kind) }
          type(@gm, "encounter/remove ##{row['id']}")

          [ added.ok? && dealt == [ 5, 15, 10 ], "#{added.status}; 10 bludgeoning, fire and slashing landed as #{dealt}" ]
        end

        probe('a Plotmaster gives a character Doomed, and takes it off') do
          given = type(@gm, "condition/set #{victim.name}=doomed/1")
          held = value_of(state_of(victim), 'Doomed')
          type(@gm, "condition/set #{victim.name}=doomed/0")

          [ given.ok? && held == 1 && value_of(state_of(victim), 'Doomed').zero?, "#{given.status}; Doomed #{held}" ]
        end

        probe('what kills a character in a Plotmaster\'s fight kills them, and the GM brings them back') do
          type(@gm, "condition/set #{victim.name}=wounded/3")
          type(@gm, "damage #{victim.name}=#{hp_of(victim)}")
          dead = Pf2e.dead?(state_of(victim))
          healed = type(@gm, "heal #{victim.name}=5")
          type(@gm, "condition/set #{victim.name}=dead/0")
          raised = !Pf2e.dead?(state_of(victim))
          type(@gm, "heal #{victim.name}=#{max_hp_of(victim)}")
          type(@gm, "condition/set #{victim.name}=wounded/0")

          [ dead && !healed.ok? && raised && hp_of(victim).positive?,
            "dead #{dead}; healing the dead: #{healed.status}; raised #{raised}; healed to #{hp_of(victim)}" ]
        end
      end
    end
  end
end
