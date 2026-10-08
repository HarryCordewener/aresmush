module AresMUSH
  module Pf2e

    # Situations a fight should handle, set up by the GM and played by the party at the start of each
    # encounter, each checked once it has happened: the circumstances a player names, conditions an
    # action or a spell leaves and what they do to the next roll, a character dropping and getting back
    # up, and the GM taking a change back. What does not happen as the rules say is a finding.
    #
    # Mixed into `ScenarioRunner`, which supplies the party, the GM, the encounter and the audit.
    module InteractionProbes

      def probe(name)
        say "### Probe: #{name}"
        ok, detail = yield
        @probes << [ name, ok ? 'ok' : "FAILED: #{detail}" ]
        @audit.find('interaction', name, detail) unless ok
      rescue StandardError => e
        @probes << [ name, "ERROR #{e.class}: #{e.message}" ]
        @audit.find('interaction', name, "#{e.class}: #{e.message} (#{e.backtrace&.first})")
      end

      def conditions_of(holder)
        (holder.class[holder.id].pf2_conditions || {})
      end

      def value_of(holder, name)
        held = conditions_of(holder)[name]

        held.is_a?(Hash) ? held['value'].to_i : (held ? 1 : 0)
      end

      def martial
        @party.find { |char| weapon_of(char) } || @party.first
      end

      def weapon_of(char)
        state_of(char).weapons.to_a.find(&:equipped)&.name
      end

      def ranged_of(char)
        state_of(char).weapons.to_a.find { |one| one.equipped && one.wp_type == 'ranged' }&.name
      end

      def rows_of(result)
        Array(((result || {})['breakdown'] || {})['modifiers'])
      end

      # The foe a probe acts on, fixed as it starts: the weakest one may die partway through, and what is
      # checked after is what happened to the one acted on.
      # With none left standing, the GM brings in another of the wave's creatures, so every probe has a
      # target.
      def aim
        type(@gm, "e/add 1 #{@wave.first.last}") unless foe
        row = foe
        [ "##{row['id']}", Pf2eNpc[row['npc']] ]
      end

      def defence_rows(holder)
        rows_of(@audit.last_defence(holder.name))
      end

      def interactions!
        striker = martial
        weapon = weapon_of(striker)

        probe('standard cover is +2 circumstance to AC') do
          covered, holder = aim
          type(@gm, "e/cover #{covered}=standard")
          type(striker, "e/strike #{covered}=#{weapon}")
          type(@gm, "e/cover #{covered}=none")
          rows = rows_of(@audit.last_defence(holder.name))
          found = rows.find { |row| row['type'] == 'circumstance' && row['value'].to_i == 2 }
          [ found, "no +2 circumstance in #{rows.inspect[0, 300]}" ]
        end

        probe('flanking leaves the target off-guard, -2 circumstance to AC') do
          ref, holder = aim
          type(striker, "e/strike #{ref}=#{weapon}/flanking")
          found = defence_rows(holder).find { |row| row['type'] == 'circumstance' && row['value'].to_i == -2 }
          [ found, "no -2 circumstance in #{defence_rows(holder).inspect[0, 300]}" ]
        end

        probe('the second Strike of a turn takes the multiple attack penalty') do
          rows = rows_of((@audit.last_roll(striker.name) || {})['result'])
          found = rows.find { |row| [ -4, -5, -8, -10 ].include?(row['value'].to_i) && row['source'].to_s.match?(/attack/i) }
          [ found, "no multiple attack penalty in #{rows.map { |row| [ row['source'], row['value'] ] }.inspect}" ]
        end

        probe('a concealed target makes a Strike roll a DC 5 flat check first') do
          ref, _holder = aim
          type(@gm, "e/conceal #{ref}=concealed")
          type(striker, "e/strike #{ref}=#{weapon}")
          type(@gm, "e/conceal #{ref}=none")
          shown = @lines.last(8).join(' ')
          [ shown.match?(/DC 5|flat/i), "no flat check told: #{shown[0, 300]}" ]
        end

        archer = @party.find { |char| ranged_of(char) }
        if archer
          probe('the third range increment is -4 to the attack') do
            ref, _holder = aim
            type(archer, "e/strike #{ref}=#{ranged_of(archer)}/range 3")
            rows = rows_of((@audit.last_roll(archer.name) || {})['result'])
            [ rows.any? { |row| row['value'].to_i == -4 && row['source'].to_s.include?('range') }, "no -4 range penalty in #{rows.map { |row| [ row['source'], row['value'] ] }.inspect}" ]
          end
        end

        demoralizer = @party.max_by { |char| Pf2eSkills.get_skill_bonus(Character[char.id], 'Intimidation').to_i rescue 0 }
        probe('Demoralize leaves Frightened by its degree, which then lowers the target\'s DCs') do
          ref, holder = aim
          before = value_of(holder, 'Frightened')
          type(demoralizer, "e/act demoralize=#{ref}")
          degree = (@audit.last_roll(demoralizer.name) || {}).dig('result', 'degree')
          wanted = { 3 => 2, 2 => 1 }.fetch(degree, 0)
          now = value_of(holder, 'Frightened')

          next [ true, nil ] if wanted.zero? && now == before
          next [ false, "degree #{degree} should leave Frightened #{wanted}, holds #{now}" ] unless now == [ wanted, before ].max
          next [ true, nil ] if holder.class[holder.id].hp_left.zero?

          type(striker, "e/strike #{ref}=#{weapon}")
          found = defence_rows(holder).find { |row| row['type'] == 'status' && row['value'].to_i == -now }
          [ found, "Frightened #{now} not on its AC: #{defence_rows(holder).inspect[0, 300]}" ]
        end

        probe('the GM takes a condition back with +e/undo, and puts it back with +e/redo') do
          ref, holder = aim
          type(striker, "e/act demoralize=#{ref}")
          held = conditions_of(holder).keys.sort
          type(@gm, 'e/undo')
          undone = conditions_of(holder).keys.sort
          type(@gm, 'e/redo')
          redone = conditions_of(holder).keys.sort
          [ redone == held, "held #{held}, after undo #{undone}, after redo #{redone}" ]
        end

        probe('a successful Trip leaves the target prone, and prone is off-guard') do
          ref, holder = aim
          type(striker, "e/act trip=#{ref}")
          degree = (@audit.last_roll(striker.name) || {}).dig('result', 'degree')
          prone = conditions_of(holder).key?('Prone')

          next [ !prone, "degree #{degree} left it prone" ] unless degree.to_i >= 2
          next [ false, "degree #{degree} did not leave it prone" ] unless prone
          next [ true, nil ] if holder.class[holder.id].hp_left.zero?

          type(striker, "e/strike #{ref}=#{weapon}")
          found = defence_rows(holder).find { |row| row['type'] == 'circumstance' && row['value'].to_i == -2 }
          [ found, "prone target is not off-guard: #{defence_rows(holder).inspect[0, 300]}" ]
        end

        rogue = @party.find { |char| Character[char.id].pf2_base_info['charclass'] == 'Rogue' }
        if rogue
          probe('a rogue\'s Strike at an off-guard target adds sneak attack\'s precision damage') do
            ref, _holder = aim
            hit = 4.times.find do
              @audit.instance_variable_set(:@last_damage, nil)
              type(rogue, "e/strike #{ref}=#{weapon_of(rogue) || 'fist'}/flanking")
              @audit.last_damage
            end

            next [ true, nil ] unless hit

            rows = @audit.last_damage
            [ rows.any? { |row| row['category'] == 'precision' }, "no precision damage in #{rows.inspect[0, 300]}" ]
          end
        end

        barbarian = @party.find { |char| Character[char.id].pf2_base_info['charclass'] == 'Barbarian' }
        if barbarian
          probe('Rage gives temporary hit points and adds its damage to a melee Strike') do
            type(barbarian, 'e/act rage')
            state = state_of(barbarian)
            melee = state.weapons.to_a.find { |one| one.equipped && one.wp_type != 'ranged' }
            attack = Pf2eCombat.attack_descriptor(state, melee)
            sources = Damage.of(state, attack)['instances'].flat_map { |one| one['sources'] }

            [ state.temp_hp.to_i.positive? && sources.any? { |one| one.to_s.match?(/rage/i) },
              "temporary hit points #{state.temp_hp}, damage from #{sources.inspect}" ]
          end
        end

        shield = @party.find { |char| state_of(char).shields.to_a.any?(&:equipped) }
        if shield
          probe('Raise a Shield is +2 circumstance to AC against the next Strike') do
            ref, _holder = aim
            type(shield, 'e/act raise a shield')
            type(@gm, "e/as #{ref}=strike #{shield.name}")
            rows = rows_of(@audit.last_defence(shield.name))
            [ rows.any? { |row| row['type'] == 'circumstance' && row['value'].to_i == 2 }, "no +2 circumstance: #{rows.inspect[0, 300]}" ]
          end
        end

        blessed = @party.last
        probe('Bless is +1 status to the attack of whoever it is on') do
          ref, _holder = aim
          type(@gm, "effect/add #{blessed.name}=bless")
          type(blessed, "e/strike #{ref}=#{weapon_of(blessed) || 'fist'}")
          rows = rows_of((@audit.last_roll(blessed.name) || {})['result'])
          [ rows.any? { |row| row['type'] == 'status' && row['value'].to_i == 1 }, "no +1 status: #{rows.map { |row| [ row['source'], row['type'], row['value'] ] }.inspect}" ]
        end

        dropped = @party[1]
        probe('a character brought to 0 is dying, and healed is wounded') do
          type(@gm, "damage #{dropped.name}=#{hp_of(dropped)}")
          dying = value_of(state_of(dropped), 'Dying')
          type(@gm, "heal #{dropped.name}=#{max_hp_of(dropped)}")
          wounded = value_of(state_of(dropped), 'Wounded')
          still = value_of(state_of(dropped), 'Dying')
          [ dying >= 1 && still.zero? && wounded >= 1, "dying #{dying} at 0, then dying #{still} and wounded #{wounded} once healed" ]
        end
      end

      # ------------------------------------------------------------------------------
      # Checked after every command of the fight

      # A spell cast at a foe leaves what its outcome says on it.
      def spell_outcome!(caster, text)
        spell = text[/\Ae\/cast ([^=\/]+)/, 1].to_s.strip
        target_ref = text[/=(#\d+)/, 1]

        return unless target_ref

        mechanics = Acting.spell_mechanics(spell).last

        return unless mechanics && (mechanics['outcomes'] || {}).any?

        row = Combatants.rows(encounter).find { |one| "##{one['id']}" == target_ref }
        holder = row && Combatants.holder_of(row)

        return unless holder

        save = @audit.last_roll(holder.name)
        attack = @audit.last_roll(caster.name)
        result = mechanics['attack'] ? attack && attack['result'] : save && save['result']

        return unless result && result['degree']

        wanted = Array((mechanics['outcomes'] || {})[Degree::NAMES[result['degree']]]).select { |one| one['condition'] }
        held = conditions_of(holder)

        wanted.each do |one|
          @audit.counts['spell outcomes checked'] += 1
          name = Pf2e.canonical_condition(one['condition'])
          value = held[name].is_a?(Hash) ? held[name]['value'].to_i : (held[name] ? 1 : 0)

          next if held.key?(name) && value >= one['value'].to_i

          @audit.find('auto condition', "#{caster.name} cast #{spell} at #{holder.name}",
                      "#{Degree::NAMES[result['degree']]} should leave #{name} #{one['value']}, holds #{held.keys.inspect}")
        end
      end

      # A character whose turn starts while dying rolls a recovery check.
      def recovery_rolled!(told)
        holder = frightened_before_turn_ends&.first

        return unless holder && !Actors.of(holder).creature?

        @audit.counts['turns checked for dying'] += 1
        rolled = told.any? { |line| line.include?('recovery check') }
        dying_now = value_of(holder, 'Dying').positive?

        return if rolled || !dying_now

        @audit.find('auto condition', "#{holder.name}'s turn started dying", 'no recovery check was rolled')
      end

      # Frightened eases by one at the end of its holder's turn.
      def frightened_before_turn_ends
        name = ActiveEffects.current_turn(encounter)
        row = Combatants.rows(encounter).find { |one| one['name'] == name }
        holder = row && Combatants.holder_of(row)

        holder ? [ holder, value_of(holder, 'Frightened') ] : nil
      end

      def frightened_eased!(held)
        return unless held && held.last.positive?

        holder, before = held
        now = value_of(holder, 'Frightened')
        @audit.counts['frightened turns checked'] += 1

        return if now == before - 1

        @audit.find('auto condition', "#{holder.name}'s turn ended", "Frightened #{before} should ease to #{before - 1}, is #{now}")
      end
    end
  end
end
