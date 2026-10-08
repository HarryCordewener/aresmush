module AresMUSH
  class PF2Encounter < Ohm::Model
    include ObjectModel

    attribute :name
    # The initiative order, one row per combatant; `Pf2e::Combatants` reads and writes it.
    attribute :participants, :type => DataType::Array, :default => []
    attribute :next_init, :type => DataType::Integer, :default => 0
    # Its GM: whoever started it, or whoever they handed it to. Held by the character, so a rename keeps
    # it theirs; `organizer` is their name as it was, for an encounter from before owners were held.
    reference :owner, "AresMUSH::Character"
    attribute :organizer
    attribute :is_active, :type => DataType::Boolean, :default => true
    attribute :round, :type => DataType::Integer, :default => 0
    attribute :current
    attribute :messages, :type => DataType::Array, :default => []
    attribute :init_stat

    # `exploration` for an exploration between fights (`Pf2e::Exploration`): no initiative and no turns.
    # Anything else is a fight.
    attribute :mode

    # The last combatant id given. An id is never reused within an encounter, so `#2` means the same
    # creature all fight long.
    attribute :last_number, :type => DataType::Integer, :default => 0

    # Players the GM has trusted with setting cover and concealment, for this encounter only.
    attribute :trusted, :type => DataType::Array, :default => []

    # A target's cover and concealment, by its id: `{ '3' => 'standard' }`.
    attribute :cover, :type => DataType::Hash, :default => {}
    attribute :concealment, :type => DataType::Hash, :default => {}

    # The encounter its characters carry on from, if the GM named one when starting it: whoever was in
    # that one starts this one as they left it. Anyone else starts fresh.
    attribute :carries_on_from

    set :characters, "AresMUSH::Character"
    reference :scene, "AresMUSH::Scene"
    collection :npcs, "AresMUSH::Pf2eNpc", :encounter
    collection :states, "AresMUSH::Pf2eCombatantState", :encounter

    # The party's level for its difficulty, where the GM set one; otherwise the characters' average.
    attribute :party_level, :type => DataType::Integer

    # What staff paid each character for it, by name: `{ 'Aria' => { 'xp' => 80, 'money' => 13500 } }`.
    attribute :awarded, :type => DataType::Hash, :default => {}

    # How many of its history's entries are in effect: undo steps back, redo forward (`Pf2e::History`).
    attribute :history_at, :type => DataType::Integer, :default => 0
    collection :entries, "AresMUSH::Pf2eEncounterEntry", :encounter

    before_delete :delete_combatants

    def delete_combatants
      self.npcs.each(&:delete)
      self.states.each(&:delete)
      self.entries.each(&:delete)
    end

    ##### CLASS METHODS #####

    def self.in_active_encounter?(char)
      char.encounters.any? { |e| e.is_active }
    end

    def self.scene_active_encounter(scene)
      scene.encounters.select { |e| e.is_active }.first
    end

    def self.get_encounter(char, scene=nil)
      return nil unless scene
      scene_active_encounter(scene)
    end

    def self.active_encounters(char)
      char.encounters.select { |e| e.is_active }
    end

    def self.send_to_encounter(enc, msg)
      message_list = enc.messages
      message_list << [ Time.now, msg ]
      enc.update(messages: message_list)
    end

    # Its GM, or staff: admins run every encounter.
    def self.is_organizer?(char, encounter)
      char.is_admin? || owned_by?(char, encounter)
    end

    def self.owned_by?(char, encounter)
      encounter.owner_id ? encounter.owner_id == char.id : char.name == encounter.organizer
    end

    def self.gm_of(encounter)
      encounter.owner || Character.named(encounter.organizer.to_s)
    end

    def self.hand_to(encounter, char)
      encounter.update(:owner => char, :organizer => char.name)
    end

  end
end
