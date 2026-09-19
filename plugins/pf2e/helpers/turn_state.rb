module AresMUSH
  module Pf2e

    # What a combatant has done this turn: actions spent, attacks made, whether the reaction is gone, and
    # how often they have used an action that is limited.
    #
    # Counted and shown, never enforced. A GM can always say "yes, you have a reaction"; the count is here
    # so nobody has to remember it between turns that can be an hour apart. The attack count is the one
    # figure it feeds: the multiple attack penalty is Foundry's `map:increases:N`, and this supplies N.
    module TurnState

      # When a limit on how often an action may be used starts over, by Foundry's `frequency.per`. A
      # minute is longer than most fights, so anything up to ten minutes starts over as the encounter
      # ends; anything longer, at a night's rest.
      PERIODS = { 'turn' => 'turn', 'round' => 'turn', 'PT1M' => 'encounter', 'PT10M' => 'encounter',
                  'encounter' => 'encounter' }.freeze

      ACTIONS = 3

      def self.of(holder)
        holder.pf2_turn_state || {}
      end

      def self.turn(holder)
        of(holder)['turn'] || {}
      end

      def self.write(holder, changes)
        holder.update(:pf2_turn_state => of(holder).merge(changes))
      end

      # Their turn has begun: three actions, a reaction, no attacks yet, and anything limited per turn or
      # per round is theirs again.
      def self.started(holder, round)
        write(holder, 'turn' => { 'round' => round.to_i, 'actions' => 0, 'attacks' => 0, 'reaction' => false })
        reset(holder, 'turn')
      end

      # Everything limited to a period starts over.
      def self.reset(holder, period)
        uses = (of(holder)['uses'] || {}).reject { |_name, one| one['period'] == period }

        write(holder, 'uses' => uses)
      end

      def self.period(frequency)
        PERIODS.fetch(frequency.to_s, 'rest')
      end

      # An action was used. `cost` is what the catalogue says it costs; a reaction spends the reaction, a
      # free action nothing, and an attack counts toward the multiple attack penalty.
      def self.spend(holder, name, cost: 1, type: 'action', attack: false, frequency: nil)
        now = turn(holder)
        now = now.merge('actions' => now['actions'].to_i + cost.to_i) if type == 'action'
        now = now.merge('reaction' => true) if type == 'reaction'
        now = now.merge('attacks' => now['attacks'].to_i + 1) if attack

        changes = { 'turn' => now }

        if frequency
          uses = of(holder)['uses'] || {}
          held = uses[name] || { 'count' => 0, 'period' => period(frequency['per']) }
          changes['uses'] = uses.merge(name => held.merge('count' => held['count'].to_i + 1))
        end

        write(holder, changes)
      end

      # How many times an action has been used in its period.
      def self.used(holder, name)
        ((of(holder)['uses'] || {})[name] || {})['count'].to_i
      end

      # Foundry's option for which attack of the turn this is: the second is `map:increases:1`.
      def self.map_options(holder)
        attacks = turn(holder)['attacks'].to_i

        attacks.positive? ? [ "map:increases:#{[ attacks, 2 ].min}" ] : []
      end

      # How many actions the turn holds: three, one more if quickened, fewer if slowed or stunned.
      def self.actions(holder)
        quickened = Pf2e.held_conditions(holder).key?('Quickened') ? 1 : 0

        ACTIONS + quickened - Pf2e.condition_level(holder, 'Slowed') - Pf2e.condition_level(holder, 'Stunned')
      end

      # `2 of 3 actions used, reaction ready, next attack at -5`.
      def self.summary(holder)
        now = turn(holder)
        penalty = map_penalty(now['attacks'].to_i)

        t('pf2e.turn_summary', :used => now['actions'].to_i, :total => [ actions(holder), 0 ].max,
                               :reaction => now['reaction'] ? t('pf2e.reaction_spent') : t('pf2e.reaction_ready'),
                               :attack => penalty.zero? ? t('pf2e.attack_no_penalty') : t('pf2e.attack_penalty', :penalty => penalty))
      end

      def self.map_penalty(attacks)
        [ attacks, 2 ].min * -5
      end
    end
  end
end
