module AresMUSH
  module Pf2e

    # Moves a Dar who took the heritage while it granted "Negative Healing" onto the remaster's name for
    # it, "Void Healing", which is the special the engine reads.
    #
    # The ledger's `add_special` grant is what the next fold writes `pf2_special` from, so it is renamed
    # by reverting it and writing the same grant under the new name, at the level and with the source it
    # had. The attribute itself is renamed too, for a character still in chargen whose fields are the
    # draft, and for one from before the ledger whose sheet is seeded from it.
    #
    # One character at a time, or `migrate_all!` from tinker. Running it again renames nothing.
    module VoidHealingRename

      OLD = 'Negative Healing'.freeze
      NEW = 'Void Healing'.freeze

      # How many names it changed.
      def self.migrate!(char)
        renamed = grants!(char)

        if renamed.positive?
          Ledger.invalidate!(char)
          Ledger.materialize!(Character[char.id])
        end

        renamed + special!(Character[char.id])
      end

      # Every character, saying which it could not move and why: one bad row does not stop the rest.
      def self.migrate_all!(characters: Character.all)
        characters.each_with_object({ 'changed' => {}, 'refused' => {} }) do |char, out|
          count = migrate!(char)
          out['changed'][char.name] = count if count.positive?
        rescue StandardError => e
          out['refused'][char.name] = e.message
        end
      end

      def self.grants!(char)
        stale = Ledger.rows(char).select do |row|
          row['reverted_by'].to_s.empty? && row['kind'] == 'add_special' &&
            (row['payload'] || {})['special'].to_s.casecmp?(OLD)
        end

        stale.each do |row|
          Pf2eGrant[row['id']]&.update(:reverted_by => "void healing rename #{Time.now.to_i}")

          Ledger.write(char, :source_type => row['source_type'], :source_ref => row['source_ref'],
                             :effective_level => row['effective_level'], :granted_by => 'Void Healing rename',
                             :materialize => false) do |txn|
            txn.grant('add_special', row['payload'].merge('special' => NEW))
          end
        end

        stale.size
      end

      def self.special!(char)
        held = Array(char.pf2_special)

        return 0 unless held.any? { |one| one.to_s.casecmp?(OLD) }

        char.update(:pf2_special => held.map { |one| one.to_s.casecmp?(OLD) ? NEW : one }.uniq)
        1
      end
    end
  end
end
