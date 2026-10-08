module AresMUSH
  module Pf2e

    # Moves a character off a spell name the remaster changed and onto the one the catalogue has: an
    # Enigma bard granted True Strike before the muse data was corrected holds Sure Strike afterwards.
    #
    # The name is kept in three places, and each is renamed: the ledger's `spell_access` and
    # `focus_spell` grants, which the next fold writes the known lists from; the magic object's own
    # hashes - signature spells, what is prepared and left today, innate grants; and the spellcasting
    # entry rows. A grant is renamed by reverting it and writing the same grant under the new name, at
    # the level and with the source it had, so a rollback treats it as it treated the old one.
    #
    # One character at a time, or `migrate_all!` from tinker. Running it again renames nothing.
    module SpellRenames

      # The legacy names whose spell this game stocks under a new one.
      def self.table
        stocked = Global.read_config('pf2e_spells') || {}

        Renames.table('spells').each_with_object({}) do |(legacy, row), out|
          next unless row['status'] == 'renamed' && stocked.key?(row['to']) && !stocked.key?(legacy)

          out[legacy.downcase] = row['to']
        end
      end

      # How many names it changed.
      def self.migrate!(char, table = self.table)
        renamed = grants!(char, table)
        renamed += magic!(char.magic, table) if char.magic
        renamed += entries!(char, table)

        if renamed.positive?
          Ledger.invalidate!(char)
          Ledger.materialize!(Character[char.id])
        end

        renamed
      end

      # Every character, saying which it could not move and why: one bad row does not stop the rest.
      def self.migrate_all!(characters: Character.all)
        table = self.table

        characters.each_with_object({ 'renamed' => 0, 'refused' => {} }) do |char, out|
          out['renamed'] += migrate!(char, table)
        rescue StandardError => e
          out['refused'][char.name] = e.message
        end
      end

      def self.grants!(char, table)
        stale = Ledger.rows(char).select do |row|
          row['reverted_by'].to_s.empty? && %w{spell_access focus_spell}.include?(row['kind']) &&
            table.key?((row['payload'] || {})['spell'].to_s.downcase)
        end

        stale.each do |row|
          Pf2eGrant[row['id']]&.update(:reverted_by => "spell rename #{Time.now.to_i}")

          Ledger.write(char, :source_type => row['source_type'], :source_ref => row['source_ref'],
                             :effective_level => row['effective_level'], :granted_by => 'Spell rename',
                             :materialize => false) do |txn|
            txn.grant(row['kind'], row['payload'].merge('spell' => table[row['payload']['spell'].to_s.downcase]))
          end
        end

        stale.size
      end

      MAGIC = %w{repertoire spellbook spells_prepared signature_spells spells_today innate_spells
                 restricted_spellbook prepared_lists mastered_spells daily_pick adapted_spells slot_pairs}.freeze

      def self.magic!(magic, table)
        changes = MAGIC.each_with_object({}) do |field, out|
          held = magic.public_send(field)
          moved = renamed(held, table)
          out[field.to_sym] = moved unless moved == held
        end

        magic.update(changes) unless changes.empty?
        changes.size
      end

      def self.entries!(char, table)
        return 0 unless char.respond_to?(:spellcasting_entries)

        char.spellcasting_entries.to_a.sum do |row|
          held = row.to_h
          moved = renamed(held, table)

          next 0 if moved == held

          row.update(moved.reject { |field, _| field == 'name' }.transform_keys(&:to_sym))
          1
        end
      end

      # A spell name wherever it sits in a nested value, as a string or a hash key.
      def self.renamed(value, table)
        case value
        when String then table.fetch(value.downcase, value)
        when Array then value.map { |one| renamed(one, table) }
        when Hash then value.each_with_object({}) { |(key, one), out| out[renamed(key, table)] = renamed(one, table) }
        else value
        end
      end
    end
  end
end
