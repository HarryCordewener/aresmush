require 'delegate'

module AresMUSH
  module Pf2e

    # A character's hit points in an encounter: the sheet's hit dice, the encounter's damage.
    #
    # The hit point code reads and writes `char.hp` as a `Pf2eHP`. In an encounter that is this: what
    # comes from the sheet is the character's own row, and what a fight changes is the encounter's.
    class StateHP
      FIELDS = %w{damage temp_hp temp_hp_source temp_max temp_current}.freeze

      def initialize(state)
        @state = state
      end

      def ancestry_hp
        @state.character.hp.ancestry_hp
      end

      def charclass_hp
        @state.character.hp.charclass_hp
      end

      def character
        @state.character
      end

      FIELDS.each do |field|
        define_method(field) { @state.public_send(field) }
        define_method("#{field}=") { |value| @state.public_send("#{field}=", value) }
      end

      def update(attributes)
        @state.update(attributes)
      end

      def save
        @state.save
      end
    end

    # A character's magic in an encounter: their spell lists and preparation from the sheet, and what they
    # have left to spend from the encounter.
    class StateMagic < SimpleDelegator
      def initialize(state, magic)
        super(magic)
        @state = state
      end

      def spells_today
        @state.spells_today
      end

      def revelation_locked
        @state.revelation_locked
      end

      # What is left of the pool is the encounter's; its size is worked out from the focus spells they
      # know, so there is nothing of it to copy.
      def focus_pool
        (__getobj__.focus_pool || {}).merge('current' => @state.focus_current.to_i)
      end

      def spells_today=(value)
        @state.spells_today = value
      end

      def revelation_locked=(value)
        @state.revelation_locked = value
      end

      def focus_pool=(value)
        @state.focus_current = value['current'].to_i
      end

      def update(attributes)
        attributes = attributes.transform_keys(&:to_s)
        pool = attributes.delete('focus_pool')
        own = attributes.slice('spells_today', 'revelation_locked')
        theirs = attributes.except('spells_today', 'revelation_locked')

        own['focus_current'] = pool['current'].to_i if pool

        __getobj__.update(theirs) unless theirs.empty?
        @state.update(own) unless own.empty?
        self
      end

      def save
        @state.save
        __getobj__.save
      end
    end
  end
end
