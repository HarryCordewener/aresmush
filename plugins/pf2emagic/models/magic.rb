module AresMUSH
  class PF2Magic < Ohm::Model
    include ObjectModel

    # The focus pool is shared: PF2e gives a character one pool however many sources feed it. The
    # spells live on Pf2eSpellcastingEntry rows, one per focus type per granting source, because a
    # bucket per type cannot say whose the spells are.
    #
    # Only the points left are stored. The most the pool holds is counted from the spells, by
    # Pf2emagic.focus_pool_max.
    attribute :focus_pool, :type => DataType::Hash, :default => { "current"=>0 }
    # A list of grants rather than a map keyed by spell name, because two sources can grant the same
    # innate spell and a map holds only one of them. Charm comes from Enthralling Allure at rank 4
    # divine and Supernatural Charm at rank 1 arcane; Interplanar Teleport is divine from one source
    # and primal from another; and six sources grant an unchosen 'open' spell, so a single 'open' key
    # would hold one pick where the character has several.
    # Each grant is { 'name', 'level', 'tradition', 'cast_stat' }. Read it through
    # Pf2emagic::Entries, not directly.
    attribute :innate_spells, :type => DataType::Array, :default => []
    attribute :revelation_locked, :type => DataType::Boolean
    attribute :signature_spells, :type => DataType::Hash, :default => {}
    attribute :repertoire, :type => DataType::Hash, :default => {}
    attribute :spell_abil, :type => DataType::Hash, :default => {}
    attribute :spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_per_day, :type => DataType::Hash, :default => {}
    attribute :restricted_slots, :type => DataType::Hash, :default => {}
    attribute :restricted_spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_prepared, :type => DataType::Hash, :default => {}
    attribute :spells_today, :type => DataType::Hash, :default => {}
    attribute :adapted_spells, :type => DataType::Hash, :default => {}
    attribute :tradition, :type => DataType::Hash, :default => { "innate"=>["innate", "trained"] }
    attribute :prepared_lists, :type => DataType::Hash, :default => {}
    # class => { 'spell', 'rank', 'as' => signature | repertoire }: the spell picked from a book
    # (Esoteric Polymath, Arcane Evolution) at the last daily preparations. Cleared at the next.
    attribute :daily_pick, :type => DataType::Hash, :default => {}
    # class => [ { 'feat', 'rank', 'spells', 'cast', 'cast_rank' } ]: two spells prepared in one slot
    # (Split Slot, Spell Combination). Prepared like spells_prepared, and copied by a rest.
    attribute :slot_pairs, :type => DataType::Hash, :default => {}
    # class => { rank => spell }: the spells a feat keeps prepared at every rest, in slots of their
    # own (Spell Mastery).
    attribute :mastered_spells, :type => DataType::Hash, :default => {}
    # spell => { 'level', 'at' }: a failed Learn a Spell, which blocks trying that spell again.
    attribute :learn_failures, :type => DataType::Hash, :default => {}
    attribute :divine_font

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_magic_obj(char)
      char.magic
    end

    def self.get_create_magic_obj(char)
      obj = char.magic

      return obj if obj

      obj = PF2Magic.create(character: char)
      char.update(magic: obj)

      return obj
    end

    def self.assess_magic_stats(char, info)
      magic_stats = {}
      magic_options = {}

      info.each_pair do |key, value|
        case key
        when "innate_spell"
          # The entry itself belongs in magic_stats so update_magic grants the spell when the
          # advancement is committed. An 'open' name additionally needs a slot to choose it in, and
          # the stats entry is what advance/spell reads for the slot's rank and tradition.
          magic_stats["innate_spell"] = value.dup

          names = Array(value['name'])
          open_count = names.count { |n| n.to_s.downcase == 'open' }

          if open_count > 0
            level_key = value['level'].to_i.zero? || value['level'].to_s.downcase == 'cantrip' ? 'cantrip' : value['level'].to_s
            assignment_list = magic_options['innate'] || {}
            list = assignment_list[level_key] || []
            list.concat(Array.new(open_count, 'open'))
            assignment_list[level_key] = list
            magic_options['innate'] = assignment_list
          end
        when "repertoire"

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          magic_options["repertoire"] = assignment_list
        when "repertoire_each_rank"
          magic_options["repertoire"] = Pf2e.merge_spell_slots(magic_options["repertoire"],
            Pf2emagic.each_rank_picks(Pf2emagic.castable_rank(char), value))
        when "spellbook"
          assignment_list = magic_options["spellbook"] || {}

          if value.is_a?(Hash)
            value.each_pair do |level, num|
              assignment_list[level] = Array(assignment_list[level]) + Array.new(num, "open")
            end
          else
            key = Pf2emagic::ANY_RANK
            assignment_list[key] = Array(assignment_list[key]) + Array.new(value.to_i, "open")
          end

          magic_options["spellbook"] = assignment_list
        when "signature_spell", "signature_spells"
          # This key means that the character needs to pick a spell from their repertoire as a signature spell.
          # Structure of value: { level to pick from => number of spells to add }
          # Use to_assign["signature"]

          magic_stats["signature_spells"] = value

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          magic_options["signature"] = assignment_list
        else
          magic_stats[key] = value
        end
      end

      # Return a hash comprised of the two keys.
      hash = {}

      hash['magic_stats'] = magic_stats
      hash['magic_options'] = magic_options

      hash
    end

    # Every key update_magic understands. Named because a caller holding a magic_stats block has to
    # tell "a block of stats" from "a block keyed by class", and the only difference is whether its
    # keys are these. A key missing from this list makes a block of stats look class-keyed, and each
    # stat is then dispatched as if it were a class name.
    STAT_KEYS = %w{
      spell_abil tradition spells_per_day restricted_slots restricted_spellbook repertoire
      repertoire_each_rank addrepertoire choice_repertoire focus_spell
      domain_focus_spell focus_cantrip spellbook addspellbook adapted_spell signature_spell
      signature_spells innate_spell divine_font grant_choice gated_spell focus_source
    }.freeze

    def self.stats_block?(info)
      info.is_a?(Hash) && info.keys.all? { |key| STAT_KEYS.include?(key.to_s) }
    end

    def self.update_magic(char, charclass, info, client)
      magic = get_create_magic_obj(char)

      # Race condition with to_assign requires that to_assign be assembled and returned by the function for a merge.
      to_assign = {}

      info.each_pair do |key, value|
        case key
        when "spell_abil"
          spell_abil = magic.spell_abil
          spell_abil[charclass] = value
          magic.spell_abil = spell_abil

          Pf2emagic::Entries.grant_casting!(char, charclass, :ability => value)

        when "tradition"
          # The hash is still the register of which classes cast at all - Entries.derived reads
          # it to find them - so it is written as well as the row, until the spell lists move too.
          tradition = magic.tradition
          value.each_pair do |trad, prof|
            tradition[charclass] = [ trad, prof ]

            Pf2emagic::Entries.grant_casting!(char, charclass, :tradition => trad, :proficiency => prof)
          end

          magic.tradition = tradition
        when "spells_per_day"
          # Structure: { charclass => {"cantrip" => 5, 1 => 3, 2 => 1} }
          # This key grants spells per day.

          spells_per_day = magic.spells_per_day
          spd_for_class = spells_per_day[charclass] ? spells_per_day[charclass] : {}

          value.each_pair do |level, num|
            spd_for_class[level] = Pf2emagic.apply_stat_delta(spd_for_class[level], num)
          end

          spells_per_day[charclass] = spd_for_class

          magic.spells_per_day = spells_per_day
        when "restricted_slots", "restricted_spellbook"
          # Structure: { charclass => { restriction => { "cantrip" => 1, 1 => 1 } } }, for the
          # slots a restriction reserves per day and the spellbook entries it reserves. The two
          # differ only in which attribute they land in, so they share one branch.
          restricted = magic.send(key)
          for_class = restricted[charclass] || {}

          (value || {}).each_pair do |restriction, by_rank|
            existing = for_class[restriction] || {}

            (by_rank || {}).each_pair do |rank, num|
              existing[rank] = Pf2emagic.apply_stat_delta(existing[rank], num)
            end

            for_class[restriction] = existing
          end

          restricted[charclass] = for_class

          magic.send("#{key}=", restricted)
        when "repertoire"
          # Structure: { "cantrip" => 5, 1 => 3, 2 => 1 }
          # This key gets dumped into to_assign as repertoire and represents spells that need to be chosen
          # for the repertoire.

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["repertoire"] = assignment_list

        when "repertoire_each_rank"
          # One pick at each rank the character can cast. A level that opens a new rank later adds
          # the pick there, through Pf2e.open_each_rank_picks.
          to_assign["repertoire"] = Pf2e.merge_spell_slots(to_assign["repertoire"],
            Pf2emagic.each_rank_picks(Pf2emagic.castable_rank(char), value))

        when "addrepertoire"
          # This key is called for spells added to the repertoire by bloodlines, mysteries, etc.
          # Initial/advanced/greater bloodline spells are focus spells and handled by that key.
          # Expected structure of value: { <level> => <spell> }
          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass] || {}

          value.each_pair do |level, spell|
            list = rep_for_class[level] || []
            spell.each { |s| list << s }
            rep_for_class[level] = list
          end

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "choice_repertoire"
          # The gift spells a bloodline's 1st-level choice decides - a dragon exemplar's, an
          # elemental influence's - at the ranks listed. The bloodline names its table.
          gifts = Pf2emagic.choice_gift_spells(char, Array(value))
          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass] || {}

          gifts.each_pair do |rank, spells|
            rep_for_class[rank] = (Array(rep_for_class[rank]) + spells).uniq
          end

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "focus_spell", "domain_focus_spell", "focus_cantrip"
          # One spellcasting entry per focus type per granting source, so two sources of the same
          # type stay apart - they share PF2e's single focus pool but cast at their own DCs.
          # Cantrips and spells are the same entry under different keys, because they differ only
          # in how they are cast. A spell that is a cantrip is filed as one whichever key granted
          # it: a composition cantrip has a rank above 0, and costs nothing all the same.
          #
          # A block may name what granted it - "Domain Healing" for a cleric's domain spell -
          # and otherwise it is the class itself. Recorded with the level, so the sheet can say
          # where a focus spell came from without deriving it.
          source = info['focus_source'].presence || charclass

          # A pool that was full stays full as it grows; one with points spent keeps them spent.
          was_full = Pf2emagic.focus_points_left(magic) >= Pf2emagic.focus_pool_max(magic)

          value.each_pair do |fstype, spell_list|
            Array(spell_list).each do |spell|
              kind = key.to_s == 'focus_cantrip' || Pf2emagic.focus_cantrip?(spell) ? 'cantrip' : 'spell'

              Pf2emagic::Entries.grant_focus!(char, fstype, [ spell ],
                :kind => kind, :granted_by => source, :granted_at => char.pf2_level)
            end
          end

          magic.focus_pool = { 'current' => Pf2emagic.focus_pool_max(magic) } if was_full
        when "spellbook"
          # Spells need to be chosen, redirect to to_assign.

          assignment_list = to_assign["spellbook"] || {}

          if value.is_a?(Hash)
            value.each_pair do |level, num|
              assignment_list[level] = Array(assignment_list[level]) + Array.new(num, "open")
            end
          else
            key = Pf2emagic::ANY_RANK
            assignment_list[key] = Array(assignment_list[key]) + Array.new(value.to_i, "open")
          end

          to_assign["spellbook"] = assignment_list

        when "addspellbook"
          # Addspellbook means to add a specific spell to the spellbook. Adding spells to be chosen
          # should be the "spellbook" key.
          # Structure of value for addspell key: { level => [ spell ] }

          spellbook = magic.spellbook

          # Initialize spellbook for class if not already present.
          csb = spellbook[charclass] ? spellbook[charclass] : {}

          value.each do |level, spell_list|
            list = csb[level] ? csb[level] : []

            spell_list.each { |s| list << s }

            csb[level] = list
          end

          spellbook[charclass] = csb
          magic.spellbook = spellbook
        when "adapted_spell"
          # Structure: { "name" => spell, "tradition" => trad, "base_level" => n,
          #                       "source" => feat, "no_heighten" => bool }, or a list of them
          # for a feat that adds several spells at once (Fey Caller).
          adapted_class = Pf2emagic.get_caster_type(charclass) ? charclass : nil
          adapted = magic.adapted_spells

          (value.is_a?(Array) ? value : [ value ]).each do |entry|
            name = entry['name'].to_s
            next if name.empty?

            adapted[name] = {
              'tradition'  => entry['tradition'].to_s.downcase,
              'base_level' => entry['base_level'].to_i,
              'source'     => entry['source'],
              'class'      => adapted_class
            }
            adapted[name]['no_heighten'] = true if entry['no_heighten']
          end

          magic.adapted_spells = adapted
        when "signature_spell", "signature_spells"
          # This key means that the character needs to pick a spell from their repertoire as a signature spell.
          # Structure of value: { level to pick from => number of spells to add }
          # Use to_assign["signature"]

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["signature"] = assignment_list

        when "innate_spell"
          # One grant appended per spell, so two sources granting the same spell are two grants
          # rather than one overwriting the other. See the note on the attribute.
          grants = Array(magic.innate_spells)
          spell_data = value.reject { |k, _| k == 'name' }

          Array(value['name']).each do |spell_name|
            next if spell_name.nil? || spell_name.to_s.empty?

            grants = grants + [ spell_data.merge('name' => spell_name) ]
          end

          magic.innate_spells = grants
        when "divine_font"
          if value.size > 1

            to_assign['divine font'] = value
          else
            magic.update(divine_font: value.first)
          end
        when 'grant_choice'
          Array(value).compact.each { |name| Pf2e.open_feat_choice(to_assign, name.to_s) }
        when 'gated_spell'
          sublist_name = value + " spell"

          to_assign[sublist_name] = value
        when 'focus_source'
          # Not a stat of its own: it names what granted the focus spell in the same block, and
          # the focus_spell arm above reads it. Falling through to the else told a Champion
          # taking their devotion spell to go and inform staff.
          next
        else
          client.emit_ooc "Unknown key #{key} in update_magic. Please inform staff."
        end

      end

      magic.save
      char.save

      # The return of this function should be merged into pf2_to_assign.
      to_assign
    end

    # is_focus should be the focus spell type if given.
    def self.get_spell_dc(char, charclass, is_focus=false)
      caster_stats = Pf2emagic.get_caster_stats(char, charclass, is_focus)

      return 0 if caster_stats.is_a? String

      Pf2e::Stat.total(char, 'spell_dc', caster_stats)
    end

    def self.get_spell_abil(char, charclass, is_focus=false)
      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = Pf2emagic.get_focus_casting_stat(is_focus)
      else
        magic = char.magic
        spell_abil = magic.spell_abil[charclass]
      end

      spell_abil
    end

    def self.get_spell_attack_bonus(char, charclass, is_focus=false)
      caster_stats = Pf2emagic.get_caster_stats(char, charclass, is_focus)

      return 0 if caster_stats.is_a? String

      Pf2e::Stat.total(char, 'spell_attack', caster_stats)
    end

    def self.factory_default(char)

      magic = char.magic

      # Don't do anything unless magic is created.
      return nil unless magic

      (default_values || {}).each_pair do |attr, value|
        copy = value.is_a?(Hash) || value.is_a?(Array) ? Marshal.load(Marshal.dump(value)) : value
        magic.public_send("#{attr}=", copy)
      end

      # Attributes with no declared default that a reset should still clear.
      magic.divine_font = nil
      magic.revelation_locked = nil

      magic.save

    end

  end
end
