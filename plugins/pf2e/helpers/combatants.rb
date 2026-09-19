module AresMUSH
  module Pf2e

    # Who is in an encounter, and how a command names them.
    #
    # The initiative order holds each combatant by name. A character is a character; a creature is a
    # `Pf2eNpc` the GM added. Each also has an id, given when they join and never reused, so `#3` names the
    # same goblin all fight long whatever the order does - which is what a player types to target it,
    # since three goblins share a name.
    module Combatants

      Combatant = Struct.new(:holder, :label, :number) do
        def npc?
          Pf2e.npc?(holder)
        end

        def ref
          number ? "##{number}" : label
        end

        def name
          label
        end
      end

      ID = /\A#?(\d+)\z/

      # A combatant's id, given the first time anyone asks for it.
      def self.number(encounter, label)
        held = (encounter.numbers || {})[label]

        return held.to_i if held

        next_one = encounter.last_number.to_i + 1
        encounter.update(:numbers => (encounter.numbers || {}).merge(label => next_one), :last_number => next_one)

        next_one
      end

      # Whoever holds a place in the order under this name: the creature of that name, or the character.
      def self.holder_named(encounter, label)
        return nil if label.to_s.empty?

        (encounter ? encounter.npcs.to_a.find { |npc| npc.name == label } : nil) || Character.named(label)
      end

      def self.all(encounter)
        (encounter.participants || []).map do |_init, label|
          Combatant.new(holder_named(encounter, label), label, number(encounter, label))
        end
      end

      # The combatant a command names: `#3`, or a name only one of them has - whole, or the start of it.
      def self.find(encounter, term)
        wanted = term.to_s.strip
        listed = all(encounter)

        if (id = wanted.match(ID))
          found = listed.find { |one| one.number == id[1].to_i }

          return found ? Ok.new(:state => found) : Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted)
        end

        exact = listed.select { |one| one.label.casecmp?(wanted) }
        close = exact.any? ? exact : listed.select { |one| one.label.downcase.start_with?(wanted.downcase) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted) if close.empty?

        Err.new(:ambiguous_combatant, 'pf2e.ambiguous_combatant', 'target' => wanted,
                'options' => close.map { |one| "#{one.ref} #{one.label}" }.join(', '))
      end

      # Someone a command names, in an encounter or out of one: a combatant where there is an encounter,
      # and otherwise a character by name.
      def self.resolve(enactor, term, encounter = nil)
        if encounter
          found = find(encounter, term)

          return found if found.ok? || term.to_s.match?(ID)
        end

        char = ClassTargetFinder.find(term, Character, enactor)

        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => term) unless char.found?

        number = encounter && (encounter.numbers || {})[char.target.name]

        Ok.new(:state => Combatant.new(char.target, char.target.name, number))
      end

      # Several at once, saying which names found nobody: `[ found, missing ]`.
      def self.resolve_all(enactor, terms, encounter = nil)
        found, missing = Array(terms).map { |term| [ term, resolve(enactor, term, encounter) ] }
                                     .partition { |_term, result| result.ok? }

        [ found.map { |_term, result| result.state }, missing.map(&:first) ]
      end

      # The active encounter in the room the enactor is in, if there is one.
      def self.encounter_here(enactor)
        scene = enactor.room&.scene

        scene ? PF2Encounter.scene_active_encounter(scene) : nil
      end

      # ------------------------------------------------------------------------------
      # Adding a creature

      # A creature joins the encounter: its own hit points and conditions, an id, and a place in the
      # order - its Perception check unless the GM says where. `name` is what the GM calls it; otherwise
      # it is the creature and its id.
      def self.add_npc(encounter, creature: nil, described: nil, name: nil, initiative: nil)
        npc = Pf2eNpc.create(:encounter => encounter, :creature => creature, :described => described || {})
        number = encounter.last_number.to_i + 1
        base = name.to_s.strip.empty? ? "#{creature || described['name']} ##{number}" : name.to_s.strip
        label = (encounter.participants || []).any? { |_init, one| one == base } ? "#{base} ##{number}" : base

        npc.update(:name => label, :number => number)
        encounter.update(:numbers => (encounter.numbers || {}).merge(label => number), :last_number => number)

        rolled = initiative || (Pf2e.roll_dice.first + Npcs.stat(npc, 'perception', nil, [ 'initiative' ])['total'].to_i)

        PF2Encounter.add_to_initiative(encounter, label, rolled, true)

        Ok.new(:state => { 'npc' => npc, 'initiative' => rolled.to_i })
      end

      # A creature described by the numbers off a stat block: `ac 16 fort 5 ref 7 will 3 perception 2 hp 20`.
      DESCRIBED = { 'ac' => %w{ac}, 'hp' => %w{hp}, 'perception' => %w{perception per},
                    'fortitude' => %w{fort fortitude}, 'reflex' => %w{ref reflex}, 'will' => %w{will},
                    'level' => %w{level lvl} }.freeze

      def self.described(name, text)
        pairs = text.to_s.downcase.scan(/([a-z]+)\s*([+-]?\d+)/)
        read = pairs.each_with_object({}) do |(word, value), out|
          field = DESCRIBED.find { |_field, words| words.include?(word) }&.first
          out[field] = value.to_i if field
        end

        return nil unless read['ac']

        { 'name' => name, 'level' => read['level'].to_i, 'ac' => read['ac'], 'hp' => read['hp'].to_i,
          'perception' => read['perception'].to_i, 'traits' => [],
          'saves' => { 'fortitude' => read['fortitude'].to_i, 'reflex' => read['reflex'].to_i,
                       'will' => read['will'].to_i } }
      end

      # ------------------------------------------------------------------------------
      # Who may do what

      # The GM runs the encounter: its organiser, or staff.
      def self.gm?(char, encounter)
        encounter && PF2Encounter.is_organizer?(char, encounter)
      end

      # A GM, or a player the GM trusted for this encounter, may set a target's cover and concealment.
      def self.trusted?(char, encounter)
        gm?(char, encounter) || Array(encounter&.trusted).include?(char.name)
      end
    end
  end
end
