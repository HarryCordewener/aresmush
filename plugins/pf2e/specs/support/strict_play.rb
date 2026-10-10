module AresMUSH
  module Pf2e

    # A GM playing creatures by the book: each scene is one creature and the party, with the dice held
    # where the scene needs them, and every step a command the GM or a player types. What the rules say
    # should then be true is asked of the game with `rule`.
    module StrictPlay

      attr_accessor :dice

      # The d20 a scene needs: high enough to succeed without being a natural 20, or a natural 1.
      HIT = 0.95
      CRIT = 1.0
      MISS = 0.05
      MIDDLING = 0.5

      def rolling(fraction)
        before = @dice
        @dice = fraction
        yield
      ensure
        @dice = before
      end

      # A fresh fight with the party in it and the creatures named, the creatures acting first and the
      # party after them in seat order.
      def scene(title, *creatures)
        say "## Scene: #{title}"
        type(@gm, 'encounter')
        @encounter = PF2Encounter.scene_active_encounter(Scene[@scene.id])
        @encounters << @encounter
        @party.each { |char| type(char, 'e/join') }
        type(@gm, 'e/rest')
        creatures.each { |one| type(@gm, "e/add #{one}") }

        rows = Combatants.rows(encounter)
        rows.select { |row| row['npc'] }.sort_by { |row| row['id'].to_i }
            .each_with_index { |row, i| type(@gm, "encounter/mod ##{row['id']}=#{60 - i}") }
        @party.each_with_index { |char, i| type(@gm, "encounter/mod #{char.name}=#{40 - i}") }
        type(@gm, 'e/next')

        yield
      ensure
        type(@gm, "encounter/end #{encounter.id}") if encounter&.is_active
        say ''
      end

      def creature_refs
        Combatants.rows(encounter).select { |row| row['npc'] }.sort_by { |row| row['id'].to_i }.map { |row| "##{row['id']}" }
      end

      def npc_at(ref)
        row = Combatants.rows(encounter).find { |one| "##{one['id']}" == ref }
        Pf2eNpc[row['npc']]
      end

      def ref_of(char)
        row = Combatants.rows(encounter).find { |one| one['char'].to_s == char.id.to_s }
        "##{row['id']}"
      end

      # Moves the order on until it is this combatant's turn.
      def turn_to(who)
        label = who.is_a?(String) ? Combatants.rows(encounter).find { |one| "##{one['id']}" == who }['name'] : who.name

        (Combatants.rows(encounter).size + 1).times do
          break if ActiveEffects.current_turn(encounter) == label

          type(@gm, 'e/next')
        end
      end

      def as(ref, text)
        heard_from { type(@gm, "e/as #{ref}=#{text}") }
      end

      # Everything a command put on the screen, the room's lines and the typist's own.
      def heard_from
        from = @lines.size
        yield
        @lines[from..].join("\n")
      end

      def held(holder)
        conditions_of(holder.is_a?(Character) ? state_of(holder) : holder)
      end

      def note(text)
        say "    -- #{text}"
      end

      def rule(name, &block)
        probe(name, &block)
      end
    end
  end
end
