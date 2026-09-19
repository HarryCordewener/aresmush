module AresMUSH
  module Pf2e

    # What a condition or an effect brings with it.
    #
    # Grabbed makes you off-guard and immobilized; Dying makes you unconscious, which blinds you and puts
    # you on the ground. Foundry writes each of those as a `GrantItem` naming the other by compendium,
    # and the grant says what becomes of the granted thing when the granter goes. Their answer, read
    # here unchanged (`grant-item/rule-element.ts`):
    #
    #   * `inMemoryOnly` - it exists only while the granter does, and is never stored. Off-Guard from
    #     Grabbed is this: it is a consequence, not a condition anybody gave you.
    #   * otherwise it is stored in its own right, and `onDeleteActions` decides the rest:
    #       granter  what happens to it when the granter goes - `cascade` (it goes too, the default) or
    #                `detach` (it stays: you wake from unconsciousness still prone)
    #       grantee  whether it may be taken away while the granter holds - `restrict` says it may not,
    #                so nobody clears Unconscious off a character who is still dying
    module Grants

      UUID = /\ACompendium\.pf2e\.([\w-]+)\.Item\.(.+)\z/

      # The compendia a grant may name, onto the catalogue here that holds the same things.
      CATALOGUES = { 'conditionitems' => 'conditions', 'spell-effects' => 'effects',
                     'feat-effects' => 'effects', 'equipment-effects' => 'effects',
                     'other-effects' => 'effects' }.freeze

      # What becomes of a stored grant when its granter goes. Foundry defaults a granted condition or
      # effect to going with it; only a physical item stays by default, and those are not granted here.
      WHEN_GRANTER_GOES = %w{cascade detach}.freeze
      DEFAULT_WHEN_GRANTER_GOES = 'cascade'.freeze

      # What `set_condition` and `remove_condition` are told a granted condition carries on it, so the
      # stored record says how it came to be there.
      #
      #   granted_by         the condition that brought it
      #   when_granter_goes  cascade or detach
      #   restricted         whether it may be removed while its granter holds
      FIELDS = %w{granted_by when_granter_goes restricted}.freeze

      # Every grant in these rules, as the catalogue and name it resolves to and what becomes of it.
      def self.of(rules)
        Array(rules).select { |row| row['key'].to_s == 'GrantItem' }.map { |row| read(row) }.compact
      end

      def self.read(row)
        catalogue, name = target(row['uuid'])

        return nil unless catalogue

        actions = row['onDeleteActions'] || {}

        { 'catalogue' => catalogue, 'name' => name,
          'derived' => row['inMemoryOnly'] == true,
          'value' => badge(row),
          'predicate' => row['predicate'],
          'duplicate' => row['allowDuplicate'] != false,
          'when_granter_goes' => actions['granter'] || DEFAULT_WHEN_GRANTER_GOES,
          'restricted' => actions['grantee'] == 'restrict' }
      end

      # The catalogue and the name a compendium reference points at, or nil for one we hold no
      # catalogue of.
      def self.target(uuid)
        found = UUID.match(uuid.to_s)

        return nil unless found && CATALOGUES[found[1]]

        [ CATALOGUES[found[1]], found[2] ]
      end

      # The value a grant gives what it grants, where it says: Encumbered's clumsy is clumsy 1 unless an
      # alteration says otherwise.
      def self.badge(row)
        altered = Array(row['alterations']).find { |one| one['property'].to_s == 'badge-value' }

        altered && altered['value']
      end
    end
  end
end
