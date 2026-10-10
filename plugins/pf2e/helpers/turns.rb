module AresMUSH
  module Pf2e

    # What happens as a turn in an encounter starts or ends.
    #
    # Everything that keeps time with the order happens here, and each thing that happens is answered as
    # an event - a locale key and its arguments - so whoever tells the room decides how. Nothing here
    # emits anything. The one whose turn it is may be a character or a creature.
    #
    #   as a turn starts   effects and conditions timed to it end; the turn's counters start over;
    #                      temporary hit points refresh; fast healing and regeneration heal
    #   as a turn ends     effects and conditions timed to it end; a sustained effect nobody sustained
    #                      ends; Frightened drops by one; persistent damage is dealt and its flat check
    #                      rolled
    module Turns

      def self.event(key, args = {})
        { 'key' => key, 'args' => args }
      end

      # The order has moved on: one turn ended and the next began.
      def self.advanced(encounter, ending, ending_round, starting, starting_round)
        ended = ending ? turn_ended(encounter, ending, ending_round) : []

        ended + turn_started(encounter, starting, starting_round)
      end

      def self.turn_started(encounter, participant, round)
        events = ActiveEffects.expire(encounter, 'turn-start', participant, round) +
                 conditions_ended(encounter, 'turn-start', participant, round)
        holder = Combatants.holder_named(encounter, participant)

        return events unless holder

        TurnState.started(holder, round)
        Equipment.lapse!(holder, 'turn')
        ActiveEffects.on(holder).each { |effect| ActiveEffects.give_temp_hp(holder, effect, 'on_turn_start') }

        events + heal(holder) + recovery(holder)
      end

      # A dying character's recovery check as their turn starts: a flat check against 10 and their dying
      # value. A critical success takes two off, a success one; a failure adds one, a critical failure
      # two. At nothing they stop dying, wounded one more and still unconscious; at the value that is
      # death they die, or are spared it, as the encounter has it (`Pf2eHP.now_dying`).
      RECOVERY = { Degree::CRITICAL_SUCCESS => -2, Degree::SUCCESS => -1, Degree::FAILURE => 1,
                   Degree::CRITICAL_FAILURE => 2 }.freeze

      def self.recovery(holder)
        dying = Pf2e.condition_level(holder, 'Dying')

        return [] unless dying.positive? && !Actors.of(holder).creature? && !holder.pf2_is_dead

        dc = Pf2eHP.recovery_dc(holder)
        die = Pf2e.roll_dice(1, 20).first
        degree = Degree.of(die, dc, die)
        value = dying + RECOVERY[degree]
        told = [ event('pf2e.recovery_check', 'name' => holder.name, 'die' => die, 'dc' => dc,
                       'degree' => Resolve::WORDS[degree]) ]

        if value <= 0
          Pf2eHP.stable(holder)
          return told << event('pf2e.recovery_stable', 'name' => holder.name)
        end

        fate = Pf2eHP.now_dying(holder, value, Gm.may_kill?(holder))

        told << event(FATES[fate] || 'pf2e.recovery_dying', 'name' => holder.name, 'value' => value)
      end

      # What a recovery check that would kill is told as.
      FATES = { :dead => 'pf2e.recovery_dead', :spared => 'pf2e.recovery_spared' }.freeze

      def self.turn_ended(encounter, participant, round)
        events = ActiveEffects.expire(encounter, 'turn-end', participant, round) +
                 ActiveEffects.unsustained(encounter, participant, round) +
                 conditions_ended(encounter, 'turn-end', participant, round)
        holder = Combatants.holder_named(encounter, participant)

        return events unless holder

        events + less_frightened(holder) + PersistentDamage.end_of_turn(holder) + Holding.turn_ended(encounter, participant)
      end

      # ------------------------------------------------------------------------------
      # The reminder a combatant gets as their turn starts

      # What matters to whoever's turn it now is, and only to them: what the turn holds, what they are
      # under and for how long, what will burn at its end, and the auras they project - whose reach the
      # map knows and this does not, so the reminder asks.
      def self.reminder(holder, round)
        return t('pf2e.turn_dead', :name => holder.name) if Pf2e.dead?(holder)

        lines = [ t('pf2e.turn_reminder', :name => holder.name, :round => round, :summary => TurnState.summary(holder)) ]

        effects = ActiveEffects.on(holder).map { |effect| "#{effect.name}: #{ActiveEffects.remaining(effect)}" }
        lines << "  #{effects.join('. ')}." if effects.any?

        conditions = Pf2e.condition_labels(holder, false)
        lines << "  #{t('pf2e.creature_conditions')}: #{conditions.join(', ')}" if conditions.any?

        PersistentDamage.held(holder).each do |one|
          lines << t('pf2e.turn_persistent', :formula => one['formula'], :type => one['type'])
        end

        Auras.of(holder).each do |aura|
          lines << t('pf2e.turn_aura', :aura => aura['slug'], :radius => aura['radius'])
        end

        lines += Actors.of(holder).reminder_lines

        lines.join('%r')
      end

      # ------------------------------------------------------------------------------
      # Conditions that last a while

      # When a condition set for a while ends, counted from the turn of whoever set it: `turn-end` is the
      # end of their current turn, `next-turn-start` and `next-turn-end` the start or end of their next,
      # and `rounds:N` the start of their turn N rounds on.
      def self.expiry(until_when, owner, round)
        case until_when.to_s
        when 'turn-end' then { 'event' => 'turn-end', 'of' => owner, 'round' => round.to_i }
        when 'next-turn-start' then { 'event' => 'turn-start', 'of' => owner, 'round' => round.to_i + 1 }
        when 'next-turn-end' then { 'event' => 'turn-end', 'of' => owner, 'round' => round.to_i + 1 }
        when /\Arounds:(\d+)\z/ then { 'event' => 'turn-start', 'of' => owner, 'round' => round.to_i + $1.to_i }
        end
      end

      # The same, for a condition an outcome leaves: one timed by `its-` is counted from the turn of
      # whoever holds it - Blanket of Stars' "dazzled until the end of its next turn" - and anything else
      # from the caster's.
      def self.expiry_for(until_when, encounter, actor, target)
        kind = until_when.to_s

        return expiry(kind, actor, encounter.round) unless kind.start_with?('its-')

        { 'event' => kind.end_with?('start') ? 'turn-start' : 'turn-end', 'of' => target,
          'round' => upcoming_round(encounter, target) }
      end

      # The round of someone's next turn: this one, if their place in the order is still to come.
      def self.upcoming_round(encounter, label)
        order = Combatants.rows(encounter).map { |row| row['name'] }
        now = (encounter.next_init.to_i - 1) % [ order.size, 1 ].max
        at = order.index(label)

        at && at > now ? encounter.round.to_i : encounter.round.to_i + 1
      end

      # Everyone in the encounter, as they stand in it: its creatures, and its characters' states there.
      def self.holders(encounter)
        encounter.npcs.to_a + encounter.states.to_a
      end

      def self.conditions_ended(encounter, event, participant, round)
        holders(encounter).flat_map do |holder|
          (holder.pf2_conditions || {}).select { |_name, info|
            ends = info.is_a?(Hash) ? info['expires'] : nil
            ends && ends['event'] == event && ends['of'] == participant && round.to_i >= ends['round'].to_i
          }.keys.map do |name|
            Pf2e.remove_condition(holder, name, true)
            event('pf2e.condition_ended', 'condition' => name, 'name' => holder.name)
          end
        end
      end

      # Frightened drops by one at the end of each of your turns.
      def self.less_frightened(holder)
        held = (holder.pf2_conditions || {})['Frightened']

        return [] unless held.is_a?(Hash) && held['value'].to_i.positive?

        left = held['value'].to_i - 1
        Pf2e.set_condition(holder, 'Frightened', left)

        return [ event('pf2e.condition_ended', 'name' => holder.name, 'condition' => 'Frightened') ] if left.zero?

        [ event('pf2e.frightened_eased', 'name' => holder.name, 'value' => left) ]
      end

      # ------------------------------------------------------------------------------
      # Fast healing and regeneration

      # What heals the character as their turn starts, from any source: a spell's effect, a feat, an
      # item. Regeneration does nothing on a turn after damage of a kind that switches it off.
      def self.healing(char)
        Actors.of(char).turn_healing
      end

      def self.heal(char)
        off = TurnState.of(char)['regeneration_off']
        char.update(:pf2_turn_state => TurnState.of(char).except('regeneration_off'))

        healing(char).map do |one|
          next nil if one['type'] == 'regeneration' && off
          next nil unless one['value'].positive?

          Harm.heal(char, one['value'])
          event('pf2e.fast_healing', 'name' => char.name, 'count' => one['value'].to_i, 'source' => one['source'])
        end.compact
      end

      # Damage of a kind that switches regeneration off does so until the character's next turn.
      def self.damaged(char, kind)
        return unless kind

        stops = healing(char).select { |one| one['type'] == 'regeneration' }
                             .flat_map { |one| one['deactivated_by'] }.map { |one| Domains.slug(one) }

        return unless stops.include?(Domains.slug(kind))

        char.update(:pf2_turn_state => TurnState.of(char).merge('regeneration_off' => true))
      end
    end
  end
end
