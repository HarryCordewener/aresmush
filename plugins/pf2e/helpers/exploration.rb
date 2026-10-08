module AresMUSH
  module Pf2e

    # Exploring between fights. An exploration is an encounter in exploration mode (`+e/explore`): no
    # initiative and no turns, and what takes minutes - Treat Wounds - is done here rather than in a fight.
    # Each character travels doing one exploration activity, and when a fight starts from the exploration
    # the activity decides how they come into it.
    module Exploration

      MODE = 'exploration'.freeze

      # Player Core's exploration activities, and what each brings to a fight that starts while it is
      # being done:
      #
      #   initiative  the statistic initiative is rolled with, instead of the fight's own
      #   allies      a circumstance bonus to everyone else's initiative
      #   effect      an effect they start the fight under
      ACTIVITIES = {
        'Avoid Notice' => { 'initiative' => 'Stealth' },
        'Defend' => { 'effect' => 'Effect: Raise a Shield' },
        'Detect Magic' => {},
        'Follow the Expert' => {},
        'Hustle' => {},
        'Investigate' => {},
        'Repeat a Spell' => {},
        'Scout' => { 'allies' => 1 },
        'Search' => {}
      }.freeze

      def self.exploring?(encounter)
        encounter && encounter.mode == MODE
      end

      def self.activity?(name)
        ACTIVITIES.key?(name)
      end

      # An action only exploration has time for: one of the activities, or anything else with the
      # exploration trait - Treat Wounds takes ten minutes.
      def self.only_exploring?(name, entry)
        activity?(name) || Array(entry['traits']).include?('exploration')
      end

      def self.take_up(scene, name, out)
        scene.actor.holder.update(:exploration_activity => name)
        out['lines'] << Telling.event('pf2e.explore_activity', :actor => scene.actor.label, :activity => name)

        Ok.new(:state => out)
      end

      # Everyone exploring joins a fight that starts during the exploration, rolling initiative as their
      # activity has it, as they left the exploration. Answers a line for each, for the room.
      def self.bring_into(fight, exploring)
        exploring.states.to_a.sort_by(&:id).filter_map do |prior|
          char = prior.character

          next nil unless char

          arrival = arrival(prior, exploring)
          stat = Pf2e.initiative_stat(arrival['initiative'] || fight.init_stat || 'Perception')
          bonus = Pf2e.initiative_bonus(prior, stat) + arrival['bonus']
          roll = Pf2e.parse_roll_string(char, [ '1d20', bonus.to_s ])['total']

          Combatants.join(fight, char.name, roll, :holder => char)
          char.encounters.add fight
          fight.characters.add char
          started_under(fight, char, arrival['effect'])

          t('pf2e.explore_initiative', :name => char.name, :stat => stat, :roll => roll,
                                       :activity => prior.exploration_activity || t('pf2e.explore_no_activity'),
                                       :scouted => arrival['bonus'].positive? ? t('pf2e.explore_scouted', :bonus => arrival['bonus']) : '')
        end
      end

      # Defend's raised shield, where they have a shield that can be raised.
      def self.started_under(fight, char, effect)
        return unless effect

        state = CombatantStates.of(fight, char)

        return if effect == 'Effect: Raise a Shield' && ShieldBlock.cannot_raise(state)

        ActiveEffects.apply(state, effect, :applied_by => char.name, :encounter => fight)
      end

      # How a character comes into a fight from an exploration: the statistic they roll initiative with,
      # the bonus everyone else's scouting gives them, and the effect their activity starts them under.
      def self.arrival(state, exploring)
        own = ACTIVITIES[state.exploration_activity.to_s] || {}
        others = exploring.states.to_a.reject { |one| one.id == state.id }
        scouted = others.map { |one| (ACTIVITIES[one.exploration_activity.to_s] || {})['allies'].to_i }.max.to_i

        { 'initiative' => own['initiative'], 'bonus' => scouted, 'effect' => own['effect'] }
      end
    end
  end
end
