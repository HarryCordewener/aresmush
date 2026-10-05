module AresMUSH
  module Pf2emagic

    ANY_RANK = 'any'

    # A pick at any rank the character can cast is keyed `any`. One limited to a rank and below is
    # keyed `up to <rank>`, as Signature Spell Expansion's "base rank of 3rd or lower" is.
    CAPPED_ANY_RANK = /\Aup to (\d+)\z/i

    def self.any_rank?(key)
      key.to_s.casecmp?(ANY_RANK) || key.to_s.strip.match?(CAPPED_ANY_RANK)
    end

    # The highest rank an any-rank key takes, or nil when only the character's own slots limit it.
    def self.any_rank_cap(key)
      match = key.to_s.strip.match(CAPPED_ANY_RANK)

      match ? match[1].to_i : nil
    end

    # rank => open picks, from 1st rank up to the highest, keyed as a rank list is.
    def self.each_rank_picks(max_rank, per_rank)
      (1..max_rank.to_i).each_with_object({}) do |rank, picks|
        picks[rank.to_s] = Array.new(per_rank.to_i, 'open')
      end
    end

    # The highest rank the character's own class has slots for, counting a level-up in progress.
    def self.castable_rank(char)
      Pf2e.preview_max_spell_rank(char, char.pf2_base_info['charclass']).to_i
    end

    def self.any_rank_heading(key)
      cap = any_rank_cap(key)

      cap ? t('pf2emagic.any_rank_up_to_heading', :rank => rank_label(cap)) : t('pf2emagic.any_rank_heading')
    end

    def self.adapted_spell?(char, charclass, spell_name)
      magic = char.magic
      return false unless magic

      entry = (magic.adapted_spells || {}).find { |name, _| name.to_s.casecmp?(spell_name.to_s) }
      return false unless entry

      klass = entry[1].is_a?(Hash) ? entry[1]['class'].to_s : ''

      klass.empty? || klass.casecmp?(charclass.to_s)
    end

    # The deity's cleric spells, for a class whose config says its deity adds them to its spell list
    # (the Cleric). The deity grants them, so an uncommon one needs no other access.
    def self.deity_list_spells(char, charclass)
      return [] unless Global.read_config('pf2e_class', charclass.to_s, 'deity_spells')

      deity = (char.pf2_faith || {})['deity']
      return [] if deity.blank?

      Pf2e.deity_cleric_spells(deity)
    end

    def self.deity_list_spell?(char, charclass, spell_name)
      deity_list_spells(char, charclass).any? { |spell| spell.casecmp?(spell_name.to_s) }
    end

    # Whether one more spell off the class's tradition list may go in its repertoire (Mysterious
    # Repertoire). `replacing` is the spell a swap gives up, which frees its place.
    def self.off_list_room?(char, charclass, replacing = nil)
      allowed = off_list_allowance(char)
      return false unless allowed.positive?

      held = off_list_picks(char, charclass).reject { |spell| spell.casecmp?(replacing.to_s) }

      held.size < allowed
    end

    # How many off-list repertoire spells the character's feats allow at a time, counting a feat
    # the level-up in progress takes.
    def self.off_list_allowance(char)
      Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).sum do |name|
        found = Pf2e.get_feat_details(name)

        found.is_a?(Array) ? found[1]['off_list_repertoire'].to_i : 0
      end
    end

    # The repertoire spells chosen from off the class's tradition list, this level's picks included.
    # The spells the specialty put there and adapted spells are the class's own, and a spell a
    # choice adds (Divine Access) is never in the stored repertoire.
    def self.off_list_picks(char, charclass)
      tradition = Entries.tradition_of(char.magic, charclass).to_s
      return [] if tradition.empty?

      specialty = Global.read_config('pf2e_specialty', charclass.to_s, (char.pf2_base_info || {})['specialize'].to_s)
      granted = Pf2e::Advancement::Repertoire.granted(specialty, char.pf2_level.to_i + 1).map(&:downcase)
      held = (Pf2e::DraftSheet.of(char).repertoire(charclass)[charclass] || {}).values.flatten.map(&:to_s)

      held.reject { |spell| spell.casecmp?('open') }.uniq(&:downcase).select do |spell|
        next false if granted.include?(spell.downcase)
        next false if adapted_spell?(char, charclass, spell)

        found = get_spell_details(spell)
        traditions = found.is_a?(Array) ? Array(found[1]['tradition']) : []

        !traditions.empty? && traditions.none? { |t| t.to_s.casecmp?(tradition) }
      end
    end

    # Any tradition but innate makes a caster; innate alone does where it holds innate spells.
    def self.is_caster?(char)
      magic = char.magic
      return false unless magic

      # The tradition register carries a literal 'innate' key that is not a casting source.
      casting = (magic.tradition || {}).reject { |key, _| key.to_s.casecmp?('innate') }

      return true unless casting.empty?

      Entries.innate?(magic)
    end

    def self.generate_spells_today(char)

      magic = char.magic

      spells_today = {}

      return t('pf2emagic.not_caster') unless magic

      class_list = magic.tradition.keys
      class_list.delete('innate')

      class_list.each do |cc|
        caster_type = Pf2emagic.get_caster_type(cc)
        next unless caster_type

        if caster_type == 'prepared'
          prepared_list = magic.spells_prepared
          # Spell Mastery's spells are prepared at every rest, in slots of their own.
          spells_today[cc] = SlotFeats.with_mastered(prepared_list[cc], magic, cc)
        else
          spells_today[cc] = Entries.slots(magic, cc)
        end
      end

      # Only the ranked ones take a daily use; cantrips are cast at will.
      innate_spells_today = Entries.innate_ranked(magic).each_with_object({}) do |grant, today|
        rank = grant['level'].to_s

        today[rank] = Array(today[rank]) + [ grant['name'] ]
      end

      spells_today['innate'] = innate_spells_today unless innate_spells_today.empty?

      # Two spells prepared in one slot (Split Slot, Spell Combination).
      pairs = SlotFeats.today(magic)
      spells_today[SlotFeats::TODAY] = pairs unless pairs.empty?

      # A slot a feat adds for certain spells (Divine Evolution), one use a day.
      bonus = BonusSlots.fresh(char)
      spells_today[BonusSlots::TODAY] = bonus unless bonus.empty?

      # A spell picked from a book lasts until the next daily preparations, which is now.
      magic.update(spells_today: spells_today, daily_pick: {})

    end

    # Refocusing, for someone as they stand in an encounter. The GM may refocus anyone, whatever their pool
    # holds; anyone else only a pool that is short of full.
    def self.do_refocus(target, gm = false)

      # This is included because it validates the existence of a magic object.
      return t('pf2emagic.not_caster') unless is_caster?(target)

      magic = target.magic

      max = focus_pool_max(magic)
      current = focus_points_left(magic)

      return t('pf2emagic.no_focus_pool') if max.zero?

      return t('pf2emagic.cant_refocus_pool') unless gm || current < max

      current = refocus_refills?(target) ? max : [ current + 1, max ].min

      magic.update(focus_pool: { 'current' => current })

      return nil
    end

    # A Refocus restores one point, or the whole pool for a character holding a feat marked
    # `refocus: refill` - Domain Focus and the class feats like it.
    def self.refocus_refills?(char)
      Pf2e::DraftSheet.of(char).feats_by_bucket.values.flatten.any? do |feat|
        details = Pf2e.get_feat_details(feat)

        !details.is_a?(String) && details[1]['refocus'].to_s == 'refill'
      end
    end

    def self.curriculum_spells(char, charclass, level)
      specialize = char.pf2_base_info['specialize']
      return [] if specialize.blank?

      specialty = Global.read_config('pf2e_specialty', charclass.to_s, specialize)
      return [] unless specialty.is_a?(Hash)

      curriculum = specialty['curriculum']
      return [] unless curriculum.is_a?(Hash)

      key = curriculum.keys.find { |k| k.to_s.casecmp?(level.to_s) }

      Array(key && curriculum[key]).compact.map(&:to_s)
    end

    def self.apply_stat_delta(current, value)
      return value unless value.is_a?(String) && value.strip.match?(/\A[+-]\d+\z/)

      current.to_i + value.strip.to_i
    end

    # The most points a focus pool holds: one per focus spell known that costs a point, up to three
    # (Player Core, Focus Spells). A spell two sources grant is one spell, and cantrips count for
    # nothing. Counted whenever it is asked for, so it follows every grant, rollback and correction.
    def self.focus_pool_max(magic)
      return 0 unless magic

      spells = Entries.focus_entries(magic).flat_map { |e| Array((e['known'] || {})['spell']) }

      spells.map(&:to_s).uniq(&:downcase).reject { |spell| focus_cantrip?(spell) }.size.clamp(0, 3)
    end

    # The points left, never more than the pool now holds.
    def self.focus_points_left(magic)
      return 0 unless magic

      [ (magic.focus_pool || {})['current'].to_i, focus_pool_max(magic) ].min
    end

    # A cantrip costs no point to cast. That is rank 0, or the cantrip trait: a bard's composition
    # cantrips have ranks above 0 and are cantrips all the same.
    def self.focus_cantrip?(spell)
      spells = Global.read_config('pf2e_spells') || {}
      key = spells.key?(spell) ? spell : spells.keys.find { |name| name.to_s.casecmp?(spell.to_s) }
      details = key && spells[key]

      return false unless details.is_a?(Hash)

      rank = details['base_level'].to_s.downcase

      rank == 'cantrip' || rank == '0' || Array(details['traits']).any? { |t| t.to_s.casecmp?('cantrip') }
    end

    def self.get_spell_details(term)
      result = get_spells_by_name(term)

      return t('pf2emagic.no_match', :item => "spells") if result.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if result.size > 1

      spell_name = result.first

      spell_details = Global.read_config('pf2e_spells', spell_name)

      [ spell_name, spell_details ]
    end

    # Every spell a source casting `tradition` could put in a slot of `rank`.
    #
    # The same two rules SpellPick enforces when a pick is made - the tradition has to match, and a
    # spell cannot be learned above its own rank or in the wrong kind of slot - asked in advance,
    # so a player can read the list instead of guessing a name and being refused.
    def self.eligible_spells(tradition, rank)
      wanted = tradition.to_s.downcase
      cantrip_slot = rank.to_s.casecmp?('cantrip') || rank.to_s.to_i.zero?

      (Global.read_config('pf2e_spells') || {}).select do |_name, details|
        traditions = Array(details['tradition']).compact.map { |trad| trad.to_s.downcase }

        next false unless traditions.include?(wanted)

        base = details['base_level']
        spell_cantrip = base.to_s.casecmp?('cantrip') || base.to_s.to_i.zero?

        next spell_cantrip if cantrip_slot
        next false if spell_cantrip

        base.to_i <= rank.to_i
      end.keys.sort
    end

    def self.search_spells(search_type, term, operator='=')
      spell_info = Global.read_config('pf2e_spells')

      case search_type
      when 'name'
        match = spell_info.select { |k,v| k.upcase.match? term.upcase }
      when 'traits'
        match = spell_info.select { |k,v| v['traits'].include? term.downcase }
      when 'level'
        # Invalid operator defaults to ==.
        case operator
        when '<'
          match = spell_info.select { |k,v| (v['base_level'].to_i < term.to_i) && v['tradition'] }
        when '>'
          match = spell_info.select { |k,v| (v['base_level'].to_i > term.to_i) && v['tradition'] }
        else
          match = spell_info.select { |k,v| (v['base_level'].to_i == term.to_i) && v['tradition'] }
        end
      when 'tradition'
        match = spell_info.select { |k,v| v['tradition'] && (v['tradition'].include? term.downcase) }
      when 'school'
        match = spell_info.select { |k,v| v['school']&.include?(term.capitalize) }
      when 'bloodline'
        match = spell_info.select { |k,v| v['bloodline']&.include?(term.downcase) }
      when 'cast'
        match = spell_info.select { |k,v| v['cast']&.include? term.downcase }
      when 'description', 'desc', 'effect'
        match = spell_info.select { |k,v| v['effect'].upcase.match? term.upcase }
      end

      match.keys

    end

    def self.sort_level_spell_list(spells)
      # This function takes a hash and sorts it by integer-converted key.
      spells.sort {|a,b| a.first.to_i <=> b.first.to_i}.to_h
    end

    # The display name for a spell rank, the same everywhere a rank is shown regardless of the
    # caster's class.
    def self.rank_label(level)
      return 'Cantrip' if level.to_s.strip.casecmp?('cantrip') || level.to_i.zero?

      n = level.to_i
      suffix = case n % 10
               when 1 then 'st'
               when 2 then 'nd'
               when 3 then 'rd'
               else 'th'
               end

      "#{n}#{suffix}-rank"
    end

  end
end
