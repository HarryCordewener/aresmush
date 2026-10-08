module AresMUSH

  # A character as they stand in one encounter: what has happened to them there, on top of who they are.
  #
  # The character's own sheet is neutral - level, attributes, feats, equipment, what they have prepared -
  # and carries no damage, conditions, effects or spent resources. Everything an encounter does to them
  # lands here instead, so two encounters never share a wound and `+sheet` always shows the neutral
  # character while `+e/sheet` shows this.
  #
  # It stands in for the character wherever the engine works on "whoever": it answers the names the
  # condition, effect and hit point code reads off a character - `pf2_conditions`, `pf2_effects`, `hp`,
  # `magic` - from its own fields, and anything else from the character. A creature's `Pf2eNpc` does the
  # same for a stat block.
  class Pf2eCombatantState < Ohm::Model
    include ObjectModel

    attribute :damage, :type => DataType::Integer, :default => 0
    attribute :temp_hp, :type => DataType::Integer, :default => 0
    attribute :temp_hp_source
    attribute :temp_max, :type => DataType::Integer, :default => 0
    attribute :temp_current, :type => DataType::Integer, :default => 0

    attribute :pf2_conditions, :type => DataType::Hash, :default => {}
    attribute :pf2_persistent, :type => DataType::Array, :default => []
    attribute :pf2_turn_state, :type => DataType::Hash, :default => {}
    attribute :pf2_derived, :type => DataType::Hash, :default => {}
    attribute :pf2_is_dead, :type => DataType::Boolean
    attribute :pf2_reagents, :type => DataType::Hash, :default => {}

    # What a rest gave them to spend, and what is left: spells for the day by casting class, focus points,
    # and whether a revelation spell has locked them out.
    attribute :spells_today, :type => DataType::Hash, :default => {}
    attribute :focus_current, :type => DataType::Integer, :default => 0
    attribute :revelation_locked, :type => DataType::Boolean, :default => false

    # What they carry in the encounter: a copy of their own gear and money as they entered it
    # (`Pf2e::Equipment`), which is all the encounter reads or changes.
    attribute :pf2_money, :type => DataType::Integer, :default => 0
    attribute :consumables_at_start, :type => DataType::Hash, :default => {}

    # The exploration activity they are doing, which a fight started from the exploration reads.
    attribute :exploration_activity

    reference :character, "AresMUSH::Character"
    reference :encounter, "AresMUSH::PF2Encounter"
    collection :pf2_effects, "AresMUSH::Pf2eEffect", :state
    collection :weapons, "AresMUSH::PF2Weapon", :state
    collection :armor, "AresMUSH::PF2Armor", :state
    collection :shields, "AresMUSH::PF2Shield", :state
    collection :magic_items, "AresMUSH::PF2MagicItem", :state
    collection :consumables, "AresMUSH::PF2Consumable", :state
    collection :gear, "AresMUSH::PF2Gear", :state
    collection :bags, "AresMUSH::PF2Bag", :state

    index :character_id
    index :encounter_id

    before_delete :delete_effects

    # Its own fields; everything else is the character's.
    OWN = (Pf2e::StateHP::FIELDS + %w{pf2_conditions pf2_persistent pf2_turn_state pf2_derived
                          pf2_is_dead pf2_reagents spells_today focus_current revelation_locked pf2_money
                          consumables_at_start exploration_activity}).freeze

    def delete_effects
      self.pf2_effects.each(&:delete)
      Pf2e::Equipment.copies(self).each(&:delete)
    end

    def name
      character.name
    end

    def hp
      character.hp ? Pf2e::StateHP.new(self) : nil
    end

    def magic
      character.magic ? Pf2e::StateMagic.new(self, character.magic) : nil
    end

    # A write goes where the field lives: its own fields here, anything else to the character.
    def update(attributes)
      own, theirs = attributes.partition { |key, _value| OWN.include?(key.to_s) }

      character.update(theirs.to_h) unless theirs.empty?
      own.empty? ? self : super(own.to_h)
    end

    def method_missing(name, *args, &block)
      return character.public_send(name, *args, &block) if character&.respond_to?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      character&.respond_to?(name, include_private) || super
    end
  end
end
