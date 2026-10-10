module AresMUSH

  # A creature in an encounter: one goblin warrior of three, with its own hit points and conditions.
  #
  # What the creature is - its defences, Strikes and abilities - is its stat block in the bestiary
  # (`Pf2e::Bestiary`), read by name. This row is only the instance, which is what changes in a fight.
  #
  # It answers to the handful of names the condition and effect code reads off a character -
  # `pf2_conditions`, `pf2_effects`, `pf2_level` - so a creature is frightened, prone or blessed by the
  # same code a character is. Where the engine needs something only one kind of actor has, it asks the
  # actor (`Pf2e::Actors`), which knows which kind it is.
  class Pf2eNpc < Ohm::Model
    include ObjectModel

    # How the encounter names it, which is unique within it: `Goblin Warrior #3`, or the name the GM gave.
    attribute :name

    # The bestiary entry it is an instance of, or nothing for a creature the GM described by its numbers.
    attribute :creature

    # Its id in the initiative, which is what a player types to target it: `#3`.
    attribute :number, :type => DataType::Integer

    # A creature described by its numbers rather than named from the bestiary.
    attribute :described, :type => DataType::Hash, :default => {}

    # What makes it stronger or weaker than its stat block: `elite`, `weak` (`Pf2e::Adjustments`), or nothing.
    attribute :adjustment

    attribute :damage, :type => DataType::Integer, :default => 0

    # The most hit points a troop has once it has fallen below a threshold, which is that threshold.
    attribute :hp_cap, :type => DataType::Integer
    attribute :temp_hp, :type => DataType::Integer, :default => 0

    # What its shield has taken, where its stat block gives it one.
    attribute :shield_damage, :type => DataType::Integer, :default => 0

    attribute :pf2_conditions, :type => DataType::Hash, :default => {}

    # The circumstances a GM has switched on or off for it - Air Scamp's fast healing in open air.
    attribute :pf2_roll_options, :type => DataType::Hash, :default => {}
    attribute :pf2_persistent, :type => DataType::Array, :default => []
    attribute :pf2_turn_state, :type => DataType::Hash, :default => {}

    reference :encounter, "AresMUSH::PF2Encounter"
    collection :pf2_effects, "AresMUSH::Pf2eEffect", :npc

    index :number

    before_delete :delete_effects

    def delete_effects
      self.pf2_effects.each { |effect| effect.delete }
    end

    # What it fights with: the bestiary's stat block or the one it was described with, as its adjustment
    # leaves it.
    def stat_block
      @stat_block ||= Pf2e::Adjustments.apply(written_stat_block, self.adjustment)
    end

    def written_stat_block
      (self.creature ? Pf2e::Bestiary.entry(self.creature) : nil) || self.described || {}
    end

    # Elite, weak, or neither from here on. The hit points it has lost stay lost.
    def adjust(name)
      update(:adjustment => name)
      @stat_block = nil
      update(:damage => [ self.damage.to_i, max_hp ].min)
    end

    def pf2_level
      stat_block['level'].to_i
    end

    def pf2_traits
      Array(stat_block['traits'])
    end

    # The stat block's hit points as its conditions leave them: Drained lowers the maximum, and so does a
    # troop's falling below a threshold.
    def max_hp
      full = (Pf2e::Npcs.stat(self, 'hp') || {})['total'] || stat_block['hp'].to_i

      self.hp_cap.to_i.positive? ? [ full, self.hp_cap ].min : full
    end

    def hp_left
      max_hp - self.damage.to_i
    end

    # What the condition and effect code asks of a character that a creature does not have.
    def pf2_feats; {}; end
    def pf2_features; {}; end
    def pf2_base_info; {}; end
    def pf2_level_tracker; {}; end
    def pf2_roll_aliases; {}; end
    def hp; nil; end
    def combat; nil; end
  end
end
