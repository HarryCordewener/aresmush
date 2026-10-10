module AresMUSH
  module Pf2e

    # Delay: someone whose turn has begun waits for a better moment. What ends their turn happens at
    # once, the order moves on without them, and when they return - after another's turn, with the same
    # action - they act then, and directly before whoever's turn it is from there on. Their turn coming
    # round again with them still waiting is the delayed turn lost.
    module Delay

      NAME = 'Delay'.freeze
      KEY = 'delaying'.freeze

      def self.of(holder)
        TurnState.of(holder)[KEY]
      end

      def self.act(scene, out)
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless scene.encounter

        of(scene.actor.holder) ? come_back(scene, out) : wait(scene, out)
      end

      # They wait: no reaction until they return, and their turn's end now.
      def self.wait(scene, out)
        label = scene.actor.label

        return Err.new(:not_turn, 'pf2e.delay_not_turn', 'actor' => label) unless ActiveEffects.current_turn(scene.encounter) == label

        TurnState.write(scene.actor.holder, KEY => { 'passed' => false },
                                            'turn' => TurnState.turn(scene.actor.holder).merge('reaction' => true))
        out['lines'] << Telling.event('pf2e.delay_begun', :actor => label)
        out['lines'].concat(Turns.ending(scene.encounter, label, scene.encounter.round))

        Ok.new(:state => out)
      end

      # They return, with a turn's actions, to act before whoever's turn is running.
      def self.come_back(scene, out)
        label = scene.actor.label
        current = ActiveEffects.current_turn(scene.encounter)

        return Err.new(:not_passed, 'pf2e.delay_not_passed', 'actor' => label) if current == label

        Combatants.before_current(scene.encounter, label)
        TurnState.started(scene.actor.holder, scene.encounter.round)
        TurnState.write(scene.actor.holder, KEY => nil)
        out['lines'] << Telling.event('pf2e.delay_returned', :actor => label, :before => current)

        Ok.new(:state => out)
      end

      # Whether the order is moving on from someone who delayed, whose turn ended when they did.
      def self.passing?(holder)
        held = of(holder)

        return false unless held && !held['passed']

        TurnState.write(holder, KEY => held.merge('passed' => true))

        true
      end

      # Their turn has come round with them still waiting: the turn they delayed is lost.
      def self.lost(holder)
        return [] unless of(holder)

        TurnState.write(holder, KEY => nil)

        [ Turns.event('pf2e.delay_lost', 'name' => holder.name) ]
      end
    end
  end
end
