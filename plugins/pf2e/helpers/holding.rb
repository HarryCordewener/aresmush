module AresMUSH
  module Pf2e

    # Who holds whom. Someone grabbed or restrained is held by whoever did it, by name, and what the
    # rules hang on being held follows that: only the holder's own failed Grapple lets go, the holder
    # lets go when it drops or leaves, it tightens its grip without a roll, and it crushes, swallows or
    # is escaped from as the one that holds.
    #
    # The hold is written on the condition itself, as `by`. One the GM set by hand has no holder, and
    # behaves as a condition does.
    module Holding

      # In the order asked: restrained is the tighter hold.
      HOLDS = %w{Restrained Grabbed}.freeze

      # What being swallowed or engulfed slows them by, and is taken off with.
      INSIDE = 'held inside'.freeze

      def self.conditions(holder)
        holder.pf2_conditions || {}
      end

      # The hold on someone: `[ 'Grabbed', { 'by' => 'Python #2', ... } ]`, or nothing.
      def self.hold(holder)
        HOLDS.map { |name| [ name, conditions(holder)[name] ] }.find { |_name, entry| entry.is_a?(Hash) }
      end

      def self.by(holder)
        (hold(holder) || [])[1]&.fetch('by', nil)
      end

      # Whether anything keeps them where they are, held by someone or not.
      def self.held?(holder)
        (Pf2e.held_conditions(holder).keys & (HOLDS + [ 'Immobilized' ])).any?
      end

      def self.holds?(label, holder)
        by(holder) == label
      end

      # Who has just been grabbed or restrained is held by whoever did it.
      def self.mark(holder, name, label, extra = {})
        list = conditions(holder)

        return unless HOLDS.include?(name) && list[name].is_a?(Hash)

        holder.update(:pf2_conditions => list.merge(name => list[name].merge('by' => label).merge(extra)))
      end

      # Everyone in the encounter this combatant holds.
      def self.held_by(encounter, label)
        return [] unless encounter

        Combatants.all(encounter).select { |one| one.holder && holds?(label, one.holder) }
      end

      # Lets someone go: the hold, and what being inside their holder did to them.
      def self.release(holder)
        HOLDS.each { |name| Pf2e.remove_condition(holder, name, true) if conditions(holder).key?(name) }
        slowed = conditions(holder)['Slowed']
        Pf2e.remove_condition(holder, 'Slowed', true) if slowed.is_a?(Hash) && slowed['granted_by'] == INSIDE
      end

      # A holder that drops, or leaves the fight, lets go of everyone it holds. Answers a line for each,
      # for the room. Someone it had swallowed is still inside what is left of it.
      def self.let_go(encounter, label)
        held_by(encounter, label).map do |one|
          inside = inside(one.holder)

          next Telling.event('pf2e.hold_still_inside', :target => one.label, :actor => label, :kind => inside['kind']) if inside

          release(one.holder)
          Telling.event('pf2e.hold_released', :target => one.label, :actor => label)
        end
      end

      # Tightening a grip already held: to the end of the holder's next turn, with no roll.
      def self.tighten(encounter, actor, target)
        name, entry = hold(target.holder)
        ends = Turns.expiry_for('next-turn-end', encounter, actor.label, target.label)

        target.holder.update(:pf2_conditions => conditions(target.holder).merge(name => entry.merge('expires' => ends))) unless entry['inside']

        Telling.event('pf2e.hold_extended', :actor => actor.label, :target => target.label)
      end

      # What someone is inside, if their holder has swallowed or engulfed them:
      # `{ 'kind' => 'Swallow Whole', 'damage' => [ [ '1d8+1', 'bludgeoning' ] ], 'rupture' => 5 }`.
      def self.inside(holder)
        (hold(holder) || [])[1]&.fetch('inside', nil)
      end
    end
  end
end
