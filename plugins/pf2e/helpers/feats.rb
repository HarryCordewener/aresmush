module AresMUSH
  module Pf2e

    include CommonTemplateFields

    def self.get_feat_details(term)
      return "no_term" unless term.is_a? String

      feats = Global.read_config('pf2e_feats')

      keys = feats.keys

      name = ""

      # Give me an array of all the feats that match the term.
      match = keys.select { |f| f.upcase.match? Regexp.escape(term.upcase) }

      return 'no_match' if match.empty?

      if match.size > 1
        # Look for an exact match, allows 'Familiar' to be taken when 'Leshy Familiar' is in the list.
        match.each do |item|
          if item.upcase == term.upcase
            name = match.find { |item| item.casecmp?(term) } || name
          end
        end

        return 'ambiguous' if name.empty?
      else
        # Pull the unique feat name out of the array so it can be used as a key to get the feat deets.
          name = match.first
      end

      # First is the name of the feat matched, the second is the details for the feat.
      return [ name, feats[name] ]
    end

    def self.get_feat_match_options(term)
      return [] unless term.is_a? String

      feats = Global.read_config('pf2e_feats')
      keys = feats.keys

      match = keys.select { |f| f.upcase.match? Regexp.escape(term.upcase) }
      return [] if match.empty?

      exact = match.find { |item| item.casecmp?(term) }
      return [] if exact

      match.sort
    end

    # What to say when a feat name matched nothing. A pre-Remaster name is the common case, and
    # the rename table answers it outright; only a name it has never heard of gets the spelling
    # advice, which is all this used to say.
    def self.bad_feat_message(term)
      names = (Global.read_config('pf2e_feats') || {}).keys

      Pf2e::Renames.hint_for('feats', term, names) || t('pf2e.bad_feat_name', :name => term)
    end

    # The player-facing answer for each way get_feat_details can fail, so every command that
    # resolves a feat name gives the same one.
    def self.feat_lookup_failure(term, code)
      return t('pf2e.multiple_feat_matches', :options => get_feat_match_options(term).join(", ")) if code == 'ambiguous'

      bad_feat_message(term)
    end

    def self.search_feats(search_type, term, operator='=')
      feat_info = Global.read_config('pf2e_feats')

      case search_type
      when 'name'
        match = feat_info.select { |k,v| k.upcase.match? term.upcase }
      when 'traits'
        match = feat_info.select { |k,v| v['traits'].include? term.downcase }
      when 'level'
        # Invalid operator defaults to ==.
        case operator
        when '<'
          match = feat_info.select { |k,v| v['prereq']['level'] < term.to_i }
        when '>'
          match = feat_info.select { |k,v| v['prereq']['level'] > term.to_i }
        else
          match = feat_info.select { |k,v| v['prereq']['level'] == term.to_i }
        end
      when 'feat_type'
        match = feat_info.select { |k,v| v['feat_type'].include? term.capitalize }
      when 'class'
        match = feat_info.select { |k,v| v['assoc_charclass']&.include? term.capitalize }
      when 'ancestry'
        match = feat_info.select { |k,v| v['assoc_ancestry']&.include? term.capitalize }
      when 'skill'
        match = feat_info.select do |k, v|
          skills = Array(v['assoc_skill']).compact
          skills.any? { |s| s.downcase.include?(term.downcase) }
        end
      when 'description', 'desc'
        match = feat_info.select { |k,v| v['shortdesc'].upcase.match? term.upcase }
      when 'classlevel'
        feats_by_class = feat_info.select { |k,v| v['assoc_charclass']&.include? operator.capitalize }
        match = feats_by_class.select { |k,v| v['prereq']['level'] == term.to_i }
      when 'archetype'
        match = feat_info.select { |k,v| v['assoc_archetype']&.any? { |a| a.downcase.include?(term.downcase) } }
      end

      match

    end

    def self.dedication_allowed?(char, details)
      return true unless details

      feat_type = details['feat_type']
      return true unless feat_type&.include?('Dedication')

      base_class = char.pf2_base_info['charclass']
      assoc_classes = Array(details['assoc_class']).compact
      assoc_charclasses = Array(details['assoc_charclass']).compact

      # Two separate questions, and a dedication needs a yes to both.
      #
      # Which classes may take this archetype at all. `assoc_class` is a whitelist that leaves out
      # the archetype's own class, so a Fighter cannot take Fighter Dedication.
      if !assoc_classes.empty?
        return false unless assoc_classes.any? { |c| c.to_s.casecmp?(base_class.to_s) }
      elsif assoc_charclasses.any? { |c| c.to_s.casecmp?(base_class.to_s) }
        return false
      end

      # And whether this character may take another dedication yet. PF2e: "You cannot select
      # another dedication feat until you have gained two other feats from the archetype."
      dedication_archetype_ready?(char)
    end

    def self.dedication_archetype_ready?(char)
      feat_info = Global.read_config('pf2e_feats') || {}
      return true if feat_info.empty?

      feat_name_map = {}
      feat_info.keys.each { |name| feat_name_map[name.to_s.upcase] = name }

      feat_names = DraftSheet.of(char).feat_names

      dedication_archetypes = []
      archetype_feat_counts = Hash.new(0)

      feat_names.each do |feat_name|
        details_key = feat_name_map[feat_name.to_s.upcase]
        next unless details_key

        details = feat_info[details_key]
        next unless details

        assoc_archetypes = Array(details['assoc_archetype']).compact
        next if assoc_archetypes.empty?

        if details['feat_type']&.include?('Dedication')
          dedication_archetypes << assoc_archetypes
        else
          assoc_archetypes.each do |arch|
            archetype_feat_counts[arch.to_s.downcase] += 1
          end
        end
      end

      return true if dedication_archetypes.empty?

      dedication_archetypes.all? do |archetypes|
        archetypes.any? { |arch| archetype_feat_counts[arch.to_s.downcase] >= 2 }
      end
    end

    def self.can_take_feat?(char, feat)
      find_feat = Pf2e.get_feat_details(feat)

      # This will come back as a string if the feat name is bad or not unique.
      return false if find_feat.is_a? String

      # Pass the canonical name rather than what the caller typed, so the multiclass feat
      # lists below match.
      can_take_feat_details?(char, find_feat[0], find_feat[1])
    end

    # Eligibility check for a feat whose details the caller already has.
    def self.can_take_feat_details?(char, feat, details, effective_level = nil, ignore_charclass = false)
      return false if !details

      msg = []

      # Ancestry and character class checks
      # Dedication check for class feats is not done in this function.

      cinfo = char.pf2_base_info
      feat_type = details['feat_type']

      return false if !feat_type

      # Lineage feats are explicitly for select heritages and can only be taken at level 1.
      
      if feat_type.include? 'Lineage'

        heritage = cinfo['heritage'].downcase
        traits = details['traits']

        msg << 'lineage' unless traits.include?(heritage) && (char.pf2_level == 1)
      end

      if feat_type.include? 'Charclass'
        charclass = cinfo['charclass']
        allowed_charclasses = details['assoc_charclass']

        # Dedication and archetype feats are typed Charclass but deliberately carry no
        # assoc_charclass, so that feat/search class=Fighter returns fighter class feats
        # rather than fighter archetype ones. Who may take them is handled by assoc_class in
        # dedication_allowed?, and by their prereq chain back to the dedication feat.
        unless ignore_charclass
          msg << 'charclass' if allowed_charclasses && !allowed_charclasses.include?(charclass)
        end
      elsif feat_type.include? 'Ancestry'
        ancestry = []

        ancestry << cinfo['ancestry']

        # # Add allowances for Silyara and Ghaluch
        ancestry << "Sildanyar" if cinfo['heritage'] == "Silyara"
        ancestry << "Oruch" if cinfo['heritage'].include? "Ghaluch"

        allowed_ancestry = details['assoc_ancestry']

        if allowed_ancestry.intersection(ancestry).empty?
          # An adopted ancestry is handled separately from the ones the character was born
          # with, because it opens only that ancestry's adopted_feats rather than its whole
          # list.
          adopted = adopted_ancestries(char).any? do |a|
            allowed_ancestry.include?(a) && adopted_feat?(a, feat)
          end

          msg << 'ancestry' unless adopted
        end
      end

      # No double-dipping on base class / dedication, per Paizo RAW.
      msg << 'dedication' unless dedication_allowed?(char, details)

      # Prereq check, prerequisites includes level

      prereqs = details["prereq"]

      if prereqs
        cl = effective_level || effective_char_level(char)

        meets_prereqs = Pf2e.meets_prereqs?(char, prereqs, cl)
      else
        meets_prereqs = true
      end

      msg << "prerequisites" if !meets_prereqs

      return true if msg.empty?
      return false
    end

    # Every subclass the character counts as having for prerequisite purposes: the one from
    # their own class, plus one per archetype they have taken.
    def self.held_specialties(char)
      info = char.pf2_archetypeinfo || {}

      held = (1..4).map { |i| info["archetype_specialty#{i}"] }
      held << char.pf2_base_info['specialize']

      if char.advancing
        pending = (char.pf2_to_assign || {})['archetype_specialty']
        held << pending unless pending.blank? || pending.to_s.casecmp?('open')
      end

      # A specialty joined through a feat's choice (Order Explorer, Multifarious Muse).
      flagged_choices(char, 'joins_specialty').each { |_name, labels| held.concat(labels) }

      held.compact.map { |s| s.to_s.strip.upcase }.reject(&:empty?)
    end

    # [ choice name, labels ] for each feat choice resolved or in flight whose block carries `flag`.
    def self.flagged_choices(char, flag)
      in_flight = (char.pf2_to_assign || {})['feat_choices']
      names = recorded_choices(char).map(&:first) + (in_flight.is_a?(Hash) ? in_flight.keys : [])

      names.map(&:to_s).uniq { |n| n.downcase }.filter_map do |name|
        block = feat_choice_block_for(name) || class_choice_block_for(char, name)

        next unless block.is_a?(Hash) && block[flag]

        [ name, choice_labels_for(char, name) ]
      end
    end

    # The character's class's specialties: its orders, muses or bloodlines.
    def self.class_specialties(char)
      (Global.read_config('pf2e_specialty', char.pf2_base_info['charclass'].to_s) || {}).keys
    end

    # A choice's labels read as [ specialty, its own 1st-level option ], for a choice that picked
    # another bloodline and then that bloodline's choice.
    def self.specialty_and_option(char, labels)
      specialties = class_specialties(char)
      specialty = Array(labels).find { |label| specialties.any? { |s| s.casecmp?(label.to_s) } }

      return nil unless specialty

      info = Global.read_config('pf2e_specialty', char.pf2_base_info['charclass'].to_s, specialty) || {}
      options = ((info['choose'] || {})['options'] || {}).keys
      option = Array(labels).find { |label| options.any? { |o| o.casecmp?(label.to_s) } }

      [ specialty, option ]
    end

    # Bloodlines whose blood magic a choice shares (Crossblooded Evolution), with their option.
    def self.shared_bloodlines(char)
      flagged_choices(char, 'shares_blood_magic').filter_map { |_name, labels| specialty_and_option(char, labels) }
    end

    # class => [ spells ] a choice adds to the repertoire at the highest rank the class casts
    # (Greater Crossblooded Evolution).
    def self.top_rank_spells(char)
      spells = flagged_choices(char, 'known_at').flat_map { |_name, labels| labels }

      spells.empty? ? {} : { char.pf2_base_info['charclass'] => spells.uniq }
    end

    # class => [ spells ] a choice adds to the repertoire at their own rank, once the class casts at
    # it (Divine Access). The choice's first pick is a deity, and the rest are that deity's cleric
    # spells.
    def self.deity_choice_spells(char)
      spells = flagged_choices(char, 'deity_spells').flat_map do |_name, labels|
        deity = labels.find { |label| deity_named(label) }
        offered = deity ? deity_cleric_spells(deity).map(&:downcase) : []

        labels.select { |label| offered.include?(label.to_s.downcase) }
      end

      spells.empty? ? {} : { char.pf2_base_info['charclass'] => spells.uniq }
    end

    # The deity's name as config spells it, or nil.
    def self.deity_named(name)
      (Global.read_config('pf2e_deities') || {}).keys.find { |d| d.to_s.casecmp?(name.to_s) }
    end

    # A deity's cleric spells, by the names the spell files use. One that names no spell is left
    # out and logged, since offering it would record a pick nothing can cast.
    def self.deity_cleric_spells(deity)
      key = deity_named(deity)
      listed = key ? Array(Global.read_config('pf2e_deities', key, 'cleric_spells')) : []

      listed.filter_map do |name|
        found = Pf2emagic.get_spell_details(name)

        unless found.is_a?(Array)
          Global.logger.error "#{key}'s cleric spell '#{name}' is not a spell."
          next nil
        end

        found[0]
      end
    end

    # Deities who grant one of the domains of the character's mystery.
    def self.mystery_deities(char)
      base = char.pf2_base_info || {}
      mystery = Global.read_config('pf2e_specialty', base['charclass'].to_s, base['specialize'].to_s) || {}
      domains = Array(mystery['domains']).map(&:downcase)

      (Global.read_config('pf2e_deities') || {}).select do |_deity, info|
        Array((info || {})['domains']).any? { |domain| domains.include?(domain.to_s.downcase) }
      end.keys.sort
    end

    # The 1st-level feat of the character's class that lists a specialty as a prerequisite, or nil
    # when there is not exactly one.
    def self.specialty_first_feat(char, specialty)
      charclass = char.pf2_base_info['charclass']

      found = (Global.read_config('pf2e_feats') || {}).select do |_name, details|
        prereq = (details.is_a?(Hash) && details['prereq']) || {}

        prereq['level'].to_i == 1 && Array(details['assoc_charclass']).include?(charclass) &&
          Array(prereq['specialize']).any? { |s| s.to_s.casecmp?(specialty.to_s) }
      end

      Global.logger.error "#{charclass} #{specialty} has #{found.size} 1st-level feats; one was expected." unless found.size == 1

      found.size == 1 ? found.keys.first : nil
    end

    # Every focus spell the character knows, across all focus types, spells and cantrips
    # alike. Names only -- the type a focus spell is filed under is not what prereqs ask about.
    def self.held_focus_spells(char)
      magic = char.magic
      return [] unless magic

      lists = [ Pf2emagic::Entries.all_focus(magic) ]

      lists.flatten.compact.map { |s| s.to_s.strip }.reject(&:empty?)
    end

    # A more useful reason than "you do not meet the prerequisites", where one exists.
    # Returns nil when there is nothing better to say and the generic message should stand.
    def self.explain_feat_block(char, details)
      prereqs = details.is_a?(Hash) ? details['prereq'] : nil
      return nil unless prereqs.is_a?(Hash)

      return t('pf2e.needs_divine_font') if prereqs['divine_font'] && char.magic&.divine_font.blank?
      return t('pf2e.needs_caster') if prereqs['caster'] && !character_is_caster?(char)

      nil
    end

    def self.meets_prereqs?(char, prereqs, cl)
      msg = []

      prereqs.each_pair do |ptype, required|
        case ptype
        when "level"
          msg << "level" if prereqs['level'] > cl
        when "ability"
          # There can be more than one ability prereq, so required is passed as an array.
          required.each_with_index do |item, i|
            string = item.split("/")
            factor = string[0]
            minimum = string[1]

            char_score = Pf2eAbilities.get_score(char, factor)
            msg << "ability#{i}" if char_score < minimum.to_i
          end
        when "skill"
          Array(required).each_with_index do |entry, i|
            skill_name, minimum_prof = entry.to_s.split("/")

            skill_prof = DraftSheet.of(char).skill_prof(skill_name)
            char_prof = Pf2e.get_prof_bonus(char, skill_prof)
            min_prof = Pf2e.get_prof_bonus(char, minimum_prof)

            msg << "skill#{i}" if char_prof < min_prof
          end
        when "tradition_skill"
          # A skill that follows whichever tradition a source casts from - Expert Sorcerer
          # Spellcasting asks for master in the skill of the bloodline's tradition. Entries are
          # "source/proficiency"; a source casting from no tradition fails.
          Array(required).each_with_index do |entry, i|
            source, minimum_prof = entry.to_s.split("/")
            skill_name = tradition_skill_for(char, source)

            if skill_name.nil?
              msg << "tradition_skill#{i}"
              next
            end

            skill_prof = DraftSheet.of(char).skill_prof(skill_name)

            msg << "tradition_skill#{i}" if Pf2e.get_prof_bonus(char, skill_prof) < Pf2e.get_prof_bonus(char, minimum_prof)
          end
        when "specialize"
          held = held_specialties(char)

          wanted = Array(required).compact.map { |r| r.to_s.strip }.reject(&:empty?)
          banned, allowed = wanted.partition { |r| r.start_with?('!') }

          msg << ptype if banned.any? { |r| held.include?(r.delete('!').upcase) }
          msg << ptype if allowed.any? && allowed.none? { |r| held.include?(r.upcase) }
        when "focus_spell"
          # Focus spells are filed under whatever granted them -- devotion, revelation, qi --
          # and the prereq names only the spell, so the type is flattened away. Cantrips are
          # stored separately from spells but a prereq naming one should still match.
          held = held_focus_spells(char)

          wanted = Array(required).compact.map { |s| s.to_s.strip }.reject(&:empty?)

          msg << "focus_spell" if wanted.any? && wanted.none? { |s| held.any? { |h| h.casecmp?(s) } }
        when "divine_font"
          font = char.magic&.divine_font

          if font.blank?
            msg << "divine_font"
          else
            msg << "divine_font" unless Array(required).any? { |f| f.to_s.casecmp?(font.to_s) }
          end
        when "has_focus_pool"
          msg << "focus_pool" if Pf2emagic.focus_pool_max(char.magic).zero?
        when "feature"
          msg << "feature" unless Array(required).all? { |name| holds_feature?(char, name) }
        when "sanctification"
          held = char.pf2_faith['sanctification']

          if char.advancing
            pending = (char.pf2_advancement || {})['archetype_sanctification']
            held = pending unless pending.blank?
          end

          msg << "sanctification" unless Array(required).any? { |s| s.to_s.casecmp?(held.to_s) }
        when "stances"
          msg << "stances" if held_stance_count(char) < required.to_i
        when "repertoire_spell"
          known = DraftSheet.of(char).repertoire.values.flat_map { |by_rank| (by_rank || {}).values.flatten }

          msg << "repertoire_spell" unless Array(required).all? { |s| known.any? { |k| k.to_s.casecmp?(s.to_s) } }
        when "familiar"
          msg << "familiar" unless has_familiar?(char)
        when "feat"
          feats = DraftSheet.of(char).feat_names
          req = required.map { |word| word.upcase }

          msg << "feat" unless req.all? { |f| feats.include? f }
        when "caster"
          # "ability to cast spells" / "ability to cast cantrips". Both are the same test
          # here -- casting through a spellcasting class -- with the value ('spells' or
          # 'cantrips') kept only for readability in config.
          msg << "caster" unless character_is_caster?(char)
        when "heritage"
          held = char.pf2_base_info["heritage"].to_s.strip.upcase
          wanted = required.to_s.strip

          if wanted.start_with?('!')
            msg << "heritage" if wanted.delete_prefix('!').strip.upcase == held
          else
            msg << "heritage" if wanted.upcase != held
          end
        when "special"
          # Takes one special or a list, and a list means all of them, the same way the skill
          # and feat prereqs above do.
          held = Array(char.pf2_special).map { |s| s.to_s.strip.upcase }
          wanted = Array(required).compact.map { |s| s.to_s.strip.upcase }.reject(&:empty?)

          msg << "special" unless wanted.all? { |s| held.include?(s) }
        when "tradition"
          magic = char.magic

          msg << "tradition" && next unless magic

          traditions = magic.tradition

          msg << "tradition" unless traditions.include? required
        when "innate_tradition"
          # Useful for when a feat has a prereq asking for any innate spell tradition, like Quelynos Adept.
          magic = char.magic

          msg << "innate_tradition" && next unless magic

          required_traditions = Array(required).map { |t| t.to_s.downcase.strip }.reject(&:empty?)
          held = Pf2emagic::Entries.innate_traditions(magic)

          has_required_innate_tradition = held.any? { |tradition| required_traditions.include?(tradition) }

          msg << "innate_tradition" unless has_required_innate_tradition
        when "combat_stats"
          # "Perception/expert", "Reflex/expert", or "Weapon/expert" for expert in any kind of
          # weapon or unarmed attack. A factor nobody reads fails, the way an unknown key does.
          factor, minimum = required.to_s.split("/")
          held = combat_stat_ranks(char, factor)

          if held.nil?
            Global.logger.error "Unhandled combat_stats prereq '#{required}'."
            msg << "combat_stats"
          else
            min_rank = prof_rank(minimum).to_i

            msg << "combat_stats" unless held.any? { |prof| prof_rank(prof).to_i >= min_rank }
          end
        when "max_class_hp"
          # Resiliency's "a class granting no more Hit Points per level than 8 + your Constitution
          # modifier": the base class's Hit Points per level, before Constitution.
          class_hp = Global.read_config('pf2e_class', char.pf2_base_info['charclass'], 'HP')

          msg << "max_class_hp" if class_hp.nil? || class_hp.to_i > required.to_i
        when "oralign"
          alignment = char.pf2_faith["alignment"]
          
          msg << "alignment" unless required.include? alignment
        when "ordeity"
          deity = char.pf2_faith["deity"]

          if char.advancing
            pending = (char.pf2_advancement || {})['archetype_deity']
            deity = pending unless pending.blank?
          end

          if deity.blank?
            msg << "deity"
          else
            msg << "deity" unless Array(required).any? { |d| d.to_s.casecmp?(deity.to_s) }
          end
        when "orfeat"
          feats = DraftSheet.of(char).feat_names
          req = required.map { |word| word.upcase }

          msg << "feat" unless req.any? { |f| feats.include? f }
        when "orheritage"
          heritage = char.pf2_base_info["heritage"]

          msg << "heritage" unless required.include? heritage
        when "orskill"
          check = []
          required.each do |s|

          string = s.split("/")
          factor = string[0]
          minimum = string[1]

          skill_prof = DraftSheet.of(char).skill_prof(factor)
          char_prof = Pf2e.get_prof_bonus(char, skill_prof)
          min_prof = Pf2e.get_prof_bonus(char, minimum)

          check << char_prof - min_prof
          end

          msg << "orskill" unless check.any? { |i| i>= 0 }
        when "anyskills"
          # "At least N skills at rank X or better", for feats whose prereq names no
          # particular skill - Skill Mastery's "trained in at least one skill and expert in
          # at least one skill". Entries are "rank/count" strings.
          progression = Global.read_config('pf2e', 'prof_progression') || []

          skill_names = char.skills.map { |s| s.name }

          if char.advancing
            advancement = char.pf2_advancement || {}
            pending = Array(advancement['raise skill']) + Array(advancement['raise skill choice'])
            pending = pending.reject { |s| s.to_s.strip.empty? || Pf2e.open_skill_token?(s) }

            skill_names = (skill_names + pending).uniq { |s| s.to_s.downcase }
          end

          sheet = DraftSheet.of(char)

          char_ranks = skill_names.map { |s| progression.index(sheet.skill_prof(s)) || 0 }

          Array(required).each_with_index do |entry, i|
            rank, count = entry.to_s.split("/")
            min_rank = progression.index(rank.to_s.strip.downcase) || 0
            needed = count.nil? ? 1 : count.to_i

            msg << "anyskills#{i}" if char_ranks.count { |r| r >= min_rank } < needed
          end
        else
          msg << "missing_prereq_check #{ptype}"
        end
      end

      return true if msg.empty?
      return false
    end

    # The proficiencies a combat_stats prereq factor reads, or nil for a factor it does not know.
    # Several for Weapon, which any weapon category, group or unarmed attack satisfies.
    def self.combat_stat_ranks(char, factor)
      combat = char.combat

      case factor.to_s.downcase
      when 'perception'
        [ combat&.perception ]
      when 'fortitude', 'reflex', 'will'
        [ (combat&.saves || {})[factor.to_s.downcase] ]
      when 'weapon'
        (combat&.weapon_prof || {}).values + (combat&.weapon_group_prof || {}).values
      end
    end

    # Whether the character holds a class or archetype feature. A name matches a feature, the option
    # recorded in "Feature (Option)" - a Champion's Blessed Armament - or a feat choice resolved to
    # it, which is how the Champion archetype's Devout Blessing records the same blessing.
    def self.holds_feature?(char, name)
      wanted = name.to_s.strip

      held = DraftSheet.of(char).feature_names.any? do |feature|
        option = feature[/\(([^()]+)\)\z/, 1]

        feature.casecmp?(wanted) || option.to_s.strip.casecmp?(wanted)
      end

      held || choice_labels(char).any? { |label| label.to_s.casecmp?(wanted) }
    end

    # Every label a feat choice has resolved to, counting the ones this level has picked.
    def self.choice_labels(char)
      in_flight = (char.pf2_to_assign || {})['feat_choices']

      recorded_choices(char).map { |_name, label, _level| label } +
        (in_flight.is_a?(Hash) ? in_flight.values.flatten : [])
    end

    # The feats with the stance trait the character holds, counting this level's.
    def self.held_stance_count(char)
      held_feat_details(char).count { |_name, details| Array(details['traits']).any? { |t| t.to_s.casecmp?('stance') } }
    end

    # A familiar, from a feat flagged as giving one or from the Witch's Familiar class feature.
    def self.has_familiar?(char)
      held_feat_details(char).any? { |_name, details| details['familiar'] == true } || holds_feature?(char, 'Familiar')
    end

    # [ name, details ] for each feat the character holds, counting this level's.
    def self.held_feat_details(char)
      feats = Global.read_config('pf2e_feats') || {}
      by_upcase = feats.keys.each_with_object({}) { |key, out| out[key.to_s.upcase] = key }

      DraftSheet.of(char).feat_names.filter_map do |name|
        key = by_upcase[name.to_s.upcase]

        key && feats[key].is_a?(Hash) ? [ key, feats[key] ] : nil
      end
    end

    # The skill that goes with the tradition a source casts from, counting one this level grants, or
    # nil when the source casts from none.
    def self.tradition_skill_for(char, source)
      found = DraftSheet.of(char).traditions.find { |held, _| held.to_s.casecmp?(source.to_s) }
      tradition = found && Array(found[1]).first

      return nil if tradition.blank?

      skills = Global.read_config('pf2e_magic', 'tradition_skills') || {}
      key = skills.keys.find { |t| t.to_s.casecmp?(tradition.to_s) }

      key && skills[key]
    end

    def self.has_feat?(char, feat)
      DraftSheet.of(char).feat_names.include?(feat.upcase)
    end

    # How many times this feat may be taken in total. Infinity when uncapped.
    def self.feat_repeat_max(details)
      return 1 unless details.is_a?(Hash)

      spec = details['repeatable']

      return 1 if spec.nil? || spec == false
      return Float::INFINITY if spec == true
      return spec.to_i if spec.is_a?(Integer)
      return spec['max'] ? spec['max'].to_i : Float::INFINITY if spec.is_a?(Hash)

      1
    end

    def self.feat_repeatable?(details)
      feat_repeat_max(details) > 1
    end

    # Minimum character level for the nth taking.
    def self.feat_repeat_level(details, nth)
      return nil unless details.is_a?(Hash)

      spec = details['repeatable']
      return nil unless spec.is_a?(Hash)

      levels = Array(spec['levels'])
      return nil if levels.empty?

      levels[nth - 1]
    end

    # How many times the character already holds this feat, counting an open draft - a feat taken
    # earlier in the same build is held as far as a repeat limit is concerned.
    def self.feat_taken_count(char, feat_name)
      DraftSheet.of(char).feats_by_bucket.values.flatten.count { |f| f.to_s.casecmp?(feat_name.to_s) }
    end

    # Whether another instance may be taken. Returns nil when allowed, or a failure message.
    def self.feat_repeat_block(char, feat_name, details, taken = nil, level = nil)
      taken ||= feat_taken_count(char, feat_name)
      return nil if taken.zero?

      max = feat_repeat_max(details)

      return t('pf2e.already_has', :item => 'feat') if max <= 1
      return t('pf2e.feat_repeat_maxed', :feat => feat_name, :max => max.to_i) if taken >= max

      required = feat_repeat_level(details, taken + 1)
      cl = level || char.pf2_level

      if required && cl < required.to_i
        return t('pf2e.feat_repeat_too_low', :feat => feat_name, :level => required)
      end

      nil
    end

    # feat_name => times held, upcased, for loops that would otherwise re-flatten per feat.
    def self.feat_tally(char)
      tally = Hash.new(0)
      DraftSheet.of(char).feats_by_bucket.values.flatten.each { |f| tally[f.to_s.upcase] += 1 }

      tally
    end

    # How many picks one taking of a feat's choice resolves: 1 for an ordinary choice, more
    # when it chains further picks with then_choose (Adapted Cantrip: a tradition, then a
    # cantrip). Feats with no choice count as 1.
    def self.choice_sequence_depth(feat_name)
      block = feat_choice_block_for(feat_name)
      depth = 0

      while block.is_a?(Hash)
        depth += 1
        block = block['then_choose']
      end

      [ depth, 1 ].max
    end

    # Expands a stored feat list into display names, one entry per instance, with each
    # instance's recorded choice in parentheses.
    #
    # A repeatable feat is stored once per taking, so Assurance taken for Nature and then
    # Athletics reads as "Assurance (Nature), Assurance (Athletics)" rather than collapsing
    # to a single entry. A then_choose feat records several picks for one taking, so those
    # are shown together, slash-joined: "Adapted Cantrip (Primal/Electric Arc)".
    def self.feat_display_list(char, feat_names)
      names = Array(feat_names).compact.map(&:to_s)
      labels = []

      names.uniq.each do |name|
        count = names.count { |n| n.casecmp?(name) }
        depth = choice_sequence_depth(name)

        # choice_labels_for is flat; a then_choose feat contributes `depth` labels per
        # taking, so slice it back into one run per instance.
        runs = choice_labels_for(char, name).each_slice(depth).first(count)

        runs.each { |run| labels << "#{name} (#{run.join('/')})" }

        remaining = count - runs.size
        next if remaining.zero?

        labels << (remaining > 1 ? "#{name} (x#{remaining})" : name)
      end

      labels
    end

    # Full detail blocks for a list of feats.
    def self.generate_list_details(featlist, char = nil)

      feat_list=featlist

      @details = Global.read_config('pf2e_feats').select { |k,v| feat_list.include? k }

      list = []
      @details.each_pair do |feat, details|
        list << format_feat(feat_detail_heading(char, feat), details)
      end

      list.sort

    end

    def self.feat_detail_heading(char, feat)
      return feat unless char

      choices = choice_labels_for(char, feat)
      return "#{feat} (#{choices.join(', ')})" unless choices.empty?

      count = feat_taken_count(char, feat)
      count > 1 ? "#{feat} (x#{count})" : feat
    end

    # Every feat of a type the character could take.
    #
    # The sheet is read once for the whole sweep - see Pf2e::SheetReads. The eligibility check
    # looks a skill or an attribute up per prerequisite, which against the whole catalogue is
    # hundreds of reads of collections that do not change while the sweep runs.
    def self.get_feat_options(char, type)
      ftype = type.capitalize
      feats = Global.read_config('pf2e_feats') || {}
      list = []

      # Tallied once rather than rebuilt inside the loop by has_feat?. A repeatable feat
      # stays in the list until it is actually maxed out.
      tally = feat_tally(char)

      Pf2e::SheetReads.holding(char) do
        feats.each_pair do |name, details|
          # Cheap filters first, so most candidates never reach the eligibility check.
          next unless Array(details['feat_type']).include? ftype
          next if feat_repeat_block(char, name, details, tally[name.to_s.upcase])

          list << name if can_take_feat_details?(char, name, details)
        end
      end

      list.sort
    end

    def self.format_feat(feat, details)

      return t('pf2e.feat_details_missing', :name => feat.upcase) if !details

      fmt_name = "%x172#{feat}%xn"
      feat_type = "%x229Feat Type:%xn #{details['feat_type'].sort.join(", ")}"

      # Depending on feat type, this may be different keys with different formats.

      if details.has_key? 'assoc_charclass'
        associated = "%x229Associated Classes:%xn #{details['assoc_charclass'].sort.join(", ")}"
      elsif details.has_key? 'assoc_archetype'
        associated = "%x229Associated Archetypes:%xn #{details['assoc_archetype'].sort.join(", ")}"
      elsif details.has_key? 'assoc_ancestry'
        associated = "%x229Associated Ancestries:%xn #{details['assoc_ancestry'].sort.join(", ")}"
      elsif details.has_key? 'assoc_skill'
        skills = Array(details['assoc_skill']).compact
        associated = "%x229Associated Skills:%xn #{skills.sort.join(", ")}"
      else
        associated = "%x229Associated With:%xn Any"
      end

      if details.has_key?('traits') && !details['traits'].empty?
        traits = "%x229Traits:%xn #{details['traits'].sort.map(&:capitalize).join(", ")}"
      else
        traits = "%x229Traits:%xn None"
      end

      # Prerequisites needs its own level of formatting.

      prereq_list = []

      if details['prereq'].is_a?(Hash)
        details['prereq'].each_pair do |k,v|
          key_display = k.capitalize

          # Set by keys whose plural is not the label plus an "s".
          skip_plural = false

          if k == 'orfeat'
            key_display = 'One of the following feat'
          elsif k == 'orskill'
            key_display = 'One of the following skill'
          elsif k == 'oralign'
            key_display = 'One of the following alignment'
          elsif k == 'ordeity'
            key_display = Array(v).length > 1 ? 'One of the following deities' : 'One of the following deity'
            skip_plural = true
          elsif k == 'innate_tradition'
            key_display = 'Innate spell tradition'
          elsif k == 'caster'
            key_display = 'Ability to cast'
          elsif k == 'max_class_hp'
            key_display = 'Class Hit Points'
            v = "no more than #{v} + your Constitution modifier per level"
          elsif k == 'tradition_skill'
            # Stored as "source/proficiency", and the skill depends on the character.
            key_display = 'Skill requirement'

            v = Array(v).map do |entry|
              source, prof = entry.to_s.split("/")

              "#{prof} in the skill for your #{source}'s tradition"
            end
          elsif k == 'anyskills'
            # Stored as "rank/count", which is not something to show a player as-is.
            key_display = 'Skill requirement'

            v = Array(v).map do |entry|
              rank, count = entry.to_s.split("/")
              num = count.nil? ? 1 : count.to_i

              "#{num} skill#{num == 1 ? '' : 's'} at #{rank} or better"
            end
          end

          if v.is_a?(Array)
            key_display = key_display + "s" if v.length > 1 && !skip_plural
            # Array: key(s): followed by bulleted items
            prereq_list << "%r%t%xh%xw#{key_display}:%xn"
            v.each do |item|
              prereq_list << "%r%t  - #{item}"
            end
          else
            # Single value: key: value on same line
            prereq_list << "%r%t%xh%xw#{key_display}:%xn #{v}"
          end
        end
      end

      prereqs = "%x229Prerequisites:%xn" + prereq_list.join()

      desc = "%x229Description:%xn #{details['shortdesc']}"

      "#{fmt_name}%r%r#{feat_type}%r#{associated}%r#{traits}%r#{prereqs}%r#{desc}"
    end

    # A feat type to the line that says one of its slots is still open.
    UNASSIGNED_FEAT = {
      'charclass' => 'pf2e.unassigned_class_feat',
      'general' => 'pf2e.unassigned_general_feat',
      'ancestry' => 'pf2e.unassigned_ancestry_feat',
      'skill' => 'pf2e.unassigned_skill_feat'
    }.freeze

    def self.feat_messages(char)
      msgs = []
      to_assign = char.pf2_to_assign
      open_slots = to_assign['feats'] || {}

      UNASSIGNED_FEAT.each_pair do |type, key|
        msgs << t(key) if Array(open_slots[type]).include?('open')
      end

      pending_feat_choices(char).each_pair do |name, slots|
        next unless Array(slots).include?('open')

        msgs << t('pf2e.unassigned_feat_choice', :choice => name)
      end

      return nil if msgs.empty?
      return msgs
    end

    OPEN_SKILL_VALUES = %w(open choice)

    # What is still unchosen among a character's innate spell grants, one label each.
    #
    # Reads through Pf2emagic::Entries: `innate_spells` is a list of grants, not a map keyed by
    # spell name, because two sources can grant the same spell at different ranks and traditions.
    def self.open_innate_labels(magic)
      return [] unless magic

      Pf2emagic::Entries.pending_innate(magic).map do |grant|
        rank = grant['level'].to_s.downcase
        cantrip = rank == 'cantrip' || rank.to_i.zero?

        tradition = Array(grant['tradition']).first.to_s
        tradition_label = tradition.empty? ? 'unknown tradition' : tradition

        if cantrip
          "innate cantrip (#{tradition_label})"
        else
          "innate #{Pf2emagic.ordinal_level(rank)}-rank spell (#{tradition_label})"
        end
      end
    end

    # What a feat's `grants` block can hand over, one row per key.
    #
    #   timing - 'assign' for a pick the player resolves straight away, 'advance' for what is
    #            applied when a level commits. `assess_feat_grants` splits a block on this, so the
    #            two readings of the same vocabulary cannot drift.
    #   apply  - takes the context below and returns [ locale key, args ] pairs.
    #
    # The context carries the character, the value from config, the class the grant is attributed
    # to, and the client, which the magic helpers still render their own messages through.
    #
    # A key with no row is logged rather than shown: config naming something this does not handle
    # is a data error for staff to see in the log, not a sentence for the player.
    GRANTS = {
      'magic_stats' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx| Pf2e.grant_magic_stats(ctx) }
      },
      'assign' => {
        'timing' => 'assign',
        'apply' => lambda { |ctx|
          to_assign = ctx[:char].pf2_to_assign

          messages = Array(ctx[:value]).map do |item|
            to_assign[item] = Array(to_assign[item]) + [ 'open' ]

            [ 'pf2e.feat_grants_addl', { :element => item } ]
          end

          ctx[:char].update(:pf2_to_assign => to_assign)

          messages
        }
      },
      'feat' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx| Pf2e.grant_feats(ctx) }
      },
      'grant_choice' => {
        'timing' => 'assign',
        'apply' => lambda { |ctx|
          to_assign = ctx[:char].pf2_to_assign

          Array(ctx[:value]).compact.each { |name| Pf2e.open_feat_choice(to_assign, name.to_s) }

          ctx[:char].update(:pf2_to_assign => to_assign)

          []
        }
      },
      # The same choice, opened only if the character has neither an open one nor a resolved one:
      # a feat granted twice does not ask twice.
      'grant_choice_once' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx|
          to_assign = ctx[:char].pf2_to_assign

          Array(ctx[:value]).compact.each do |name|
            key = name.to_s

            next if Array((to_assign['feat choice'] || {})[key]).include?('open')
            next if Pf2e.choice_labels_for(ctx[:char], key).any?

            Pf2e.open_feat_choice(to_assign, key)
          end

          ctx[:char].update(:pf2_to_assign => to_assign)

          []
        }
      },
      'reagents' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx|
          Pf2e.update_reagents(ctx[:char], ctx[:value])

          [ [ 'pf2e.feat_grants_reagents', {} ] ]
        }
      },
      'attack' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx|
          combat = Pf2eCombat.get_create_combat_obj(ctx[:char])
          attacks = combat.unarmed_attacks

          ctx[:value].each_pair { |attack, info| attacks[attack] = info }

          combat.update(:unarmed_attacks => attacks)

          [ [ 'pf2e.feat_grants_attack', {} ] ]
        }
      },
      'skill' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx| Pf2e.grant_skills(ctx) }
      },
      'raise_skill' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx| Pf2e.grant_raises(ctx) }
      },
      'combat_stats' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx|
          Pf2eCombat.update_combat_stats(ctx[:char], ctx[:value])

          [ [ 'pf2e.feat_grants_combat_stats', {} ] ]
        }
      },
      # A sense the character keeps: Eyes of Night's darkvision. Written to pf2_special, which the
      # chargen and level-up syncs record on the ledger, so a rollback takes it back.
      'special' => {
        'timing' => 'advance',
        'apply' => lambda { |ctx|
          gained = Array(ctx[:value]).map(&:to_s).reject(&:empty?)

          ctx[:char].update(:pf2_special => Pf2e.with_senses(ctx[:char].pf2_special, gained))

          gained.map { |sense| [ 'pf2e.feat_grants_special', { :special => sense } ] }
        }
      }
    }.freeze

    # A special list with senses added. Darkvision replaces low-light vision, as it does when a
    # heritage grants it at chargen. Names are compared without case, because the data spells them
    # both ways.
    def self.with_senses(held, gained)
      list = Array(held).dup

      gained.each do |sense|
        list << sense unless list.any? { |s| s.to_s.casecmp?(sense) }
      end

      if gained.any? { |s| s.casecmp?('Darkvision') }
        list.reject! { |s| s.to_s.casecmp?('Low-Light Vision') }
      end

      list
    end

    def self.grant_keys
      GRANTS.keys
    end

    # Applies a feat's grants block. Returns rendered messages, because every caller emits them
    # straight to a client.
    #
    # A row answers with [ locale key, args ] pairs, or with a string where the helper it delegates
    # to has already rendered its own.
    def self.do_feat_grants(char, info, charclass, client)
      (info || {}).flat_map do |key, value|
        row = GRANTS[key.to_s]

        unless row
          Global.logger.error "A feat grants '#{key}', which is not one of #{grant_keys.join(', ')}."
          next []
        end

        ctx = { :char => char, :value => value, :charclass => charclass, :client => client }

        Array(row['apply'].call(ctx)).map do |message|
          next message if message.is_a?(::String)

          locale_key, args = message

          t(locale_key, **(args || {}))
        end
      end
    end

    # Which of a grants block is resolved now and which waits for the level to commit.
    def self.assess_feat_grants(info)
      split = { 'assign' => {}, 'advance' => {} }

      (info || {}).each_pair do |key, value|
        timing = (GRANTS[key.to_s] || {})['timing'] || 'advance'

        split[timing][key] = value
      end

      split
    end

    # ------------------------------------------------------------------------------
    # The longer grants, each its own function so the table stays readable
    # ------------------------------------------------------------------------------

    # Spellcasting a feat hands over. What it opens for the player to choose is counted and named,
    # because "you have spells to choose" without saying how many or at what rank is not actionable.
    def self.grant_magic_stats(ctx)
      char = ctx[:char]
      update = PF2Magic.update_magic(char, ctx[:charclass], ctx[:value], ctx[:client])

      # update_magic renders its own complaint, so it is passed through as it is.
      return [ update ] if update.is_a?(::String)

      messages = []
      details = magic_open_details(char, update)

      if details.any?
        review_cmd = char.advancing ? 'advance/review' : 'cg/review'
        messages << [ 'pf2e.feat_grants_magic_open',
                      { :review_cmd => review_cmd, :details => Pf2emagic.join_with_and(details) } ]
      else
        messages << [ 'pf2e.feat_grants_magic', {} ]
      end

      # update_magic answers with what belongs in pf2_to_assign, so it goes there.
      if update.is_a?(::Hash) && !update.empty?
        messages << [ 'pf2e.feat_grants_addl', { :element => 'magic' } ]
        char.update(:pf2_to_assign => char.pf2_to_assign.merge(update))
      end

      messages
    end

    # "two 1st-rank spells to add to your spellbook", one phrase per rank and list, with the innate
    # spells still to assign first - which is the order a player reads them in on the review screen.
    def self.magic_open_details(char, update)
      innate = open_innate_labels(char.magic).tally.map do |label, count|
        t('pf2e.feat_grants_magic_innate', :count => count,
          :label => Pf2emagic.pluralize_label(label, count))
      end

      lists = update.is_a?(::Hash) ? update : {}

      innate + [ 'spellbook', 'repertoire' ].flat_map do |source|
        open_counts_by_rank(lists[source]).map do |rank, count|
          label = Pf2emagic.pluralize_label(rank_label(rank), count)

          t("pf2e.feat_grants_magic_#{source}", :count => count, :label => label)
        end
      end
    end

    # rank => how many picks at it are still open, for either shape update_magic answers with.
    def self.open_counts_by_rank(value)
      return {} unless value.is_a?(Hash) || value.is_a?(Array)

      pairs = value.is_a?(Hash) ? value : { '1' => value }

      pairs.each_with_object({}) do |(rank, list), counts|
        open = Array(list).count { |entry| entry.to_s.casecmp?('open') }

        counts[rank.to_s.downcase] = open if open.positive?
      end
    end

    def self.rank_label(rank)
      return 'cantrip' if rank == 'cantrip' || rank == '0'

      "#{Pf2emagic.ordinal_level(rank)}-rank spell"
    end

    # Feats a feat hands over. Each is bound by the same eligibility and repeat rules as one the
    # player picks, which is also what ends a chain that closes on itself. A grant that waives the
    # prerequisites is still bound by the rest: the feat's class or ancestry, and the repeat limit.
    def self.grant_feats(ctx)
      char = ctx[:char]

      Array(ctx[:value]).flat_map do |entry|
        parsed = granted_feat_entry(entry)

        next [] unless parsed

        fname, label, source, filter, waived = parsed
        found = get_feat_details(fname)

        if found.is_a?(String)
          Global.logger.error "A feat grant names '#{fname}', which did not resolve (#{found})."
          next []
        end

        checked = waived ? found[1].merge('prereq' => nil) : found[1]

        unless can_take_feat_details?(char, found[0], checked)
          Global.logger.warn "#{char.name} was granted '#{found[0]}' but does not qualify for it."
          next []
        end

        repeat = feat_repeat_block(char, found[0], found[1])

        if repeat
          Global.logger.warn "#{char.name} was granted '#{found[0]}' and may not hold it again: #{repeat}"
          next []
        end

        label = granted_choice_label(char, source) if source.present?

        # Both of these render their own messages, so they are passed through as they are.
        add_granted_feat(char, found[0], found[1], ctx[:charclass], ctx[:client]) +
          resolve_granted_choice(char, found[0], found[1], label, ctx[:client], filter)
      end
    end

    # A skill a feat grants. One the character is already trained in becomes a free skill to assign
    # instead, which is the rule PF2e states for a duplicate.
    def self.grant_skills(ctx)
      char = ctx[:char]

      Array(ctx[:value]).flat_map do |skill|
        open_choice = OPEN_SKILL_VALUES.include?(skill.to_s.downcase)
        held = open_choice || Pf2eSkills.get_skill_prof(char, skill) != 'untrained'

        next [ grant_one_skill(char, skill) ] unless held
        next [ [ 'pf2e.feat_needs_free_skill', { :name => char.name } ] ] unless char.advancing || !char.is_approved?

        to_assign = char.pf2_to_assign
        to_assign['open skills'] = Array(to_assign['open skills']) + [ 'open' ]
        char.update(:pf2_to_assign => to_assign)
        char.update(:pf2_skills_locked => false)

        [ [ open_choice ? 'pf2e.feat_grants_free_skill' : 'pf2e.feat_grants_duplicate_skill', {} ] ]
      end
    end

    def self.grant_one_skill(char, skill)
      Pf2eSkills.create_skill_for_char(skill, char) unless Pf2eSkills.find_skill(skill, char)
      Pf2eSkills.update_skill_for_char(skill, char, 'trained')

      [ 'pf2e.feat_grants_skill', { :skill => skill } ]
    end

    # A skill increase a feat grants, which moves one skill up a rank.
    def self.grant_raises(ctx)
      char = ctx[:char]

      Array(ctx[:value]).compact.flat_map do |name|
        next [] if name.to_s.strip.empty?

        Pf2eSkills.create_skill_for_char(name, char) unless Pf2eSkills.find_skill(name, char)

        skill = Pf2eSkills.find_skill(name, char)

        next [] unless skill

        raised = Pf2eSkills.get_next_prof(char, name)

        next [] if raised.blank? || raised.to_s.casecmp?(skill.prof_level.to_s)

        skill.update(:prof_level => raised)

        [ [ 'pf2e.feat_grants_raise', { :skill => name, :prof => raised } ] ]
      end
    end

    CASTER_TYPE_STAT_KEYS = %w(prepared spontaneous)

    def self.resolve_caster_type_stats(char, magic_stats)
      return magic_stats unless magic_stats.is_a?(Hash)
      return magic_stats unless magic_stats.keys.any? { |k| CASTER_TYPE_STAT_KEYS.include?(k.to_s.downcase) }

      caster_type = Pf2emagic.get_caster_type(char.pf2_base_info['charclass'])

      unconditional = magic_stats.reject { |k, _v| CASTER_TYPE_STAT_KEYS.include?(k.to_s.downcase) }
      matched = magic_stats.find { |k, _v| k.to_s.casecmp?(caster_type.to_s) }

      matched && matched[1].is_a?(Hash) ? unconditional.merge(matched[1]) : unconditional
    end

    def self.do_feat_magic_stats(char, feat_details, charclass, client)
      # Feats keep their magic in a top-level magic_stats block instead of under 'grants', so route it
      # through the same handler the 'grants' path uses. Returns the messages for the caller to emit.
      return [] if !feat_details.is_a?(Hash)

      magic_stats = feat_details['magic_stats']

      return [] if !magic_stats.is_a?(Hash) || magic_stats.empty?
      return [] if !AresMUSH.const_defined?("Pf2emagic")

      magic_stats = resolve_caster_type_stats(char, magic_stats)

      return [] if magic_stats.empty?

      do_feat_grants(char, { 'magic_stats' => magic_stats }, charclass, client)
    end

    def self.apply_init_magic_feat(char, feat_name, feat_details, client)
      return unless feat_details && feat_details['init_magic']

      # The flag grants the spell that has the feat's own name.
      spell_result = Pf2emagic.get_spell_details(feat_name)

      if spell_result.is_a?(String)
        Global.logger.error "Feat '#{feat_name}' carries init_magic, but no single spell has its name."
        return
      end

      spell_name, _details = spell_result
      focus_type_by_source = Global.read_config('pf2e_magic', 'focus_type_by_source')
      focus_type = focus_type_by_source[char.pf2_base_info['charclass']] || 'devotion'

      key = Pf2emagic.focus_cantrip?(spell_name) ? 'focus_cantrip' : 'focus_spell'
      spell_info = { key => { focus_type => [ spell_name ] } }

      PF2Magic.update_magic(char, char.pf2_base_info['charclass'], spell_info, client)
    end

    def self.feat_choice_def(feat_details)
      return nil unless feat_details.is_a?(Hash)

      block = feat_details['feat_choice']
      return nil unless block.is_a?(Hash)

      block
    end

    def self.feat_has_choice?(feat_details)
      !feat_choice_def(feat_details).nil?
    end

    # Pulls the name => block map off a class, subclass, or specialty level entry.
    def self.level_feat_choices(info)
      return {} unless info.is_a?(Hash)

      block = info['feat_choice']
      return {} unless block.is_a?(Hash)

      block.select { |_name, definition| definition.is_a?(Hash) }
    end

    def self.choice_summary(block)
      return 'eligible option' unless block.is_a?(Hash)

      (block['summary'] || 'eligible option').to_s
    end

    def self.choice_options(char, choice_name, block)
      return [] unless block.is_a?(Hash)

      options = if block['options'].is_a?(Hash)
        block['options'].keys.select { |label| choice_option_allowed?(char, block['options'][label]) }.sort
      elsif block['from_feats'].is_a?(Hash)
        choice_feat_pool(char, resolve_prior_steps(char, choice_name, block['from_feats']))
      elsif block['from_skills'].is_a?(Hash)
        choice_skill_pool(char, block['from_skills'])
      elsif block['from_weapons'].is_a?(Hash)
        choice_weapon_pool(char, block['from_weapons'])
      elsif block['from_weapon_groups'].is_a?(Hash)
        choice_weapon_group_pool(char, block['from_weapon_groups'])
      elsif block['from_spells'].is_a?(Hash)
        choice_spell_pool(char, block['from_spells'], choice_name)
      elsif block.key?('from_lores')
        choice_lore_pool(char, block['from_lores'])
      elsif block['from']
        choice_dynamic_options(char, block['from'], block, choice_name)
      else
        []
      end

      options = narrow_choice_options(char, choice_name, options)

      return options if block['allow_duplicates']

      taken = choice_labels_for(char, choice_name)
      return options if taken.empty?

      options.reject { |option| taken.any? { |t| t.to_s.casecmp?(option.to_s) } }
    end

    PRIOR_STEPS = 'from_prior_steps'.freeze

    # A feat pool's `assoc_skill: from_prior_steps`, read as the skills picked in this choice's
    # earlier steps - the ones still sitting in its open slot, so a later taking of a repeatable feat
    # asks about its own picks and not the last one's.
    def self.resolve_prior_steps(char, choice_name, filter)
      return filter unless filter['assoc_skill'].to_s == PRIOR_STEPS

      slots = (char.pf2_to_assign || {})['feat choice'] || {}
      key = slots.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      picked = Array(key && slots[key]).reject { |slot| slot.to_s.casecmp?('open') }

      filter.merge('assoc_skill' => picked)
    end

    def self.match_choice_option(char, choice_name, block, label)
      return nil if label.blank?

      choice_options(char, choice_name, block).find { |option| option.to_s.casecmp?(label.to_s) }
    end

    def self.choice_option_allowed?(char, option_info)
      return true unless option_info.is_a?(Hash)

      prereq = option_info['prereq']
      return true unless prereq

      cl = char.pf2_level
      cl = cl + 1 if char.advancing

      meets_prereqs?(char, prereq, cl)
    end

    def self.choice_grants_feat?(block)
      block.is_a?(Hash) && block['from_feats'].is_a?(Hash)
    end

    # The option hash for a resolved label, or nil if the block has no enumerated options.
    def self.choice_option_def(block, label)
      return nil unless block.is_a?(Hash)

      options = block['options']
      return nil unless options.is_a?(Hash)

      key = options.keys.find { |o| o.to_s.casecmp?(label.to_s) }
      return nil unless key && options[key].is_a?(Hash)

      options[key]
    end

    # The grants payload for a resolved choice. choice_name is the pending choice's key,
    # needed by pool filters and grants that read an earlier pick in the same sequence.
    def self.choice_grants(char, block, label, choice_name = nil)
      option = choice_option_def(block, label)
      return option['grants'] if option

      # A pool's own grants, applying to whatever was picked from it: Skill Mastery's raise of the
      # skill chosen, written `raise_skill: [ chosen ]`.
      return substitute_choice_label(block['grants'], label) if block.is_a?(Hash) && block['grants'].is_a?(Hash)

      return { 'skill' => [ label ] } if block.is_a?(Hash) && block.key?('from_lores')

      if block.is_a?(Hash) && block['from_spells'].is_a?(Hash)
        focus_type = block['from_spells']['focus_type']

        return { 'magic_stats' => { 'focus_spell' => { focus_type.to_s => [ label ] } } } if focus_type.present?

        return adapted_spell_grant(char, block, label, choice_name) if block['adapted']
      end

      return choice_dynamic_grants(char, block['from'], label, block) if block.is_a?(Hash) && block['from']

      nil
    end

    ARMOR_LADDER = %w(light medium heavy)

    def self.auto_choice?(block)
      block.is_a?(Hash) && !block['auto'].to_s.empty?
    end

    def self.auto_choice_label(char, block, advancement = nil)
      return nil unless auto_choice?(block)

      case block['auto'].to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block['archetype'], block['tier'])

        found && found[1]
      when 'next_armor_category'
        next_armor_category(char, advancement)
      else
        Global.logger.error "Unknown feat_choice auto source '#{block['auto']}'."
        nil
      end
    end

    def self.effective_armor_prof(char, advancement = nil)
      profs = (char.combat && char.combat.armor_prof) ? char.combat.armor_prof.dup : {}

      advancement = char.pf2_advancement if advancement.nil? && char.advancing
      return profs unless advancement.is_a?(Hash)

      staged = [ advancement.dig('combat_stats', 'armor_prof') ]

      grants = advancement['grants']

      if grants.is_a?(Hash)
        grants.each_value do |payload|
          staged << payload.dig('combat_stats', 'armor_prof') if payload.is_a?(Hash)
        end
      end

      staged.compact.each { |added| profs = merge_combat_stats(profs, added) }

      profs
    end

    def self.next_armor_category(char, advancement = nil)
      profs = effective_armor_prof(char, advancement)

      found = ARMOR_LADDER.find { |category| prof_rank(profs[category]).to_i.zero? }

      found && found.capitalize
    end

    # Grants implied by a dynamically sourced choice.
    def self.choice_dynamic_grants(char, source, value, block = nil)
      case source.to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block.is_a?(Hash) ? block['archetype'] : nil, block.is_a?(Hash) ? block['tier'] : nil)
        return nil unless found

        { 'magic_stats' => { 'focus_spell' => { found[0] => [ found[1] ] } } }
      when 'deity_domains', 'mystery_domains'
        domain_spell_grant(char, value, 'initial')
      when 'held_domains'
        domain_spell_grant(char, value, 'advanced')
      when 'lessons'
        lesson_grant(char, value)
      when 'devotion_spells'
        { 'magic_stats' => { 'focus_spell' => { 'devotion' => [ value ] } } }
      when 'other_specialties'
        # Order Explorer and Multifarious Muse: "you gain a 1st-level feat that lists that order as a
        # prerequisite", which is the gain itself, so its prerequisites are not asked again.
        feat = block.is_a?(Hash) && block['grants_specialty_feat'] && specialty_first_feat(char, value)

        feat ? { 'feat' => [ { 'name' => feat, 'prereqs' => 'ignore' } ] } : nil
      when 'chosen_specialties'
        # Order Magic: the specialty's initial focus spell, as its chargen block grants it.
        return nil unless block.is_a?(Hash) && block['grants_specialty_focus']

        info = Global.read_config('pf2e_specialty', char.pf2_base_info['charclass'].to_s, value.to_s) || {}
        focus = ((info['chargen'] || {})['magic_stats'] || {})['focus_spell']

        focus.is_a?(Hash) ? { 'magic_stats' => { 'focus_spell' => focus } } : nil
      when 'traditions', 'other_traditions', 'mystery_deities', 'deity_cleric_spells'
        # The deity's spells are worked out from the choice when the repertoire is read.
        nil
      else
        nil
      end
    end

    def self.domain_table
      Global.read_config('pf2e_magic', 'domains') || {}
    end

    # A domain's spell of one tier, as the focus type the character's class casts it as. The domain
    # is what granted the spell, so it travels with it - otherwise the sheet has to work back from a
    # deity's or a mystery's domain list to say where the spell came from.
    def self.domain_spell_grant(char, domain, tier)
      table = domain_table
      key = table.keys.find { |d| d.to_s.casecmp?(domain.to_s) }
      spell = key && table[key][tier]
      return nil if spell.blank?

      focus_type_by_source = Global.read_config('pf2e_magic', 'focus_type_by_source') || {}
      focus_type = focus_type_by_source[char.pf2_base_info['charclass']] || 'devotion'

      { 'magic_stats' => { 'focus_spell' => { focus_type => [ spell ] }, 'focus_source' => "Domain #{key}" } }
    end

    # A witch's lessons as choice labels, from the tiers the feat's block names. A lesson whose
    # familiar spell is a choice is listed once per spell, "Lesson of the Elements (Air Bubble)", so
    # the one pick settles both. A lesson whose hex is already held is left out.
    def self.lesson_options(char, block)
      tiers = Array(block.is_a?(Hash) ? block['tiers'] : nil).map { |t| t.to_s.downcase }
      lessons = Global.read_config('pf2e_magic', 'lessons') || {}
      held = held_focus_spells(char).map(&:downcase)

      labels = tiers.flat_map do |tier|
        (lessons[tier] || {}).flat_map do |lesson, info|
          next [] if held.include?(info['hex'].to_s.downcase)

          spells = Array(info['spell'])
          spells.size > 1 ? spells.map { |spell| "#{lesson} (#{spell})" } : [ lesson ]
        end
      end

      labels.sort
    end

    # The lesson a label names, and the familiar spell it carries.
    def self.lesson_for_label(label)
      lessons = (Global.read_config('pf2e_magic', 'lessons') || {}).values.inject({}) { |all, tier| all.merge(tier || {}) }

      name, spell = label.to_s.match(/\A(.+?)(?: \((.+)\))?\z/).captures
      key = lessons.keys.find { |l| l.to_s.casecmp?(name) }
      return nil unless key

      info = lessons[key]
      spells = Array(info['spell'])
      spell = spell ? spells.find { |s| s.casecmp?(spell) } : spells.first
      return nil unless spell && (spells.size == 1 || label.to_s.include?('('))

      [ key, info['hex'], spell ]
    end

    # A lesson's hex, and its familiar spell written into the witch's spellbook at the spell's rank.
    def self.lesson_grant(char, label)
      found = lesson_for_label(label)
      return nil unless found

      lesson, hex, spell = found
      rank = ((Global.read_config('pf2e_spells') || {})[spell] || {})['base_level'].to_i

      focus_type_by_source = Global.read_config('pf2e_magic', 'focus_type_by_source') || {}
      focus_type = focus_type_by_source[char.pf2_base_info['charclass']] || 'hex'

      { 'magic_stats' => { 'focus_spell' => { focus_type => [ hex ] },
                           'addspellbook' => { rank => [ spell ] },
                           'focus_source' => lesson } }
    end

    THE_TRADITIONS = %w(arcane divine occult primal)

    def self.own_traditions(char)
      magic = char.magic
      return [] unless magic

      Pf2emagic::Entries.casting(magic).each_with_object({}) { |e, h| h[e['name']] = [ e['tradition'], e['proficiency'] ] }
        .values
        .map { |entry| Array(entry).first.to_s.downcase }
        .reject(&:empty?)
        .uniq
    end

    # Whether the character can cast at all through a spellcasting class -- the "ability to
    # cast spells / cantrips" prerequisite.
    def self.character_is_caster?(char)
      return true if own_traditions(char).any?

      !(char.magic&.innate_spells || {}).empty?
    end

    def self.resolve_tradition_spec(char, spec, choice_name = nil)
      case spec
      when nil
        nil
      when Array
        spec.map { |t| t.to_s.downcase }
      when Hash
        src = spec['from_feat_choice']
        return [] unless src

        trad = adapted_source_tradition(char, src)
        trad ? [ trad.to_s.downcase ] : []
      else
        case spec.to_s.downcase
        when 'own'
          own_traditions(char)
        when 'not_own'
          THE_TRADITIONS - own_traditions(char)
        when 'from_prior_choice'
          prior = choice_labels_for(char, choice_name).last.to_s.downcase
          prior.empty? ? [] : [ prior ]
        else
          [ spec.to_s.downcase ]
        end
      end
    end

    def self.adapted_source_tradition(char, source)
      spells = char.magic&.adapted_spells || {}

      entry = spells.values.find { |e| e.is_a?(Hash) && e['source'].to_s.casecmp?(source.to_s) }
      entry && entry['tradition']
    end

    def self.adapted_spell_grant(char, block, spell_name, choice_name = nil)
      return nil unless AresMUSH.const_defined?("Pf2emagic")

      spell = Pf2emagic.get_spell_details(spell_name)
      return nil if spell.is_a?(String)

      name, details = spell
      base_level = details['base_level'].to_s.downcase == 'cantrip' ? 0 : details['base_level'].to_i
      level_key = base_level.zero? ? 'cantrip' : base_level.to_s

      spec = block['from_spells'].is_a?(Hash) ? block['from_spells']['tradition'] : nil
      allowed = Array(resolve_tradition_spec(char, spec, choice_name))
      spell_trads = Array(details['tradition']).compact.map { |t| t.to_s.downcase }
      tradition = (allowed & spell_trads).first || allowed.first || spell_trads.first

      entry = {
        'name'       => name,
        'tradition'  => tradition,
        'base_level' => base_level,
        'source'     => choice_name
      }
      # Adaptive Adept: a 1st-rank (or higher) pick is fixed at its base rank. A cantrip
      # heightens by the normal rules regardless, so the flag only bites above rank 0.
      entry['no_heighten'] = true if block['no_heighten'] && base_level.positive?

      stats = { 'adapted_spell' => entry }

      if Pf2emagic.get_caster_type(char.pf2_base_info['charclass']) == 'spontaneous'
        stats['addrepertoire'] = { level_key => [ name ] }
      end

      { 'magic_stats' => stats }
    end

    # Entries owed on advancing into a level, as [ level, payload ].
    def self.at_level_due(at_level, level)
      return [] unless at_level.is_a?(Hash)

      # YAML gives these integer keys; Redis hands them back as strings. Compare numerically.
      at_level.keys
              .select { |k| k.to_s.to_i == level.to_i }
              .map { |k| [ k.to_s.to_i, at_level[k] ] }
    end

    # Entries owed on acquiring something at a level, as [ level, payload ], lowest first.
    def self.at_level_caught_up(at_level, level)
      return [] unless at_level.is_a?(Hash)

      at_level.keys
              .select { |k| k.to_s.to_i <= level.to_i }
              .sort_by { |k| k.to_s.to_i }
              .map { |k| [ k.to_s.to_i, at_level[k] ] }
    end

    # The at_level map on a feat itself, beside its grants.
    def self.feat_at_level(details)
      details.is_a?(Hash) ? details['at_level'] : nil
    end

    def self.choice_option_at_level(block, label)
      option = choice_option_def(block, label)
      return option['at_level'] if option && option['at_level']

      block.is_a?(Hash) ? block['at_level'] : nil
    end

    CHOSEN_LABEL_SENTINEL = 'chosen'

    def self.substitute_choice_label(payload, label)
      case payload
      when Hash
        payload.each_with_object({}) { |(k, v), h| h[k] = substitute_choice_label(v, label) }
      when Array
        payload.map { |v| substitute_choice_label(v, label) }
      when String
        payload.casecmp?(CHOSEN_LABEL_SENTINEL) ? label.to_s : payload
      else
        payload
      end
    end

    # The single payload a resolved choice owes on advancing into a level, or nil.
    def self.choice_at_level(block, label, level)
      due = at_level_due(choice_option_at_level(block, label), level)

      due.empty? ? nil : substitute_choice_label(due.first[1], label)
    end

    # Level clauses on held feats that come due at the given level, as [ feat, level, payload ].
    def self.deferred_feat_grants(char, level)
      feats = Global.read_config('pf2e_feats') || {}

      DraftSheet.of(char).feat_names.uniq.flat_map do |name|
        key = feats.keys.find { |k| k.to_s.casecmp?(name.to_s) }
        next [] unless key

        at_level_due(feat_at_level(feats[key]), level).map { |lvl, payload| [ name, lvl, payload ] }
      end
    end

    # Level clauses a feat owes immediately on acquisition, as [ level, payload ].
    def self.feat_at_level_catch_up(details, level)
      at_level_caught_up(feat_at_level(details), level)
    end

    CHOICE_INLINE_LIMIT = 20

    # A choice block declared on a feat, which is named after that feat.
    def self.feat_choice_block_for(choice_name)
      details = get_feat_details(choice_name.to_s)
      return nil if details.is_a?(String)

      feat_choice_def(details[1])
    end

    # A choice block declared on a class, subclass, or specialty entry, named by the key it
    # appears under there.
    def self.class_choice_block_for(char, choice_name)
      blocks = class_choice_blocks(char)
      match = blocks.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }

      match ? blocks[match] : nil
    end

    def self.find_choice_block(char, choice_name, source = nil)
      feat_block = source.to_s != 'charclass' && feat_choice_block_for(choice_name)

      if feat_block
        return advance_choice_steps(feat_block, feat_choice_step(char, choice_name))
      end

      return nil if source.to_s == 'feat'

      # A class's choice can be chained too (Divine Access: a deity, then its spells).
      class_block = class_choice_block_for(char, choice_name)

      class_block && advance_choice_steps(class_block, feat_choice_step(char, choice_name))
    end

    def self.advance_choice_steps(block, steps)
      steps.to_i.times do
        nxt = block.is_a?(Hash) && block['then_choose']
        break unless nxt.is_a?(Hash)

        block = nxt
      end

      block
    end

    def self.feat_choice_step(char, choice_name)
      choices = (char.pf2_to_assign || {})['feat choice']
      return 0 unless choices.is_a?(Hash)

      key = choices.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      Array(key && choices[key]).count { |slot| slot.to_s.strip.downcase != 'open' }
    end

    def self.choice_source_entries(char)
      entries = []

      charclass = char.pf2_base_info['charclass']

      unless charclass.blank?
        class_info = Global.read_config('pf2e_class', charclass) || {}

        entries << [ charclass, class_info ]
        entries << [ charclass, class_info['chargen'] ]
        entries.concat(class_info['advance'].values.map { |v| [ charclass, v ] }) if class_info['advance'].is_a?(Hash)

        specialize = char.pf2_base_info['specialize']

        unless specialize.blank?
          spec_info = Global.read_config('pf2e_specialty', charclass, specialize) || {}

          if spec_info.is_a?(Hash)
            entries << [ charclass, spec_info ]
            entries << [ charclass, spec_info['chargen'] ]
            entries.concat(spec_info['advance'].values.map { |v| [ charclass, v ] }) if spec_info['advance'].is_a?(Hash)

            specialize_info = char.pf2_base_info['specialize_info']

            unless specialize_info.blank?
              option_info = spec_info.dig('choose', 'options', specialize_info)

              if option_info.is_a?(Hash)
                entries << [ charclass, option_info ]
                entries << [ charclass, option_info['chargen'] ]
                entries.concat(option_info['advance'].values.map { |v| [ charclass, v ] }) if option_info['advance'].is_a?(Hash)
              end
            end
          end
        end
      end

      held_archetypes(char).each do |archetype|
        entries << [ archetype, Global.read_config('pf2e_archetype', archetype) ]

        mirrored = Global.read_config('pf2e_class', mirrored_class(archetype))
        entries << [ archetype, mirrored ] if mirrored
      end

      entries.reject { |_source, info| info.nil? }
    end

    def self.held_archetypes(char)
      info = char.pf2_archetypeinfo || {}

      (1..4).map { |i| info["archetype#{i}"] }.compact.map(&:to_s).reject(&:empty?).uniq
    end

    # The class an archetype draws its features from, where it draws them from one at all.
    def self.mirrored_class(archetype)
      archetype.to_s.sub(/\s*Archetype\z/i, '')
    end

    def self.class_choice_blocks(char)
      choice_source_entries(char).each_with_object({}) do |(_source, info), hash|
        hash.merge!(level_feat_choices(info))
      end
    end

    def self.choice_caster_source(char, choice_name)
      entry = choice_source_entries(char).find do |_source, info|
        level_feat_choices(info).keys.any? { |k| k.to_s.casecmp?(choice_name.to_s) }
      end

      entry ? entry[0] : char.pf2_base_info['charclass']
    end

    def self.granted_choice_names(info)
      return [] unless info.is_a?(Hash)

      names = level_feat_choices(info).keys
      names.concat(Array(info['grant_choice']).compact.map { |n| n.to_s })

      names.uniq
    end

    def self.pending_feat_choices(char)
      to_assign = char.pf2_to_assign || {}

      stored = to_assign['feat choice']
      return {} unless stored.is_a?(Hash)

      stored.each_with_object({}) { |(name, slots), pending| pending[name] = Array(slots) }
    end

    # A choice a feat carries is a slot like any other, so opening one is the slot vocabulary
    # rather than an inline array append - see Pf2e::Slots.
    def self.open_feat_choice(to_assign, choice_name, count = 1)
      to_assign.replace(Slots.apply(to_assign, [ Slots.open([ 'feat choice', choice_name ], :count => count) ]))
    end

    def self.fill_feat_choice(to_assign, choice_name, value)
      choices = to_assign['feat choice'] || {}
      key = choices.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      return false unless key

      filled = Slots.apply(to_assign, [ Slots.fill([ 'feat choice', key ], value) ])
      return false if filled.is_a?(Err)

      to_assign.replace(filled)
      slots = Array(to_assign['feat choice'][key])

      # A narrowing only applies while the slot it was opened for is still open.
      clear_choice_filter(to_assign, key) unless slots.include?('open')

      true
    end

    def self.store_choice_filter(to_assign, choice_name, filter)
      return to_assign unless filter.is_a?(Hash) && !filter.empty?

      filters = to_assign['feat choice filter'] || {}
      filters[choice_name] = filter
      to_assign['feat choice filter'] = filters

      to_assign
    end

    def self.clear_choice_filter(to_assign, choice_name)
      filters = to_assign['feat choice filter']
      return to_assign unless filters.is_a?(Hash)

      key = filters.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      filters.delete(key) if key

      to_assign['feat choice filter'] = filters

      to_assign
    end

    def self.stored_choice_filter(char, choice_name)
      filters = (char.pf2_to_assign || {})['feat choice filter']
      return nil unless filters.is_a?(Hash)

      key = filters.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      key && filters[key]
    end

    def self.narrow_choice_options(char, choice_name, options)
      filter = stored_choice_filter(char, choice_name)
      return options unless filter.is_a?(Hash)

      allowed = if filter['options']
        Array(filter['options']).compact
      elsif filter['from']
        choice_dynamic_options(char, filter['from'])
      elsif filter['same_as']
        choice_labels_for(char, filter['same_as'])
      end

      return options unless allowed

      options.select { |o| allowed.any? { |a| a.to_s.casecmp?(o.to_s) } }
    end

    def self.validate_feat_choice(char, choice_name, source = nil)
      pending = pending_feat_choices(char)
      key = pending.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }

      return t('pf2e.no_such_choice', :choice => choice_name) unless key
      return t('pf2e.choice_already_resolved', :choice => key) unless Array(pending[key]).include?('open')

      block = find_choice_block(char, key, source)

      unless block
        if source.present? && find_choice_block(char, key)
          actual = feat_choice_block_for(key) ? 'feat' : 'charclass'

          return t('pf2e.choice_wrong_source',
            :choice => key,
            :source => source,
            :actual => actual,
            :cmd => choice_option_cmd(char))
        end

        return t('pf2e.choice_not_configured', :choice => key)
      end

      [ key, block ]
    end

    # The command that lists a choice's options in full, which differs by mode.
    def self.choice_info_cmd(char)
      char.advancing ? 'advance/info' : 'cg/info'
    end

    # The command that resolves a choice, which differs by mode the same way.
    def self.choice_option_cmd(char)
      char.advancing ? 'advance/option' : 'cg/option'
    end

    # What the player may pick, as a message. Large pools are not dumped inline; they are
    # left to the info command, which paginates.
    def self.describe_choice_options(char, choice_name, block)
      options = choice_options(char, choice_name, block)

      return t('pf2e.choice_no_options', :choice => choice_name) if options.empty?

      if options.size > CHOICE_INLINE_LIMIT
        return t('pf2e.choice_too_many_options',
          :choice => choice_name,
          :count => options.size,
          :cmd => choice_info_cmd(char))
      end

      t('pf2e.choice_options', :choice => choice_name, :options => options.join(", "))
    end

    def self.describe_bad_choice_option(char, choice_name, block)
      options = choice_options(char, choice_name, block)

      return t('pf2e.choice_no_options', :choice => choice_name) if options.empty?

      if options.size > CHOICE_INLINE_LIMIT
        return t('pf2e.choice_bad_option_many',
          :choice => choice_name,
          :count => options.size,
          :cmd => choice_info_cmd(char))
      end

      t('pf2e.choice_bad_option', :choice => choice_name, :options => options.join(", "))
    end

    # Feats matching a from_feats filter that the character does not already have.
    def self.choice_feat_pool(char, filter)
      feats = Global.read_config('pf2e_feats') || {}

      # Tallied once rather than rebuilt inside the loop by has_feat?. A repeatable feat
      # stays selectable until it is actually maxed out.
      tally = feat_tally(char)

      # One read of the sheet for the whole sweep, as get_feat_options does.
      list = Pf2e::SheetReads.holding(char) do
        feats.keys.select do |name|
          next false if feat_repeat_block(char, name, feats[name], tally[name.to_s.upcase])

          choice_feat_match?(char, name, feats[name], filter)
        end
      end

      list.sort
    end

    def self.choice_feat_match?(char, feat_name, details, filter)
      return false unless details.is_a?(Hash)
      return false unless filter.is_a?(Hash)

      feat_types = Array(details['feat_type']).compact.map { |f| f.to_s.downcase }
      return false if feat_types.empty?

      # No double-dipping on base class / dedication, per Paizo RAW.
      return false unless dedication_allowed?(char, details)

      # A named pair rather than a category: PF2e has features that hand over one of two specific
      # feats, the Druid's Voice of Nature being "your choice of the Animal Empathy or Plant
      # Empathy druid feat". A whitelist, so the rest of the filter still applies.
      if filter['names']
        wanted = Array(filter['names']).compact.map { |n| n.to_s.downcase }
        return false unless wanted.include?(feat_name.to_s.downcase)
      end

      if filter['feat_type']
        wanted = Array(filter['feat_type']).compact.map { |f| f.to_s.downcase }
        return false unless wanted.any? { |w| feat_types.include?(w) }
      end

      cap = filter['max_level'] ? choice_level_cap(char, filter['max_level']) : nil

      if cap
        prereq_level = details.dig('prereq', 'level')
        return false if prereq_level.nil?
        return false if prereq_level.to_i > cap
      end

      if filter['traits']
        wanted = Array(filter['traits']).compact.map { |t| t.to_s.downcase }
        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        return false unless wanted.any? { |w| traits.include?(w) }
      end

      # Narrows a lineage-feat pool to the lineage matching the character's own heritage
      if filter['trait_matches_heritage']
        heritage = char.pf2_base_info['heritage'].to_s.downcase
        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        return false unless traits.include?(heritage)
      end

      if filter['assoc_charclass']
        wanted = Array(filter['assoc_charclass']).compact.map { |c| c.to_s.downcase }
        assoc = Array(details['assoc_charclass']).compact.map { |c| c.to_s.downcase }
        return false unless wanted.any? { |w| assoc.include?(w) }
      end

      if filter['own_charclass']
        base_class = char.pf2_base_info['charclass'].to_s
        assoc = Array(details['assoc_charclass']).compact
        return false unless assoc.any? { |c| c.to_s.casecmp?(base_class) }
      end

      # Restricts the pool to feats that are open only because of an adopted ancestry
      if filter['adopted_only']
        assoc = Array(details['assoc_ancestry'])

        opened = adopted_ancestries(char).any? do |a|
          assoc.include?(a) && adopted_feat?(a, feat_name)
        end

        return false unless opened
      end

      # Narrows to the skill feats hanging off one named skill
      if filter['assoc_skill']
        wanted = Array(filter['assoc_skill']).compact.map { |s| s.to_s.downcase }
        skills = Array(details['assoc_skill']).compact.map { |s| s.to_s.downcase }

        return false unless wanted.any? { |w| skills.include?(w) }
      end

      if filter['skill_key_abil']
        wanted = Array(filter['skill_key_abil']).compact.map { |a| a.to_s.downcase }
        skills = Global.read_config('pf2e_skills') || {}
        assoc_skills = Array(details['assoc_skill']).compact

        return false if assoc_skills.empty?

        matches = assoc_skills.any? do |skill_name|
          key = skills.keys.find { |s| s.to_s.casecmp?(skill_name.to_s) }
          key && wanted.include?(skills[key]['key_abil'].to_s.downcase)
        end

        return false unless matches
      end

      return true if filter['qualify'] == false

      can_take_feat_details?(char, feat_name, details, cap, filter['ignore_charclass'])
    end

    def self.choice_level_cap(char, value)
      return effective_char_level(char) / 2 if value.to_s == 'half_level'

      value.to_i
    end

    def self.effective_char_level(char)
      DraftSheet.of(char).level
    end

    def self.choice_skill_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      min_rank = prof_rank(filter['min_prof'] || 'trained') || 1
      max_rank = filter['max_prof'] ? prof_rank(filter['max_prof']) : nil

      # Ranks as this level leaves them, so a skill raised earlier in the level - by an earlier
      # step of the same choice, say - is judged at its new rank.
      sheet = DraftSheet.of(char)

      list = char.skills.map(&:name).select do |name|
        rank = prof_rank(sheet.skill_prof(name))
        rank && rank >= min_rank && (max_rank.nil? || rank <= max_rank)
      end

      if filter['key_abil']
        wanted = Array(filter['key_abil']).compact.map { |a| a.to_s.downcase }
        skills = Global.read_config('pf2e_skills') || {}

        list = list.select do |name|
          key = skills.keys.find { |s| s.to_s.casecmp?(name.to_s) }
          key && wanted.include?(skills[key]['key_abil'].to_s.downcase)
        end
      end

      list.sort
    end

    def self.choice_spell_pool(char, filter, choice_name = nil)
      filter = {} unless filter.is_a?(Hash)

      spells = Global.read_config('pf2e_spells') || {}

      wanted = Array(filter['traits']).compact.map { |t| t.to_s.downcase }

      ranks = if filter.key?('base_level')
        Array(filter['base_level']).map { |r| r.to_s.downcase == 'cantrip' ? 0 : r.to_i }
      end

      allowed_trads = filter.key?('tradition') ? resolve_tradition_spec(char, filter['tradition'], choice_name) : nil

      # `subclass: own` or `other`: spells tagged for the character's own bloodline or mystery, or
      # for another one. An untagged spell belongs to no subclass and matches neither.
      subclass = filter['subclass'].to_s.downcase
      own = subclass.empty? ? '' : (char.pf2_base_info || {})['specialize'].to_s.downcase

      list = spells.keys.select do |name|
        details = spells[name]
        next false unless details.is_a?(Hash)

        if ranks
          spell_rank = details['base_level'].to_s.downcase == 'cantrip' ? 0 : details['base_level'].to_i
          next false unless ranks.include?(spell_rank)
        end

        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        next false unless wanted.all? { |w| traits.include?(w) }

        unless subclass.empty?
          tags = (Array(details['bloodline']) + Array(details['mystery'])).map { |t| t.to_s.downcase }
          next false if tags.empty?
          next false if subclass == 'own' && !tags.include?(own)
          next false if subclass == 'other' && tags.include?(own)
        end

        if allowed_trads
          spell_trads = Array(details['tradition']).compact.map { |t| t.to_s.downcase }
          next false unless allowed_trads.any? { |t| spell_trads.include?(t) }
        end

        true
      end

      # Focus spells are entries, not an attribute of the magic object - one per focus type per
      # granting source - so Entries is the only place that can answer this.
      held = Array(char.magic && Pf2emagic::Entries.focus_spells(char.magic, filter['focus_type'])).map { |s| s.to_s.downcase }

      list.reject { |name| held.include?(name.to_s.downcase) }.sort
    end

    def self.choice_lore_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      list = lore_skills(filter['group'])

      trained = char.skills.reject { |s| s.prof_level.to_s.casecmp?('untrained') }.map { |s| s.name.to_s.downcase }

      list.reject { |name| trained.include?(name.to_s.downcase) }.sort
    end

    # Whether a skill entry is a Lore subcategory rather than one of the sixteen base skills.
    def self.lore_skill?(name, details = nil)
      return true if details.is_a?(Hash) && !Array(details['lore_groups']).empty?

      name.to_s.strip =~ /\bLore\z/i ? true : false
    end

    # Lore skills from pf2e_skills.yml, sorted, leaving out any marked hidden. Given groups, only
    # the lores tagged with at least one of them.
    def self.lore_skills(groups = nil)
      skills = Global.read_config('pf2e_skills') || {}

      list = skills.keys.select do |name|
        details = skills[name]

        lore_skill?(name, details) && !(details.is_a?(Hash) && details['hidden'])
      end

      unless groups.nil?
        wanted = Array(groups).compact.map { |g| g.to_s.downcase }

        list = list.select { |name| (lore_groups_of(skills[name]) & wanted).any? }
      end

      list.sort
    end

    # A skill entry's lore_groups tags, downcased.
    def self.lore_groups_of(details)
      return [] unless details.is_a?(Hash)

      Array(details['lore_groups']).compact.map { |g| g.to_s.downcase }
    end

    # The lore groups skills/lore lists, from pf2e_options.yml, keyed by group name.
    def self.lore_group_lists
      Global.read_config('pf2e', 'lore_group_lists') || {}
    end

    # The lore group a player typed, by its name or one of its aliases. Nil when it is neither.
    def self.find_lore_group(input)
      wanted = input.to_s.strip.downcase

      lore_group_lists.keys.find do |group|
        details = lore_group_lists[group] || {}

        group.to_s.downcase == wanted || Array(details['aliases']).any? { |a| a.to_s.downcase == wanted }
      end
    end

    # How a lore group is shown: its configured name, or its key with each word capitalized.
    def self.lore_group_display_name(group)
      name = (lore_group_lists[group] || {})['name']
      return name.to_s unless name.to_s.strip.empty?

      group.to_s.split(' ').map(&:capitalize).join(' ')
    end

    # Every lore group's display name, in the order listed, for the skills/lore index.
    def self.lore_group_index
      lore_group_lists.keys.map { |group| lore_group_display_name(group) }
    end

    # One line per alias, for the skills/lore index. An alias that only repeats the group's
    # display name - crafting, for Crafting - says nothing, so it is left out.
    def self.lore_group_alias_lines
      lore_group_lists.flat_map do |group, details|
        name = lore_group_display_name(group)

        Array((details || {})['aliases']).reject { |a| a.to_s.casecmp?(name) }.map do |a|
          t('pf2e.lore_group_alias', :alias => a.to_s.split(' ').map(&:capitalize).join(' '), :group => name)
        end
      end
    end

    # A lore group's lores as [heading, lores] pairs. A group without sections is one list with no
    # heading. A group with sections is split by those tags in the order they are listed, and any
    # lore that fits none of them trails under "Other" rather than disappearing.
    def self.lore_group_sections(group)
      details = lore_group_lists[group] || {}
      lores = lore_skills(group) - Array(Global.read_config('pf2e', 'hidden_options'))
      sections = details['sections']

      return [ [ nil, lores ] ] unless sections.is_a?(Hash) && !sections.empty?

      skills = Global.read_config('pf2e_skills') || {}
      placed = []

      result = sections.map do |tag, heading|
        in_section = lores.select { |name| lore_groups_of(skills[name]).include?(tag.to_s.downcase) }
        placed.concat(in_section)

        [ heading, in_section ]
      end

      leftover = lores - placed
      result << [ t('pf2e.lore_group_other'), leftover ] unless leftover.empty?

      result.reject { |_, list| list.empty? }
    end

    # One page of a lore group's sections. A group with sections_per_page is paged by whole
    # sections, so a region never splits across two pages; any other group is a single page.
    def self.lore_group_page(group, page)
      sections = lore_group_sections(group)
      per_page = (lore_group_lists[group] || {})['sections_per_page'].to_i
      per_page = sections.size if per_page < 1

      Paginator.paginate(sections, page, [ per_page, 1 ].max)
    end

    # Weapons matching a from_weapons filter, drawn from pf2e_weapons.yml.
    def self.choice_weapon_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      weapons = Global.read_config('pf2e_weapons') || {}

      list = weapons.keys.select do |name|
        details = weapons[name]
        next false unless details.is_a?(Hash)

        if filter['category']
          wanted = Array(filter['category']).compact.map { |c| c.to_s.downcase }
          next false unless wanted.include?(details['category'].to_s.downcase)
        end

        if filter['group']
          wanted = Array(filter['group']).compact.map { |g| g.to_s.downcase }
          next false unless wanted.include?(details['group'].to_s.downcase)
        end

        true
      end

      list.sort
    end

    # Weapon groups holding a weapon of the filter's category, drawn from pf2e_weapons.yml.
    def self.choice_weapon_group_pool(_char, filter)
      wanted = Array((filter.is_a?(Hash) ? filter : {})['category']).map { |c| c.to_s.downcase }
      weapons = Global.read_config('pf2e_weapons') || {}

      weapons.values.filter_map do |details|
        next unless details.is_a?(Hash) && details['group'].present?
        next if wanted.any? && !wanted.include?(details['category'].to_s.downcase)

        details['group'].to_s
      end.uniq.sort
    end

    # Weapon names the character has chosen through any feat whose choice draws from the
    # weapon list, such as Weapon Proficiency.
    def self.chosen_weapons(char)
      recorded_choices(char).filter_map do |name, label, _level|
        block = find_choice_block(char, name)
        next unless block.is_a?(Hash) && block['from_weapons']

        label
      end.uniq
    end

    # The categories a weapon also counts as for this character: Advanced Weapon Training's chosen
    # group, whose advanced weapons count as martial. Read from any recorded choice whose block draws
    # from the weapon groups and names an `as_category`.
    def self.weapon_counts_as(char, category, group)
      return [] if group.blank?

      recorded_choices(char).filter_map do |name, label, _level|
        block = find_choice_block(char, name)
        next unless block.is_a?(Hash) && block['from_weapon_groups'].is_a?(Hash) && block['as_category'].present?
        next unless block['from_weapon_groups']['category'].to_s.casecmp?(category.to_s)
        next unless label.to_s.casecmp?(group.to_s)

        block['as_category'].to_s.downcase
      end.uniq
    end

    # Ancestries the character has taken on through any feat whose choice draws from the
    # ancestry list, such as Adopted Ancestry.
    def self.adopted_ancestries(char)
      recorded = recorded_choices(char)
      legacy = char.pf2_base_info['adopted ancestry']

      return [] if recorded.empty? && legacy.blank?

      feats = Global.read_config('pf2e_feats') || {}

      adopted = recorded.filter_map do |name, label, _level|
        block = feat_choice_def(feats[name])
        next unless block.is_a?(Hash) && block['from'].to_s.casecmp?('ancestries')

        label
      end

      # Kept for sheets that were set directly rather than through the feat.
      adopted << legacy if legacy.present?

      adopted.uniq
    end

    # Whether an adopted ancestry opens this particular feat.
    def self.adopted_feat?(ancestry, feat_name)
      list = Global.read_config('pf2e_ancestry', ancestry, 'adopted_feats')

      Array(list).any? { |f| f.to_s.casecmp?(feat_name.to_s) }
    end

    # Whether a feat's choice opens on this taking.
    def self.feat_choice_opens_at?(block, instance)
      return false unless block.is_a?(Hash)

      from = block['from_instance']
      return true unless from

      instance.to_i >= from.to_i
    end

    # The subclass a character holds for one archetype, and the initial focus spell it grants.
    def self.archetype_subclass_spell(char, archetype, tier = nil)
      if archetype.blank?
        cls = char.pf2_base_info['charclass']
        subclass = char.pf2_base_info['specialize']
      else
        info = char.pf2_archetypeinfo || {}
        slot = (1..4).find { |i| info["archetype#{i}"].to_s.casecmp?(archetype.to_s) }
        return nil unless slot

        cls = mirrored_class(archetype)
        subclass = info["archetype_specialty#{slot}"]
      end

      return nil if cls.blank? || subclass.blank?

      spec = Global.read_config('pf2e_specialty', cls.to_s, subclass)
      return nil unless spec.is_a?(Hash)

      # The initial spell is the one chargen grants; each later tier has its own key, such as
      # `advanced_focus_spell` or `greater_focus_spell`.
      focus = if tier.blank? || tier.to_s.casecmp?('initial')
        spec.dig('chargen', 'magic_stats', 'focus_spell')
      else
        spec["#{tier.to_s.downcase}_focus_spell"]
      end

      return nil unless focus.is_a?(Hash)

      focus_type, spells = focus.first
      spell = Array(spells).first

      spell.blank? ? nil : [ focus_type, spell ]
    end

    def self.choice_dynamic_options(char, source, block = nil, choice_name = nil)
      case source.to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block.is_a?(Hash) ? block['archetype'] : nil, block.is_a?(Hash) ? block['tier'] : nil)

        found ? [ found[1] ] : []
      when 'deity_domains'
        deity = char.pf2_faith['deity']
        return [] if deity.blank?

        deity_info = (Global.read_config('pf2e_deities') || {})[deity]
        return [] unless deity_info

        Array(deity_info['domains']).compact.sort
      when 'held_domains'
        # Advanced Domain and its like: a domain whose initial spell is held and whose advanced
        # spell is not yet.
        held = held_focus_spells(char).map(&:downcase)

        domain_table.select do |_domain, info|
          held.include?(info['initial'].to_s.downcase) && !held.include?(info['advanced'].to_s.downcase)
        end.keys.sort
      when 'mystery_domains'
        # Domain Acumen: the domains the oracle's mystery lists, less those already begun.
        base = char.pf2_base_info || {}
        mystery = Global.read_config('pf2e_specialty', base['charclass'].to_s, base['specialize'].to_s) || {}
        held = held_focus_spells(char).map(&:downcase)
        table = domain_table

        Array(mystery['domains']).select do |domain|
          table[domain] && !held.include?(table[domain]['initial'].to_s.downcase)
        end.sort
      when 'mystery_deities'
        # Divine Access: a deity who grants one of the mystery's domains.
        mystery_deities(char)
      when 'deity_cleric_spells'
        # Divine Access's later steps: the cleric spells of the deity its first step picked. The
        # spells already picked are left out by choice_options, as for any choice.
        deity = choice_labels_for(char, choice_name).find { |label| deity_named(label) }

        deity ? deity_cleric_spells(deity).sort : []
      when 'lessons'
        lesson_options(char, block)
      when 'other_specialties'
        # Another order, muse or bloodline than the character's own.
        own = char.pf2_base_info['specialize'].to_s

        class_specialties(char).reject { |s| s.casecmp?(own) }.sort
      when 'chosen_specialties'
        # The specialties picked with another choice - Order Magic's orders explored.
        chosen = choice_labels_for(char, block.is_a?(Hash) ? block['from_choice'] : nil)

        class_specialties(char).select { |s| chosen.any? { |c| c.to_s.casecmp?(s) } }.sort
      when 'specialty_options'
        # The 1st-level choice of the specialty picked in this choice's first step, if it has one.
        specialty = specialty_and_option(char, choice_labels_for(char, choice_name))&.first
        info = specialty && Global.read_config('pf2e_specialty', char.pf2_base_info['charclass'].to_s, specialty)

        (((info || {})['choose'] || {})['options'] || {}).keys.sort
      when 'secondary_gift_spells'
        # The sorcerous gift spells of the bloodline another choice picked, its option's included.
        found = specialty_and_option(char, choice_labels_for(char, block.is_a?(Hash) ? block['from_choice'] : nil))

        found ? Pf2emagic.all_gift_spells(char.pf2_base_info['charclass'], found[0], found[1]).sort : []
      when 'devotion_spells'
        options = [ 'Shields of the Spirit' ]

        deity = char.pf2_faith['deity']

        if deity.blank? && char.advancing
          pending = (char.pf2_to_assign || {})['archetype deity']
          deity = pending unless pending.blank? || pending.to_s.casecmp?('open')
        end

        # read_config takes at most three keys, so the fourth is a plain hash read.
        fonts = deity.blank? ? [] : Array((Global.read_config('pf2e_deities', deity, 'magic_stats') || {})['divine_font'])

        options << 'Lay on Hands' if fonts.any? { |f| f.to_s.casecmp?('heal') }
        options << 'Touch of the Void' if fonts.any? { |f| f.to_s.casecmp?('harm') }

        options.sort
      when 'lineage planes'
        # Nephilim Lore.
        case char.pf2_base_info['heritage'].to_s
        when /\AAesa\z/i
          [ 'City of Bells Lore', 'Elysian Fields Lore', 'Shining Peak Lore' ]
        when /\ANiasa\z/i
          [ 'Iron Hells Lore', 'The Abyss Lore', 'The Null Lore' ]
        else
          []
        end
      when 'ancestries'
        # Adopted Ancestry. Their own is excluded, since the feat is about taking on
        # another one, and duplicate exclusion handles any they have already adopted.
        own = char.pf2_base_info['ancestry'].to_s

        (Global.read_config('pf2e_ancestry') || {}).keys
          .reject { |a| a.to_s.casecmp?(own) }
          .sort
      when 'traditions'
        THE_TRADITIONS.map(&:capitalize)
      when 'other_traditions'
        # Adapted Cantrip: the magical traditions the character does not already cast as.
        own = own_traditions(char)

        THE_TRADITIONS.reject { |t| own.include?(t) }.map(&:capitalize).sort
      else
        Global.logger.error "Unknown feat_choice source '#{source}'."
        []
      end
    end

    DEFERRED_CHOICE_SOURCES = [ 'skill choice' ]

    def self.deferred_choice_source?(source)
      DEFERRED_CHOICE_SOURCES.include?(source.to_s.downcase)
    end

    # [ name, choice, choice_from, choice_filter, prereqs waived ] for a granted feat, which the data
    # writes as a bare name or a hash. `prereqs: ignore` hands a feat over without its prerequisites,
    # as Spellbook Prodigy does Magical Shorthand.
    def self.granted_feat_entry(entry)
      return [ entry.to_s, nil, nil, nil, false ] unless entry.is_a?(Hash)

      name = entry['name'].to_s
      return nil if name.empty?

      [ name, entry['choice'], entry['choice_from'], entry['choice_filter'], entry['prereqs'].to_s.casecmp?('ignore') ]
    end

    def self.granted_choice_label(char, source)
      case source.to_s.downcase
      when 'skill choice'
        choice = (char.pf2_to_assign || {})['bg skill choice']
        return nil unless choice.is_a?(Hash)

        selected = choice['selected']
        return nil if selected.blank? || selected.to_s == 'open'

        selected
      when 'divine skill'
        deity_config(char)&.fetch('divine_skill', nil)
      when 'related lore'
        deity_config(char)&.fetch('related_lore', nil)
      when 'divine ability'
        deity_config(char)&.fetch('divine_ability', nil)
      else
        Global.logger.error "Unknown choice_from source '#{source}'."
        nil
      end
    end

    def self.config_skills(char, source)
      return [] unless source.is_a?(Hash)

      Array(source['skills']).filter_map do |entry|
        next entry unless entry.is_a?(Hash)

        label = granted_choice_label(char, entry['from'])

        if label.blank?
          Global.logger.error "Config skill 'from: #{entry['from']}' resolved to nothing for #{char.name}."
          next nil
        end

        label
      end
    end

    def self.config_abl_boosts(char, source)
      return [] unless source.is_a?(Hash)

      Array(source['abl_boosts']).filter_map do |entry|
        next entry unless entry.is_a?(Hash)

        label = granted_choice_label(char, entry['from'])

        if label.blank?
          Global.logger.error "Config boost 'from: #{entry['from']}' resolved to nothing for #{char.name}."
          next nil
        end

        options = Array(label)

        options.size > 1 ? options : options.first
      end
    end

    # The character's deity entry, or nil when they have no deity set.
    def self.deity_config(char)
      deity = (char.pf2_faith || {})['deity']
      return nil if deity.blank?

      Global.read_config('pf2e_deities', deity)
    end

    # The headings a sheet groups feats under. `pf2_feats` is keyed by these.
    FEAT_BUCKETS = %w(charclass skill general ancestry archetype dedication).freeze

    # Where a feat belongs, taken from the type its own data names. A feat that is both Skill and
    # General belongs under the more specific one, which the data lists first.
    #
    # Falls back to `charclass` for a feat whose data names no type at all, since a bucket named
    # `''` is one no heading on the sheet reads.
    def self.feat_bucket(details)
      types = Array((details || {})['feat_type']).map { |t| t.to_s.downcase }

      types.find { |t| FEAT_BUCKETS.include?(t) } || 'charclass'
    end

    # The same question asked by name, for callers holding a granted feat's name and not its data.
    def self.feat_bucket_for(name)
      feats = Global.read_config('pf2e_feats') || {}
      key = feats.keys.find { |k| k.to_s.casecmp?(name.to_s) }

      feat_bucket(key && feats[key])
    end

    # A list of granted feats, grouped by the heading each belongs under. What granted a feat has no
    # bearing on which heading it takes. Shield Block is a general feat however a class hands it
    # over.
    def self.bucket_feats(names)
      Array(names).each_with_object({}) do |name, grouped|
        next if name.blank?

        bucket = feat_bucket_for(name)
        grouped[bucket] = Array(grouped[bucket]) + [ name ]
      end
    end

    # Files a feat under a heading, in the draft, which is where a pick goes too.
    #
    # The sheet's own lists are the materialiser's output, so a feat written straight to pf2_feats
    # would be erased by the next fold. Both commit boundaries read the draft as well as the sheet,
    # so a feat recorded here is history at the same moment a chosen one is.
    def self.record_feat(char, bucket, fname)
      draft = char.pf2_advancement || {}
      feats = draft['feats'] || {}

      feats[bucket] = Array(feats[bucket]) + [ fname ]
      draft['feats'] = feats

      char.update(:pf2_advancement => draft)
    end

    # Takes a feat back out of wherever it is held. Both stores, because a draft holds what has been
    # picked and the sheet holds what a fold has already written.
    def self.forget_feat(char, fname)
      draft = char.pf2_advancement || {}
      feats = draft['feats'] || {}

      feats.each_key { |bucket| feats[bucket] = Array(feats[bucket]).reject { |f| f.to_s.casecmp?(fname.to_s) } }
      draft['feats'] = feats

      held = char.pf2_feats || {}
      held.each_key { |bucket| held[bucket] = Array(held[bucket]).reject { |f| f.to_s.casecmp?(fname.to_s) } }

      char.update(:pf2_advancement => draft)
      char.update(:pf2_feats => held)
    end

    def self.add_granted_feat(char, fname, details, charclass, client)
      record_feat(char, feat_bucket(details), fname)

      msgs = []
      msgs.concat(do_feat_grants(char, details['grants'], charclass, client)) if details['grants']
      msgs.concat(do_feat_magic_stats(char, details, charclass, client))
      apply_init_magic_feat(char, fname, details, client)

      msgs
    end

    def self.resolve_granted_choice(char, fname, details, label, client, filter = nil)
      block = feat_choice_def(details)
      return [] unless block
      return [] unless feat_choice_opens_at?(block, feat_taken_count(char, fname))

      to_assign = char.pf2_to_assign
      open_feat_choice(to_assign, fname)

      store_choice_filter(to_assign, fname, filter)
      char.update(pf2_to_assign: to_assign)

      option = label.blank? ? nil : match_choice_option(char, fname, block, label)

      unless option
        if label.present?
          Global.logger.error "Granted feat '#{fname}' names choice '#{label}', which is not an available option for #{char.name}."
        end

        return [ t('pf2e.choice_opened',
          :choice => fname,
          :summary => choice_summary(block),
          :cmd => choice_info_cmd(char)) ]
      end

      msgs = apply_feat_choice(char, fname, block, option, client)
      msgs << t('pf2e.choice_granted', :choice => fname, :value => option)

      msgs
    end

    # A choice resolved to a value, applied at whichever boundary is open. Chargen writes it to the
    # character now; an open level stages it for advance/done to carry out.
    def self.resolve_feat_choice(char, choice_name, block, value, client)
      if DraftSheet.of(char).drafting?
        stage_feat_choice(char, choice_name, block, value, client)
      else
        apply_feat_choice(char, choice_name, block, value, client)
      end
    end

    def self.apply_feat_choice(char, choice_name, block, value, client)
      msgs = []

      if choice_grants_feat?(block)
        feat = get_feat_details(value)
        return [ feat_lookup_failure(value, feat) ] if feat.is_a?(String)

        fname = feat[0]
        fdetails = feat[1]
        charclass = fdetails['assoc_charclass'] || char.pf2_base_info['charclass']

        record_feat(char, Array(fdetails['feat_type']).first.to_s.downcase, fname)

        msgs.concat(do_feat_grants(char, fdetails['grants'], charclass, client)) if fdetails['grants']
        msgs.concat(do_feat_magic_stats(char, fdetails, charclass, client))
        apply_init_magic_feat(char, fname, fdetails, client)

        nested = feat_choice_def(fdetails)
        nested = nil unless feat_choice_opens_at?(nested, feat_taken_count(char, fname))

        if nested
          nested_assign = char.pf2_to_assign
          open_feat_choice(nested_assign, fname)
          char.update(pf2_to_assign: nested_assign)

          msgs << t('pf2e.choice_opened', :choice => fname, :summary => choice_summary(nested), :cmd => choice_info_cmd(char))
        end

        value = fname
      else
        grants = choice_grants(char, block, value, choice_name)

        msgs.concat(do_feat_grants(char, grants, choice_caster_source(char, choice_name), client)) if grants
      end

      at_level_caught_up(choice_option_at_level(block, value), char.pf2_level).each do |lvl, payload|
        payload = substitute_choice_label(payload, value)

        msgs.concat(do_feat_grants(char, payload, char.pf2_base_info['charclass'], client))
        msgs << t('pf2e.choice_level_clause_applied', :choice => choice_name, :value => value, :level => lvl)
      end

      # Re-read, because do_feat_grants writes to_assign itself.
      to_assign = char.pf2_to_assign
      fill_feat_choice(to_assign, choice_name, value)
      char.update(pf2_to_assign: to_assign)

      record_choice(char, choice_name, value)

      msgs.concat(open_chained_choice(char, choice_name, block))

      msgs
    end

    # Advancement: staged into pf2_advancement, applied by do_advancement at advance/done.
    def self.stage_feat_choice(char, choice_name, block, value, client)
      msgs = []
      advancement = char.pf2_advancement
      to_assign = char.pf2_to_assign

      deferred = []

      if choice_grants_feat?(block)
        feat = get_feat_details(value)
        return [ feat_lookup_failure(value, feat) ] if feat.is_a?(String)

        fname = feat[0]
        fdetails = feat[1]

        # The same path a feat typed at advance/feat takes, so a feat handed over by a choice is
        # worth exactly what the same feat chosen directly is.
        gained = Advancement::FeatGain.apply(char, fname, fdetails,
          :bucket => Array(fdetails['feat_type']).first.to_s.downcase,
          :to_assign => to_assign,
          :advancement => advancement,
          :client => client)

        msgs.concat(Advancement::FeatGain.render(gained[:messages]))
        deferred.concat(gained[:after_save])

        value = fname
      else
        grants = choice_grants(char, block, value, choice_name)

        if grants
          adv_grants = advancement['grants'] || {}
          adv_grants["#{choice_name} (#{value})"] = grants
          advancement['grants'] = adv_grants
        end
      end

      new_level = char.pf2_level + 1

      at_level_caught_up(choice_option_at_level(block, value), new_level).each do |lvl, payload|
        adv_grants = advancement['grants'] || {}
        adv_grants["#{choice_name} (#{value}, level #{lvl})"] = substitute_choice_label(payload, value)
        advancement['grants'] = adv_grants

        msgs << t('pf2e.choice_level_clause_applied', :choice => choice_name, :value => value, :level => lvl)
      end

      fill_feat_choice(to_assign, choice_name, value)

      choices = to_assign['feat_choices'] || {}
      existing = Array(choices[choice_name])
      existing << value
      choices[choice_name] = existing.uniq
      to_assign['feat_choices'] = choices

      # The character holds this pick before the next step asks what it offers, since what a step
      # offers can depend on the pick before it.
      char.pf2_to_assign = to_assign

      msgs.concat(open_chained_choice(char, choice_name, block, to_assign))

      char.pf2_advancement = advancement
      char.pf2_to_assign = to_assign
      char.save

      # Work that had to wait for the draft to be written, such as staging a choice the gained
      # feat resolved by itself - that re-reads and saves the character.
      deferred.each { |run| msgs.concat(Advancement::FeatGain.render(run.call)) }

      msgs
    end

    def self.open_chained_choice(char, choice_name, block, to_assign = nil)
      nxt = block.is_a?(Hash) && block['then_choose']
      return [] unless nxt.is_a?(Hash)

      # A step that only some picks need - a bloodline's own 1st-level choice, which not every
      # bloodline has - is not opened when it has nothing to offer.
      return [] if nxt['skip_if_empty'] && choice_options(char, choice_name, nxt).empty?

      if to_assign
        open_feat_choice(to_assign, choice_name)
      else
        chained = char.pf2_to_assign
        open_feat_choice(chained, choice_name)
        char.update(pf2_to_assign: chained)
      end

      [ t('pf2e.choice_opened',
        :choice => choice_name,
        :summary => choice_summary(nxt),
        :cmd => choice_info_cmd(char)) ]
    end

  end
end
