require 'json'

module AresMUSH
  module Pf2e

    # An encounter's history: every change in it, which the GM can take back and put back.
    #
    # A change is recorded as the whole encounter before and after it - its order, turn, cover and
    # concealment, each character's state in it, each creature, each effect - so taking one back is
    # putting the before back, whatever the change touched, and putting it back again is putting the after
    # back, with no die rolled twice.
    #
    # What its characters carry is the encounter's own copy (`Equipment`), so it is recorded and put back
    # like anything else, and nothing outside the encounter can move it.
    #
    # The history is one line: `history_at` is how many of its entries are in effect, and recording a new
    # one drops any past that point, which could only have been redone.
    #
    # An ended encounter's history is frozen.
    module History

      # What an encounter holds of its own that a change can move.
      FIELDS = %w{participants next_init round last_number cover concealment trusted current}.freeze

      # What an encounter owns, each by id: the states and creatures in it, and the effects on them. Asked
      # for rather than held in a constant, because the models load after this file.
      def self.owned
        held = { 'states' => [ Pf2eCombatantState, ->(encounter) { encounter.states.to_a } ],
                 'npcs' => [ Pf2eNpc, ->(encounter) { encounter.npcs.to_a } ],
                 'effects' => [ Pf2eEffect, ->(encounter) { Pf2eEffect.find(:encounter_id => encounter.id).to_a } ] }

        # And what its characters carry in it: their copies of their gear.
        Equipment.kinds.each do |collection, model|
          held["items:#{collection}"] = [ model, ->(encounter) { encounter.states.to_a.flat_map { |one| one.public_send(collection).to_a } } ]
        end

        held
      end

      KEY = :pf2e_recording

      def self.snapshot(encounter)
        encounter = PF2Encounter[encounter.id]
        held = { 'encounter' => plain(FIELDS.to_h { |field| [ field, encounter.public_send(field) ] }) }

        owned.each do |name, (_model, members)|
          held[name] = members.call(encounter).to_h do |one|
            [ one.id.to_s, plain(one.attributes.except(:created_at, :updated_at)) ]
          end
        end

        held
      end

      # The encounter as it was: what was there then is put back as it was, including what the change
      # deleted, and what the change created is gone.
      def self.restore(encounter, held)
        held = without_the_deleted(held)
        encounter = PF2Encounter[encounter.id]
        encounter.update(held['encounter'].transform_keys(&:to_sym))

        owned.each do |name, (model, members)|
          wanted = held[name] || {}

          members.call(encounter).each { |one| one.delete unless wanted.key?(one.id.to_s) }

          wanted.each do |id, attributes|
            attributes = attributes.transform_keys(&:to_sym)
            found = model[id]

            if found
              found.update_attributes(attributes)
              found.save
            else
              model.new(attributes.merge(:id => id)).save
            end
          end
        end
      end

      def self.plain(value)
        JSON.parse(JSON.dump(value))
      end

      # A copy with nobody in it who has been deleted since: their place in the order, their state and the
      # effects on it, and what they carried. Taking a change back never brings a deleted character back.
      def self.without_the_deleted(held)
        gone = lambda { |id| id && !Character[id] }
        states = (held['states'] || {}).reject { |_id, one| gone.call(one['character_id']) }
        order = Array(held['encounter']['participants']).reject { |row| row.is_a?(Hash) && gone.call(row['char']) }

        kept = lambda { |one| !one['state_id'] || states.key?(one['state_id'].to_s) }
        owned_by_kept = held.select { |name, _| name == 'effects' || name.start_with?('items:') }
                            .transform_values { |members| members.select { |_id, one| kept.call(one) } }

        held.merge(owned_by_kept).merge('encounter' => held['encounter'].merge('participants' => order), 'states' => states)
      end

      # ------------------------------------------------------------------------------
      # Recording

      # Runs a change and records it, if it changed anything. A change inside another - `+e/as` running
      # a Strike - is part of the outer one.
      def self.recording(encounter, said)
        return yield if encounter.nil? || !encounter.is_active || Thread.current[KEY]

        Thread.current[KEY] = true
        before = snapshot(encounter)

        begin
          yield
        ensure
          Thread.current[KEY] = nil
        end

        after = snapshot(encounter)
        append(encounter, said, before, after) unless before == after
      end

      def self.entries(encounter)
        Pf2eEncounterEntry.find(:encounter_id => encounter.id).to_a.sort_by(&:seq)
      end

      def self.at(encounter)
        PF2Encounter[encounter.id].history_at.to_i
      end

      def self.append(encounter, said, before, after)
        applied = at(encounter)

        entries(encounter).select { |entry| entry.seq > applied }.each(&:delete)
        Pf2eEncounterEntry.create(:encounter => encounter, :seq => applied + 1, :said => said,
                                  :before => before, :after => after)
        PF2Encounter[encounter.id].update(:history_at => applied + 1)
      end

      # ------------------------------------------------------------------------------
      # Taking back and putting back

      def self.undo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entries(encounter).find { |one| one.seq == at(encounter) }

        return Err.new(:nothing_to_undo, 'pf2e.history_nothing_to_undo') unless entry

        restore(encounter, entry.before)
        PF2Encounter[encounter.id].update(:history_at => entry.seq - 1)

        Ok.new(:state => entry)
      end

      def self.redo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entries(encounter).find { |one| one.seq == at(encounter) + 1 }

        return Err.new(:nothing_to_redo, 'pf2e.history_nothing_to_redo') unless entry

        restore(encounter, entry.after)
        PF2Encounter[encounter.id].update(:history_at => entry.seq)

        Ok.new(:state => entry)
      end
    end
  end
end
