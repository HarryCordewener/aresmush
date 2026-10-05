module AresMUSH
  module Pf2e

    # p can be passed to this method as nil
    #
    # Whether a list of traits holds one, however it was written.
    #
    # The weapon catalogue writes them Title Case with parenthesised parameters (`Deadly (d8)`),
    # chargen writes an unarmed attack's lowercase, and a few are slugs. A reader that compares with
    # `include?` answers no for half the game's data.
    def self.has_trait?(traits, wanted)
      Array(traits).any? { |trait| trait.to_s.strip.casecmp?(wanted.to_s.strip) }
    end

    # Files a language in the draft, which is where a pick and a grant both go.
    #
    # `pf2_lang` is what the materialiser writes from the fold, and during a level-up it is the
    # levels already committed. A language written straight there is not part of the draft, so
    # `advance/reset` cannot take it back - which is how an abandoned advancement used to leave the
    # character a free language.
    def self.record_language(char, language)
      draft = char.pf2_advancement || {}
      held = Array(draft['languages'])

      return if held.any? { |l| l.to_s.casecmp?(language.to_s) }

      draft['languages'] = held + [ language ]

      char.update(:pf2_advancement => draft)
    end

    # Takes a language out of wherever it is held. Both stores, because a draft holds what has been
    # picked and the sheet holds what a fold has already written.
    def self.forget_language(char, language)
      draft = char.pf2_advancement || {}
      draft['languages'] = Array(draft['languages']).reject { |l| l.to_s.casecmp?(language.to_s) }

      char.update(:pf2_advancement => draft)
      char.update(:pf2_lang => Array(char.pf2_lang).reject { |l| l.to_s.casecmp?(language.to_s) })
    end

    # Is this character in chargen at all?
    #
    # `cg/start` sets chargen_stage to 0, which is page zero of the walkthrough and means they
    # have started. Testing `.zero?` read that as "not started", so the command the error told
    # them to run put them in the state the error complained about, and the only way forward was
    # cg/next. The base chargen plugin has always tested for nil; this matches it.
    def self.in_chargen?(char)
      !char.chargen_stage.nil?
    end

    PROF_BONUS = { "untrained" => 0, "trained" => 2, "expert" => 4,
                   "master" => 6, "legendary" => 8 }.freeze

    def self.get_prof_bonus(char, p="untrained")
      p = "untrained" if p.to_s.strip.empty?

      # A rank spelled some way this does not know would otherwise be `nil + level`. Untrained is the
      # safe reading, and the log says so rather than leaving a figure quietly short.
      unless PROF_BONUS.key?(p)
        Global.logger.warn "PF2e read a proficiency rank of #{p.inspect}, which is none of #{PROF_BONUS.keys.join(', ')}; treating as untrained."
        p = "untrained"
      end

      if p == "untrained" && Pf2e.has_feat?(char, "Untrained Improvisation")
        return untrained_improv_bonus(char.pf2_level)
      end

      PROF_BONUS[p] + ((p == "untrained") ? 0 : char.pf2_level)
    end

    # Untrained Improvisation: level - 2, improving to level - 1 at 5th and full level at 7th.
    def self.untrained_improv_bonus(level)
      return level if level >= 7

      step = level >= 5 ? 1 : 2

      [ level - step, 0 ].max
    end

    # The six abilities, and every word that names one: the full name and the three-letter
    # shorthand players actually type.
    ABILITIES = %w(Strength Dexterity Constitution Intelligence Wisdom Charisma).freeze

    ABILITY_BY_WORD = ABILITIES.each_with_object({}) { |ability, words|
      words[ability.downcase] = ability
      words[ability[0, 3].downcase] = ability
    }.freeze

    # The ability a save, an attack kind or perception is rolled off. PF2e fixes all of these, so
    # this is a register to look things up in.
    LINKED_ABILITY = {
      'fort' => 'Constitution', 'fortitude' => 'Constitution',
      'ref' => 'Dexterity', 'reflex' => 'Dexterity', 'ranged' => 'Dexterity', 'finesse' => 'Dexterity',
      'will' => 'Wisdom', 'perception' => 'Wisdom',
      'melee' => 'Strength'
    }.freeze

    SAVES = %w(will fort fortitude ref reflex).freeze

    # A save under one name, whichever of its names was typed. Both spellings reach the same statistic,
    # so both have to reach the same domain - a condition that penalises Fortitude cannot depend on
    # whether the caller wrote `fort`.
    CANONICAL_SAVE = { 'fort' => 'fortitude', 'fortitude' => 'fortitude',
                       'ref' => 'reflex', 'reflex' => 'reflex', 'will' => 'will' }.freeze

    def self.canonical_save(name)
      CANONICAL_SAVE[name.to_s.strip.downcase] || name
    end

    # An attack keyword names which ability the attack uses. The bonus comes from the weapon, so the
    # keyword itself adds nothing to a roll.
    ATTACK_KINDS = %w(melee ranged unarmed finesse).freeze

    # The ability modifier behind a value, for a roll that looks one up instead of adding it. `type`
    # says how to read `value`: a skill's linked ability, a lore's Intelligence, or, when no type is
    # given, a save or attack keyword.
    def self.get_linked_attr_mod(char, value, type=nil)
      ability = case type.to_s.downcase
                when 'skill' then Pf2eSkills.get_linked_attr(value)
                when 'lore'  then 'Intelligence'
                when ''      then LINKED_ABILITY[value.to_s.downcase]
                end

      return nil unless ability

      ability_mod(char, ability)
    end

    # The land speed the ancestry sets, which is what armour and conditions modify.
    def self.ancestry_speed(char)
      (char.pf2_movement || {})['base_speed'].to_i
    end

    def self.ability_mod(char, ability)
      Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, ability))
    end

    # A word in a roll string, and how to turn it into a number.
    #
    # Rows are tried in order and the last one matches anything, so a word this does not recognise
    # is looked up as a skill and otherwise contributes nothing. Adding a keyword is adding a row.
    #
    # A row may return an array of individual dice, which `parse_roll_string` shows in brackets
    # and flattens into the total. Sneak attack does; that is deliberate.
    #
    # `options` are what the roller said they are doing - `action:pick-a-lock` and the like - which is
    # what a conditional bonus is tested against. A row that reads no figure ignores them.
    KEYWORDS = [
      {
        'name' => 'shenanigans',
        'match' => lambda { |word| word == 'shenanigans' },
        'value' => lambda { |_char, _word, _options| Pf2e.shenanigans }
      },
      {
        'name' => 'save',
        'match' => lambda { |word| SAVES.include?(word) },
        'value' => lambda { |char, word, options| Check.of(char, 'save', word, options) }
      },
      {
        'name' => 'perception',
        'match' => lambda { |word| word == 'perception' },
        'value' => lambda { |char, _word, options| Check.of(char, 'perception', nil, options) }
      },
      {
        'name' => 'attack',
        'match' => lambda { |word| ATTACK_KINDS.include?(word) },
        'value' => lambda { |_char, _word, _options| 0 }
      },
      {
        'name' => 'ability',
        'match' => lambda { |word| ABILITY_BY_WORD.key?(word) },
        'value' => lambda { |char, word, _options| Pf2e.ability_mod(char, ABILITY_BY_WORD[word]) }
      },
      {
        'name' => 'sneak attack',
        'match' => lambda { |word| word == 'sneak attack' },
        'value' => lambda { |char, _word, _options| Pf2e.sneak_attack_dice(char) }
      },
      {
        'name' => 'skill',
        'match' => lambda { |_word| true },
        'value' => lambda { |char, word, options| Pf2e.skill_keyword_bonus(char, word, options) }
      }
    ].freeze

    # A word that names a check answers with the check rather than a number, so the roll can ask it what
    # it is worth *and* what changes its outcome. `collect` is where the check itself goes; a caller that
    # only wants the number leaves it out.
    #
    # The check rather than its adjustments, because some of them depend on how the die came up: a keen
    # weapon turns a natural 19 into a critical hit, and that is not knowable until it is rolled.
    def self.get_keyword_value(char, word, options = [], collect = nil)
      downcased = word.to_s.downcase
      keyword = KEYWORDS.find { |k| k['match'].call(downcased) }

      held = keyword['value'].call(char, downcased, options)

      # Asked for what it can do rather than what it is: a keyword may answer with a number, with several
      # dice, or with a check.
      return held unless held.respond_to?(:total) && held.respond_to?(:adjustments)

      collect&.push(held)

      held.total
    end

    # The terms of a roll string: `athletics-2` is athletics and minus two.
    def self.roll_terms(string)
      string.to_s.gsub('-', '+-').gsub('--', '-').split('+').map(&:strip).reject(&:empty?)
    end

    # What a player said they were doing, as the options a predicate is tested against.
    #
    # Foundry spells an action `action:pick-a-lock` and a circumstance that is not an action as a bare
    # word - `visual` for a check that needs sight. A player should not have to know which, so a named
    # circumstance is offered as both.
    #
    # A word already spelled as one of their options - `substitute:assurance`, `map:increases:1` - is
    # taken as that option, each part slugged, because that is what it is.
    def self.circumstances(words)
      Array(words).flat_map do |word|
        parts = word.to_s.strip.downcase.split(':').map { |part| part.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '') }

        next [ parts.join(':') ] if parts.size > 1 && parts.none?(&:empty?)

        slug = parts.join('-')

        slug.empty? ? [] : [ slug, "action:#{slug}" ]
      end
    end

    # A joke roll: some number of some die, as often negative as not.
    def self.shenanigans
      sides = [ 2, 3, 4, 6, 8, 10, 12, 20, 30, 100, 1000 ].sample
      roll = Pf2e.roll_dice(rand(1..50), sides).sum

      Time.now.to_i.odd? ? roll : -roll
    end

    def self.sneak_attack_dice(char)
      dice = char.combat&.sneak_attack
      return 0 if !dice

      amount, sides = dice.gsub("d", " ").split

      Pf2e.roll_dice(amount.to_i, sides.to_i)
    end

    # A skill term in a roll string is a check rather than a figure, so it carries the circumstances a
    # check establishes: that it is a skill check, and which skill. Deafened's own rule is predicated on
    # exactly those.
    def self.skill_keyword_bonus(char, word, options = [])
      name = word.capitalize
      return 0 unless Global.read_config('pf2e_skills').keys.include?(name)

      Check.of(char, Pf2eSkills.lore?(name) ? 'lore' : 'skill', name, options)
    end

    def self.roll_dice(amount=1, sides=20)
      amount.to_i.times.collect { |t| rand(1..sides.to_i) }
    end

    def self.character_has?(array, element)
      array.include?(element)
    end

    def self.character_has_index?(array, element)
      if array.member?(element)
        return array.index(element)
      else
        return false
      end
    end

    def self.get_level_tier(level)
      1 + ((level - 1) / 4)
    end

    # `options` are the circumstances the roller named, which is what a conditional bonus is tested
    # against. They add no number of their own: they decide whether a figure counts a bonus it holds.
    def self.parse_roll_string(target, list, options = [])
      aliases = target.pf2_roll_aliases
      roll_list = list.map { |word|
        aliases.has_key?(word) ? Pf2e.roll_terms(aliases[word]) : word
      }.flatten

      dice_pattern = /([0-9]+)d[0-9]+/i
      find_dice = roll_list.select { |d| d =~ dice_pattern }

      roll_list.unshift('1d20') if find_dice.empty?

      # The words are worked out before any die is rolled, because what they are can change how the d20
      # is rolled: fortune rolls it twice and keeps the higher.
      checks = []
      terms = roll_list.map do |e|
        if e =~ dice_pattern
          nil
        elsif e.to_i == 0
          Pf2e.get_keyword_value(target, e, options, checks)
        else
          e.to_i
        end
      end

      # A roll opening with a d20 is a check, and its d20 is rolled the way any check's is. A
      # substitution is a number rather than a die, so it takes the die's place, with no natural 20 or 1.
      d20 = roll_list.first == '1d20' ? Resolve.d20(checks) : nil

      if d20 && d20['substitution']
        roll_list[0] = d20['face'].to_s
        terms[0] = d20['face']
      end

      result = roll_list.each_with_index.map do |e, index|
        next terms[index] unless e =~ dice_pattern
        next [ d20['face'] ] if d20 && index.zero?

        dice = e.gsub("d"," ").split
        amount = dice[0].to_i > 0 ? dice[0].to_i : 1
        sides = dice[1].to_i

        Pf2e.roll_dice(amount, sides)
      end

      fmt_result = result.map do |word|
        if word.is_a? Array
          fmt_word = word.map { |w| "%xc#{w}%xn" }
          "(" + fmt_word.join(" ") + ")"
        else
          word
        end
      end

      return_hash = {}
      return_hash['list'] = roll_list
      return_hash['result'] = fmt_result
      return_hash['total'] = result.flatten.sum
      return_hash['options'] = options
      # The statistics rolled, which is what the outcome is theirs to change through. Kept as the checks
      # themselves so a rule about how the die came up can be asked once the die is known.
      return_hash['checks'] = checks
      return_hash['adjustments'] = checks.flat_map(&:adjustments)
      # Both dice, where the d20 was rolled twice, and which was kept.
      return_hash['rolled_twice'] = d20 && d20['kept'] ? { 'keep' => d20['kept'], 'rolls' => d20['dice'] } : nil
      # The natural face of the d20, which shifts the outcome a degree either way.
      return_hash['die'] = d20 && d20['die']

      # What the roll spent is spent: Guidance's bonus, a fortune effect.
      checks.each { |check| check.rolled!(return_hash['total'], nil, return_hash['die']) if check.respond_to?(:rolled!) }

      return return_hash
    end

    # How the roll is shown. The outcome itself is `Pf2e::Degree`'s, so anything that has to change an
    # outcome works on a number rather than on a coloured string.
    DEGREE_LABELS = [ "(%xrCRITICAL FAILURE%xn)",
                      "(%xh%xyFAILURE%xn)",
                      "(%xgSUCCESS!%xn)",
                      "(%xh%xmCRITICAL SUCCESS!%xn)" ].freeze

    # How a parsed roll went against a DC, as the roll commands show it. The outcome is `Resolve`'s, the
    # same one an encounter's checks come to.
    def self.roll_degree(roll, dc)
      degree_label(Resolve.degree(roll['checks'], roll['total'], dc, roll['die']), roll['die'])
    end

    def self.degree_label(degree, die = nil)
      DEGREE_LABELS[degree] + (die == 1 ? t('pf2e.whirldice') : "")
    end

    # A check's degree of success as a number, for a caller that rolled its own dice: 0 critical failure
    # to 3 critical success, with a natural 20 or 1 moving it a degree. `natural` is nil where the roll
    # was not a d20.
    def self.degree_index(natural, total, dc)
      Degree.of(total, dc, natural)
    end

    def self.pretty_string(string)
      string.split.map { |w| w.capitalize }.join(" ")
    end

    # Fronts a noun phrase with 'a' or 'an' so it can be dropped into a sentence.
    ARTICLE_DETERMINERS = %w(a an the your our their his her its this that these those one any each every some no)

    def self.with_article(phrase)
      text = phrase.to_s.strip

      return text if text.empty?
      return text if ARTICLE_DETERMINERS.include?(text.split.first.to_s.downcase)
      return text if text =~ /\A[A-Z]/

      text =~ /\A[aeiou8]/i ? "an #{text}" : "a #{text}"
    end

    # The one door for moving a character's XP, in either direction. Negative spends.
    #
    # It records the transaction and moves the running total together, so there is no separate
    # history call for a caller to forget.
    def self.award_xp(target, amount, awarded_by = 'System', reason = nil, ref = nil)
      Pf2e::Audit.post(target, 'xp', amount, :by => awarded_by, :reason => reason, :ref => ref)
    end

    def self.is_proficient?(char, category, name)

      return true if char.is_admin?

      case category
      when "weapons"
        prof = Pf2eCombat.get_weapon_prof(char, name)
      when "armor"
        prof = Pf2eCombat.get_armor_prof(char, name)
      else
        prof = 'untrained'
      end

      return false if !prof || prof == 'untrained'
      return true
    end

    # The highest proficiency rank in the list.
    def self.select_best_prof(array)
      profs = %w{untrained trained expert master legendary}

      array.compact.max_by { |a| profs.index(a.to_s) || -1 } || 'untrained'
    end

    def self.cannot_respec(char)
      msg = []

      # Characters cannot respec if they're in any scenes still in progress, because they will be unapproved
      # in the process of the respec.
      open_scenes = Scene.all.select { |s| s.completed && (s.participants.include?(char) || s.owner == char) }

      msg << t('pf2e.respec_refused_scenes') unless open_scenes.empty?

      # Only approved characters can respec, otherwise just reset.

      msg << t('pf2e.respec_refused_approval') unless char.is_approved?

      return msg unless msg.empty?
      return nil
    end

    # A blank sheet, attribute by attribute. Both ways of starting a character over write this;
    # which of them is running decides only what is *kept*, so there is one list of what a blank
    # character looks like rather than two that drift apart.
    BLANK_SHEET = {
      :chargen_stage => 0,
      :pf2_baseinfo_locked => false,
      :pf2_abilities_locked => false,
      :pf2_skills_locked => false,
      :pf2_checkpoint => 'start',
      :pf2_reset => false,
      :pf2_base_info => { 'ancestry' => '', 'heritage' => '', 'background' => '', 'charclass' => '', 'specialize' => '' },
      :pf2_archetypeinfo => {
        'archetype1' => '', 'archetype2' => '', 'archetype3' => '', 'archetype4' => '',
        'archetype_specialty1' => '', 'archetype_specialty2' => '', 'archetype_specialty3' => '', 'archetype_specialty4' => '',
        'archetype_specialty_choice1' => '', 'archetype_specialty_choice2' => '',
        'archetype_specialty_choice3' => '', 'archetype_specialty_choice4' => ''
      },
      :pf2_conditions => {},
      :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] },
      :pf2_traits => [],
      :pf2_feats => { 'ancestry' => [], 'charclass' => [], 'skill' => [], 'general' => [] },
      :pf2_faith => { 'deity' => '', 'alignment' => '', 'sanctification' => '' },
      :pf2_special => [],
      :pf2_boosts_working => { 'free' => [], 'ancestry' => [], 'background' => [], 'charclass' => [] },
      :pf2_boosts => {},
      :pf2_to_assign => {},
      :pf2_advancement => {},
      :pf2_lang => [],
      :pf2_movement => {},
      :pf2_reagents => {},
      :pf2_formula_book => {},
      :advancing => nil,
      :pf2_level_tracker => {},
      :pf2_size => '',
      :pf2_roll_aliases => {},
      :pf2_actions => {},
      :pf2_is_dead => nil,
      :pf2_known_for => [],
      :pf2_alloc_reagents => 0,
      :groups => {},
      :demographics => {}
    }.freeze

    # What a character earned rather than built. A respec keeps these; a reset does not.
    EARNED = {
      :pf2_xp => 0,
      :pf2_level => 1,
      :pf2_viewsheet => {}
    }.freeze

    # A respec: the character keeps their level, XP, money and inventory, and rebuilds everything
    # they chose. Their recorded build goes, because a ledger they are about to contradict would
    # be folded back over the blank sheet at the first write.
    def self.respec_character(char)
      blank_sheet!(char)
      Pf2egear.reset_gear(char, true) if AresMUSH.const_defined?('Pf2egear')
      char.save
    end

    # A reset: back to the very beginning, including the XP and money they were given.
    def self.reset_character(char)
      blank_sheet!(char)

      EARNED.each_pair { |attr, value| char.send("#{attr}=", value) }
      Pf2e::Audit.delete_all!(char, 'xp')

      Pf2egear.reset_gear(char) if AresMUSH.const_defined?('Pf2egear')
      char.save
    end

    def self.blank_sheet!(char)
      if char.is_approved?
        char.update(approval_job: nil)
        char.update(chargen_locked: false)
        Roles.remove_role(char, 'approved')
      end

      # The grants first. A character with grants is finalized, so until they are gone the
      # character is not back in a draft: chargen commands would write history instead of a
      # working copy, and the next materialise would restore the sheet being cleared here.
      Ledger.delete_all!(char)
      DraftJournal.clear!(char)
      Checkpoints.clear!(char)

      BLANK_SHEET.each_pair { |attr, value| char.send("#{attr}=", value) }

      # Every character has all of these except magic, so they are reset in place rather than
      # deleted and rebuilt.
      Pf2eAbilities.factory_default(char)
      Pf2eSkills.factory_default(char)
      Pf2eHP.factory_default(char)
      Pf2eCombat.factory_default(char)
      PF2Magic.factory_default(char)
    end

    def self.get_character(name, enactor)
      # To keep from doing this repeatedly.

      return enactor unless name

      result = ClassTargetFinder.find(name, Character, enactor)
      if (result.found?)
        return result.target
      else
        return nil
      end
    end

    def self.update_reagents(char, info, cleanup=false)

      reagents = char.pf2_reagents

      if cleanup
        info.each_pair do |k,v|
          reagents.delete[k]
        end
      else
        info.each_pair do |k,v|
          reagents[k] = v
        end
      end

      char.update(pf2_reagents: reagents)

    end

    def self.treat_as_charclass?(char, charclass)
    # Determine whether a class' features apply to this character.
      charclass = charclass.upcase
    
      return true if char.pf2_base_info['charclass'].upcase == charclass
      return false
    end

    def self.easter_scrub(ary)
      # Scrubs Easter egg options out of any array.
      # Use for option output to players.

      return ary unless ary.is_a? Array

      scrubs = Global.read_config('pf2e', 'hidden_options') || []

      ary - scrubs
    end

    # The line under a page footer that says how to see the next page, built from the command as
    # dispatched: 'skills/lore city' on page 1 gives 'skills/lore2 city'. Shortcuts have already
    # been applied by then, so a player's shortcut comes back as the full command, which still
    # works. Nil on the last page, or when everything fits on one.
    def self.next_page_hint(cmd, paginator)
      return nil unless cmd && paginator
      return nil unless paginator.current_page < paginator.total_pages

      page = paginator.current_page + 1
      command = "#{cmd.prefix}#{cmd.root}"
      command << (cmd.switch ? "/#{cmd.switch}#{page}" : page.to_s)
      command << " #{cmd.args}" unless cmd.args.to_s.strip.empty?

      t('pf2e.next_page_hint', :command => command)
    end

  end
end
