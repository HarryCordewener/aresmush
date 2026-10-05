module AresMUSH
  module Pf2e
    module Advancement

      # A feat's `at_level` entry coming due, on taking the feat or on reaching the level later.
      #
      # Most of an entry is a grants block, which the caller files for advance/done. The exception is
      # `archetype_magic`, spellcasting that adds to an archetype's own casting: the Basic, Expert and
      # Master Spellcasting feats. That is staged the way a Dedication stages the casting it starts -
      # under the archetype's key, with its spell picks opened while the level is still open. Applied
      # at advance/done it would reach update_magic under the base class, and the picks it opened would
      # be cleared along with the rest of the pool.
      #
      # `proficiency` inside it raises whatever tradition the archetype casts from. A Sorcerer's comes
      # from the bloodline and a Witch's from the patron, so the feat cannot name it.
      module LevelClauses

        ARCHETYPE_MAGIC = 'archetype_magic'.freeze

        # [ archetype magic, the rest ] of one entry.
        def self.split(payload)
          payload = payload.is_a?(Hash) ? payload : {}

          [ payload[ARCHETYPE_MAGIC], payload.reject { |key, _| key.to_s == ARCHETYPE_MAGIC } ]
        end

        # Stages an entry's archetype magic. Returns messages as [ locale key, args ] pairs, or
        # [ nil, text ] for one already rendered, and mutates to_assign and advancement.
        def self.archetype_magic(char, feat, magic, to_assign, advancement)
          return [] unless magic.is_a?(Hash) && !magic.empty?

          archetype = archetype_for(feat)

          unless archetype
            Global.logger.error "#{feat} carries #{ARCHETYPE_MAGIC} but names no archetype."
            return []
          end

          stats = magic.reject { |key, _| key.to_s == 'proficiency' }

          if magic['proficiency']
            tradition = held_tradition(char, archetype, advancement)

            if tradition
              stats = stats.merge('tradition' => { tradition => magic['proficiency'] })
            else
              Global.logger.error "#{feat} raises #{archetype}'s proficiency, but #{archetype} casts from no tradition."
            end
          end

          # A new highest rank may bring the ranks below it into a Breadth feat's reach.
          Onboarding.apply_payload(char, archetype, { 'magic_stats' => stats }, to_assign, advancement,
            :source => 'feat', :name => feat) +
            ArchetypeBreadth.stage(char, archetype, to_assign, advancement)
        end

        def self.archetype_for(feat)
          found = Pf2e.get_feat_details(feat)

          return nil if found.is_a?(::String)

          Array(found[1]['assoc_archetype']).first
        end

        # The tradition an archetype casts from: staged in this advancement, or on the magic object.
        def self.held_tradition(char, archetype, advancement)
          staged = ((advancement['magic_stats'] || {})[archetype] || {})['tradition']

          return staged.keys.first.to_s if staged.is_a?(Hash) && !staged.empty?

          held = (char.magic&.tradition || {}).find { |source, _| source.to_s.casecmp?(archetype.to_s) }

          held && Array(held[1]).first
        end
      end
    end
  end
end
