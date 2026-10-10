module AresMUSH
  module Pf2e

    # What a condition stops someone doing, by the traits of what they try. Each row is a condition, the
    # traits it is about, and what comes of trying: refused outright, or risked on a flat check.
    #
    #   Immobilized  cannot use an action with the move trait.
    #   Restrained   cannot use an action with the attack or manipulate trait, except to Escape or Force
    #                Open.
    #   Grabbed      an action with the manipulate trait is lost on a failed DC 5 flat check.
    module Restraints

      FREEING = [ 'Escape', 'Force Open' ].freeze

      ROWS = [
        { 'condition' => 'Restrained', 'traits' => %w{attack manipulate}, 'key' => 'pf2e.act_restrained', 'unless' => FREEING },
        { 'condition' => 'Immobilized', 'traits' => %w{move}, 'key' => 'pf2e.act_immobilized' },
        { 'condition' => 'Grabbed', 'traits' => %w{manipulate}, 'flat' => 5, 'unless' => FREEING }
      ].freeze

      def self.row_for(holder, name, traits)
        held = Pf2e.held_conditions(holder)
        slugs = Array(traits).map { |trait| Domains.slug(trait) }

        ROWS.find do |row|
          held.key?(row['condition']) && (row['traits'] & slugs).any? && !Array(row['unless']).include?(name)
        end
      end

      # What stops the action, as an error to tell whoever tried, or nothing.
      def self.refusal(actor, name, traits)
        row = row_for(actor.holder, name, traits)

        row && row['key'] ? Err.new(:restrained, row['key'], 'actor' => actor.label, 'action' => name) : nil
      end

      # The flat check a grabbed creature's hands are risked on, rolled: nothing where none is called for,
      # and otherwise whether the action is kept and the line that says so.
      def self.risked(actor, name, traits)
        row = row_for(actor.holder, name, traits)

        return nil unless row && row['flat']

        flat = Resolve.flat(row['flat'])
        key = flat['success'] ? 'pf2e.act_grabbed_kept' : 'pf2e.act_grabbed_lost'

        { 'kept' => flat['success'], 'line' => Telling.event(key, :actor => actor.label, :action => name, :die => flat['die']) }
      end
    end
  end
end
