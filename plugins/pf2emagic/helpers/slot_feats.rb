module AresMUSH
  module Pf2emagic

    # Feats that change what a prepared caster's slots hold, each through a prepare switch its data
    # names, so no code names a feat:
    #
    #   prepared_slot:               # two spells in one slot
    #     switch: splitslot
    #     cast: either               # cast one and the other is lost (Split Slot), or
    #                                # both at once (Spell Combination)
    #     count: 1                   # how many such slots in all, or
    #     per_rank: 1                # how many at each rank
    #     below_top: 1               # at least this many ranks below the highest
    #     min_rank: 3
    #     components_below: 2        # both are cast this many ranks below the slot
    #
    #   mastered_spells:             # spells prepared at every rest in slots of their own
    #     switch: spellmastery       # (Spell Mastery)
    #     count: 4
    #     max_rank: 9
    #
    # A pair is kept in magic.slot_pairs and takes one of the rank's ordinary slots. Mastered
    # spells are kept in magic.mastered_spells and added to the day's spells at a rest.
    module SlotFeats

      KINDS = %w{prepared_slot mastered_spells}.freeze

      # What a pair holds in the ordinary slot count, since it is not one spell.
      PLACEHOLDER = '(two spells in one slot)'.freeze

      # Where a rest copies the pairs to, beside the class-keyed lists.
      TODAY = 'slot pairs'.freeze

      # Every switch any feat declares, for routing a command before a character is looked at.
      def self.switch?(switch)
        (Global.read_config('pf2e_feats') || {}).any? do |_name, details|
          next false unless details.is_a?(Hash)

          KINDS.any? { |kind| details[kind].is_a?(Hash) && details[kind]['switch'].to_s.casecmp?(switch.to_s) }
        end
      end

      # { 'feat', 'class', 'kind', 'block' } for the character's feat declaring a switch, or nil.
      def self.for_switch(char, switch)
        Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).each do |name|
          found = Pf2e.get_feat_details(name)
          next unless found.is_a?(Array)

          KINDS.each do |kind|
            block = found[1][kind]
            next unless block.is_a?(Hash) && block['switch'].to_s.casecmp?(switch.to_s)

            return { 'feat' => found[0], 'class' => Array(found[1]['assoc_charclass']).first.to_s,
                     'kind' => kind, 'block' => block }
          end
        end

        nil
      end

      def self.top_rank(char, charclass)
        Entries.slots(char.magic, charclass).keys.map(&:to_s).reject { |r| r.casecmp?('cantrip') }.map(&:to_i).max.to_i
      end

      def self.pairs(magic, charclass)
        Array((magic.slot_pairs || {})[charclass])
      end

      # One placeholder per pair prepared at a rank, for counting it against the rank's slots.
      def self.placeholders(magic, charclass, rank)
        pairs(magic, charclass).select { |pair| pair['rank'].to_s == rank.to_s }.map { |_pair| PLACEHOLDER }
      end

      def self.err(key, args = {})
        Pf2e::Err.new(key.to_sym, "pf2emagic.#{key}", args)
      end

      # ------------------------------------------------------------------------------
      # Two spells in one slot
      # ------------------------------------------------------------------------------

      # Why a pair cannot go at this rank, or nil. Pure: the feat's block, the rank, the highest rank
      # the class casts, and the ranks of the feat's pairs already prepared.
      def self.rank_refusal(block, rank, top, held_ranks)
        return err('slot_pair_bad_rank') unless rank.to_i.positive?
        return err('slot_pair_rank_too_high', 'rank' => top - block['below_top'].to_i) if rank.to_i > top - block['below_top'].to_i
        return err('slot_pair_rank_too_low', 'rank' => block['min_rank']) if block['min_rank'] && rank.to_i < block['min_rank'].to_i

        if block['per_rank']
          return err('slot_pair_rank_full', 'rank' => rank) if held_ranks.count { |r| r.to_s == rank.to_s } >= block['per_rank'].to_i
        elsif block['count']
          return err('slot_pair_all_used', 'count' => block['count']) if held_ranks.size >= block['count'].to_i
        end

        nil
      end

      # The rank the pair's spells are cast at: the slot's, or lower for a combination.
      def self.cast_rank(block, rank)
        rank.to_i - block['components_below'].to_i
      end

      def self.prepare_pair(char, found, rank, names)
        magic = char.magic
        block = found['block']
        charclass = found['class']

        return err('slot_pair_two_spells') unless names.size == 2

        held = pairs(magic, charclass).select { |pair| pair['feat'] == found['feat'] }.map { |pair| pair['rank'] }
        refusal = rank_refusal(block, rank, top_rank(char, charclass), held)
        return refusal if refusal

        at = cast_rank(block, rank)

        checked = names.map do |name|
          result = Pf2emagic.check_preparable(char, charclass, name, at.to_s)
          return Pf2e::Err.new(:not_preparable, 'pf2emagic.slot_pair_spell_refused', 'spell' => name, 'why' => result) if result.is_a?(String)

          result['name']
        end

        return err('slot_pair_same_spell') if checked[0].casecmp?(checked[1])

        prepared = Array(((magic.spells_prepared || {})[charclass] || {})[rank.to_s])
        taken = prepared + placeholders(magic, charclass, rank) + [ PLACEHOLDER ]

        unless taken.size <= Pf2emagic.max_spells_per_day(char, charclass, rank.to_s) &&
               Pf2emagic.prepared_set_fits?(char, charclass, rank.to_s, taken)
          return err('slot_pair_no_slot', 'rank' => rank)
        end

        pair = { 'feat' => found['feat'], 'rank' => rank.to_s, 'spells' => checked,
                 'cast' => block['cast'].to_s, 'cast_rank' => at.to_s }

        all = magic.slot_pairs || {}
        all[charclass] = pairs(magic, charclass) + [ pair ]
        magic.update(:slot_pairs => all)

        Pf2e::Ok.new(:state => pair)
      end

      def self.unprepare_pair(char, found, rank)
        magic = char.magic
        charclass = found['class']
        list = pairs(magic, charclass)
        index = list.index { |pair| pair['feat'] == found['feat'] && (rank.blank? || pair['rank'].to_s == rank.to_s) }

        return err('slot_pair_none', 'feat' => found['feat']) unless index

        removed = list.delete_at(index)
        magic.update(:slot_pairs => (magic.slot_pairs || {}).merge(charclass => list))

        Pf2e::Ok.new(:state => removed)
      end

      # The pair a cast draws on from the day's spells: one holding the spell, at the rank asked
      # for if one was. Removed from the day, since the slot is spent either way.
      def self.cast_from_pair(magic, charclass, spell, rank)
        today = magic.spells_today || {}
        list = Array((today[TODAY] || {})[charclass])
        index = list.index do |pair|
          Array(pair['spells']).any? { |s| s.casecmp?(spell.to_s) } && (rank.nil? || pair['rank'].to_s == rank.to_s)
        end

        return nil unless index

        pair = list.delete_at(index)
        today[TODAY] = (today[TODAY] || {}).merge(charclass => list)
        magic.update(:spells_today => today)

        pair
      end

      # ------------------------------------------------------------------------------
      # Mastered spells
      # ------------------------------------------------------------------------------

      def self.mastered(magic, charclass)
        (magic.mastered_spells || {})[charclass] || {}
      end

      # Why a spell cannot be mastered at this rank, or nil. Pure. Replacing the spell already
      # mastered at a rank is allowed, since the ranks must differ.
      def self.mastery_refusal(block, rank, held)
        return err('mastery_rank_too_high', 'rank' => block['max_rank']) if block['max_rank'] && rank.to_i > block['max_rank'].to_i
        return nil if held.key?(rank.to_s)
        return err('mastery_all_used', 'count' => block['count']) if held.size >= block['count'].to_i

        nil
      end

      def self.master_spell(char, found, rank, name)
        magic = char.magic
        charclass = found['class']

        checked = Pf2emagic.check_preparable(char, charclass, name, rank.presence)
        return Pf2e::Err.new(:not_preparable, 'pf2emagic.slot_pair_spell_refused', 'spell' => name, 'why' => checked) if checked.is_a?(String)

        at = checked['level']
        return err('mastery_no_cantrip') if at == 'cantrip'

        held = mastered(magic, charclass)
        refusal = mastery_refusal(found['block'], at, held)
        return refusal if refusal

        replaced = held[at]
        all = magic.mastered_spells || {}
        all[charclass] = held.merge(at => checked['name'])
        magic.update(:mastered_spells => all)

        Pf2e::Ok.new(:state => { 'spell' => checked['name'], 'rank' => at, 'replaced' => replaced })
      end

      def self.forget_mastered(char, found, name)
        magic = char.magic
        charclass = found['class']
        held = mastered(magic, charclass)
        rank = held.keys.find { |r| held[r].to_s.casecmp?(name.to_s) || r.to_s == name.to_s }

        return err('mastery_not_held', 'spell' => name) unless rank

        spell = held[rank]
        all = magic.mastered_spells || {}
        all[charclass] = held.reject { |r, _s| r == rank }
        magic.update(:mastered_spells => all)

        Pf2e::Ok.new(:state => { 'spell' => spell, 'rank' => rank })
      end

      # ------------------------------------------------------------------------------
      # A rest
      # ------------------------------------------------------------------------------

      # The day's prepared list for a class with its mastered spells added, each in a slot of its own.
      def self.with_mastered(prepared, magic, charclass)
        list = Marshal.load(Marshal.dump(prepared || {}))

        mastered(magic, charclass).each_pair do |rank, spell|
          list[rank.to_s] = Array(list[rank.to_s]) + [ spell ]
        end

        list
      end

      # class => [ pairs ] for the day.
      def self.today(magic)
        Marshal.load(Marshal.dump(magic.slot_pairs || {})).reject { |_cc, list| Array(list).empty? }
      end
    end
  end
end
