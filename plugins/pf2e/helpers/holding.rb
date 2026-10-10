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

      # Lets someone go. What the hold brought with it - the slowness of being swallowed - goes with it,
      # as anything a condition grants does.
      def self.release(holder)
        HOLDS.each { |name| Pf2e.remove_condition(holder, name, true) if conditions(holder).key?(name) }
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

        # Someone held inside is held until they get out.
        target.holder.update(:pf2_conditions => conditions(target.holder).merge(name => entry.merge('expires' => ends))) unless entry['inside']

        Telling.event('pf2e.hold_extended', :actor => actor.label, :target => target.label)
      end

      # ------------------------------------------------------------------------------
      # Held inside: swallowed, or engulfed

      # What someone is inside, if their holder has swallowed or engulfed them:
      # `{ 'kind' => 'Swallow Whole', 'damage' => [ [ '1d8+1', 'bludgeoning' ] ], 'rupture' => 5 }`.
      def self.inside(holder)
        (hold(holder) || [])[1]&.fetch('inside', nil)
      end

      # Whether one combatant is inside another.
      def self.inside?(holder, label)
        !inside(holder).nil? && by(holder) == label
      end

      # Puts someone inside their holder: grabbed there with no end to it, and slowed while they are.
      def self.put_inside(holder, label, inside)
        Pf2e.remove_condition(holder, 'Restrained', true)
        Pf2e.set_condition(holder, 'Grabbed') unless conditions(holder).key?('Grabbed')

        list = conditions(holder)
        holder.update(:pf2_conditions => list.merge('Grabbed' => list['Grabbed'].except('expires').merge('by' => label, 'inside' => inside)))

        Pf2e.set_condition(holder, 'Slowed', 1, 'granted_by' => 'Grabbed') unless conditions(holder).key?('Slowed')
      end

      # What being inside deals: as they go in, and at the end of each of their turns while whatever
      # holds them still stands.
      def self.digest(encounter, target, out)
        within = inside(target.holder)
        keeper = within && encounter ? Combatants.find(encounter, by(target.holder)) : nil

        return unless keeper&.ok? && Acting.still_up(keeper.state.holder) && Array(within['damage']).any?

        rows = DamageRoll.of_formulas(within['damage'].map { |formula, type| [ formula, type, nil ] }, false)

        Acting.deal(Acting::Scene.new(encounter, keeper.state, target, nil, true), target, rows, out)
      end

      # The end of someone's turn inside something. Answers what happened, for whoever tells the room.
      def self.turn_ended(encounter, label)
        found = Combatants.find(encounter, label)

        return [] unless found.ok? && inside(found.state.holder)

        out = Acting.report
        digest(encounter, found.state, out)
        out['lines']
      end

      # Someone inside cuts their way out with a single blow of piercing or slashing damage as great as
      # the Rupture value. Answers the line that says so, or nothing.
      def self.cut_free(actor, target, sharp)
        within = inside(actor.holder)

        return nil unless within && by(actor.holder) == target.label && within['rupture'] && sharp >= within['rupture'].to_i

        release(actor.holder)
        Telling.event('pf2e.hold_cut_free', :target => actor.label, :actor => target.label)
      end
    end
  end
end
