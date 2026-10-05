module AresMUSH
  module Pf2e
    module Advancement

      # An archetype's Breadth feat: one more slot at each rank below the archetype's two highest,
      # and for a repertoire caster one more repertoire spell there. The feat's `archetype_breadth`
      # block says how many of each.
      #
      # Which ranks it reaches follows the archetype's highest slot rank, which moves whenever Expert
      # or Master Spellcasting brings a new one. So this is recomputed each time the archetype's slots
      # change - when Breadth is taken, and after any archetype magic is staged - and it has to be safe
      # to run more than once in a level. It is, because a rank's slots are set as an absolute count:
      # a rank already at the spellcasting feats' count plus Breadth's has nothing left to add.
      module ArchetypeBreadth

        # The ranks Breadth reaches now that it did not before this level. `before` is the archetype's
        # highest rank on the sheet, `after` the highest counting this level, and `held` whether
        # Breadth was already on the sheet - if it was, the ranks `before` reached are already paid.
        def self.newly_owed(before, after, held)
          reached = below_two_highest(after)

          held ? reached - below_two_highest(before) : reached
        end

        def self.below_two_highest(highest)
          (1..(highest.to_i - 2)).to_a
        end

        # Stages what Breadth owes an archetype this level. Returns messages as [ locale key, args ]
        # pairs, or [ nil, text ] for one already rendered, and mutates to_assign and advancement.
        def self.stage(char, archetype, to_assign, advancement)
          feat, block, held = breadth(char, archetype, advancement)

          return [] unless block

          staged_slots = ((advancement['magic_stats'] || {})[archetype] || {})['spells_per_day'] || {}
          committed = numbered(committed_slots(char, archetype))
          staged = numbered(staged_slots)
          base = base_slots(archetype)
          extra = block['spells_per_day'].to_i

          owed = newly_owed(committed.keys.max, (committed.keys + staged.keys).max, held)
          ranks = owed.select { |rank| base[rank] && staged[rank].to_i < base[rank] + extra }

          return [] if ranks.empty?

          stats = { 'spells_per_day' => ranks.to_h { |rank| [ key_for(staged_slots, rank), base[rank] + extra ] } }

          if block['repertoire'].to_i > 0
            picks = (to_assign['repertoire'] || {})[archetype] || {}
            stats['repertoire'] = ranks.to_h { |rank| [ key_for(picks, rank), block['repertoire'].to_i ] }
          end

          labels = ranks.map { |rank| "#{Pf2emagic.ordinal_level(rank)} rank" }

          [ [ 'pf2e.adv_archetype_breadth',
              { :feat => feat, :archetype => archetype, :ranks => Pf2emagic.join_with_and(labels) } ] ] +
            Onboarding.apply_payload(char, archetype, { 'magic_stats' => stats }, to_assign, advancement,
              :source => 'feat', :name => feat)
        end

        # [ name, archetype_breadth block, whether it is on the sheet ] for the archetype's Breadth
        # feat, looking at the sheet first and then this level's picks, or nil when neither holds it.
        def self.breadth(char, archetype, advancement)
          config = Global.read_config('pf2e_feats') || {}
          sheet = (char.pf2_feats || {}).values.flatten
          picked = (advancement['feats'] || {}).values.flatten

          [ [ sheet, true ], [ picked, false ] ].each do |names, held|
            names.each do |name|
              key = config.keys.find { |k| k.to_s.casecmp?(name.to_s) }
              details = key && config[key]

              next unless details.is_a?(Hash) && details['archetype_breadth'].is_a?(Hash)
              next unless Array(details['assoc_archetype']).any? { |a| a.to_s.casecmp?(archetype.to_s) }

              return [ key, details['archetype_breadth'], held ]
            end
          end

          nil
        end

        def self.committed_slots(char, archetype)
          held = (char.magic&.spells_per_day || {}).find { |source, _| source.to_s.casecmp?(archetype.to_s) }

          held ? held[1] : {}
        end

        # rank => count for the numbered ranks, whichever way the keys came - YAML gives integers,
        # Redis strings.
        def self.numbered(slots)
          (slots || {}).each_with_object({}) do |(rank, count), found|
            next if rank.to_s.casecmp?('cantrip') || rank.to_i.zero?

            found[rank.to_i] = count.to_i
          end
        end

        # rank => count the archetype's spellcasting feats give, read from their `at_level` entries.
        def self.base_slots(archetype)
          (Global.read_config('pf2e_feats') || {}).each_value.with_object({}) do |details, base|
            next unless details.is_a?(Hash) && details['at_level'].is_a?(Hash)
            next unless Array(details['assoc_archetype']).any? { |a| a.to_s.casecmp?(archetype.to_s) }

            details['at_level'].each_value do |entry|
              slots = ((entry || {})[LevelClauses::ARCHETYPE_MAGIC] || {})['spells_per_day']

              numbered(slots).each_pair { |rank, count| base[rank] = [ base[rank].to_i, count ].max }
            end
          end
        end

        # The key a hash already uses for a rank, so a string "2" and an integer 2 do not end up as
        # two entries for one rank.
        def self.key_for(hash, rank)
          (hash || {}).keys.find { |key| key.to_s == rank.to_s } || rank
        end
      end
    end
  end
end
