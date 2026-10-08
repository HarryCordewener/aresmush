module AresMUSH
  module Pf2e

    # Plays an encounter the way a GM and a party of players would: every step is a command one of them
    # types, read back through what the game told them. It records each thing a player tried - a Strike
    # with each weapon they carry, each action their feats and features give them, each spell they can
    # cast, each item they can use - and what came of it, so a scenario's report says what a character
    # of that class and level could and could not do.
    #
    # The room's and the GM's messages are written to the transcript by whoever drives the runner, which
    # stubs the emitters (`#heard`).
    class ScenarioRunner
      include InteractionProbes

      # One player's seat: the character's class and origin, and what they carry.
      #
      #   kit: { 'weapons' => [ 'Longsword' ], 'armor' => 'Full Plate', 'shields' => 'Steel Shield',
      #          'consumables' => [ [ 'Healing Potion (Minor)', 2 ] ],
      #          'runes' => { 'potency' => 1, 'striking' => 1, 'resilient' => 0, 'armor_potency' => 1,
      #                       'property' => [ 'Flaming' ] },
      #          'alchemy' => [ 'Alchemist's Fire (Lesser)' ] }
      Seat = Struct.new(:charclass, :ancestry, :heritage, :background, :kit, keyword_init: true)

      # What one command did: who typed it, what they typed, what they were told, and anything it raised.
      Outcome = Struct.new(:who, :text, :said, :failures, :error, keyword_init: true) do
        def ok?
          failures.empty? && error.nil?
        end

        def status
          return "ERROR #{error.class}: #{error.message}" if error
          return "refused: #{failures.join(' / ')}" unless failures.empty?

          'ok'
        end
      end

      # A thing a player tried, by kind, and how it went.
      Try = Struct.new(:who, :kind, :what, :text, :outcome, keyword_init: true)

      MUSH_CODES = /%x[a-zA-Z]|%x\d+|%c[a-zA-Z]|%l[a-z]|%n|%t|%b/

      attr_reader :name, :level, :seats, :waves, :lines, :tries, :outcomes, :party, :gm, :encounters,
                  :build_notes, :audit, :probes

      def initialize(name, level:, seats:, waves:, rounds: 6)
        @name = name
        @level = level
        @seats = seats
        @waves = waves
        @rounds = rounds
        @lines = []
        @tries = []
        @outcomes = []
        @party = []
        @encounters = []
        @build_notes = {}
        @tried = Hash.new { |h, k| h[k] = {} }
        @audit = RollAudit.new
        @probes = []
      end

      # ------------------------------------------------------------------------------
      # The transcript

      # What leaks the engine's insides into what a player reads.
      LEAKS = /Translation missing|=>|%\{|#<[A-Z]|undefined method|\bnil\b/

      def heard(message, to = nil)
        text = clean(message)

        return if text.empty?

        @audit.find('wording', to ? "told #{to}" : 'told the room', text[0, 200]) if text.match?(LEAKS)

        @lines << (to ? "    [to #{to}] #{text}" : "    #{text}")
      end

      def clean(message)
        message.to_s.gsub(MUSH_CODES, '').gsub('%r', "\n      ").gsub(/%R/, "\n      ").strip
      end

      def say(text)
        @lines << text
      end

      # ------------------------------------------------------------------------------
      # Typing a command

      def type(char, text)
        client = AutoBuilder::CaptureClient.new
        cmd = Command.new(text)
        enactor = Character[char.id]
        handler = AutoBuilder::PLUGINS.lazy.map { |plugin|
          (AresMUSH.const_get(plugin).get_cmd_handler(client, cmd, enactor) rescue nil)
        }.find { |found| found }
        error = nil

        say "  > #{enactor.name}: #{text}"

        begin
          raise "no command answers #{text}" unless handler

          handler.new(client, cmd, enactor).on_command
        rescue StandardError => e
          error = e
        end

        (client.successes + client.oocs).each { |line| heard(line, enactor.name) }
        client.failures.each do |line|
          @lines << "    !! #{clean(line)}"
          @audit.find('wording', "#{enactor.name}: #{text}", clean(line)[0, 200]) if clean(line).match?(LEAKS)
        end
        @lines << "    ** #{error.class}: #{error.message} (#{error.backtrace&.first})" if error

        outcome = Outcome.new(:who => enactor.name, :text => text, :said => client.successes + client.oocs,
                              :failures => client.failures.map { |line| clean(line) }, :error => error)
        @outcomes << outcome
        outcome
      end

      def attempt(char, kind, what, text)
        outcome = type(char, text)

        @tries << Try.new(:who => char.name, :kind => kind, :what => what, :text => text, :outcome => outcome)
        @tried[char.id][[ kind, what ]] = outcome
        @audit.safely("#{char.name}: #{text}") { spell_outcome!(char, text) } if outcome.ok? && text.start_with?('e/cast')
        outcome
      end

      # ------------------------------------------------------------------------------
      # Before the fight

      def stage!
        @room = Room.create(:name => "#{@name} Hall #{rand(1000000)}")
        @scene = Scene.create(:room => @room, :title => @name)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        Roles.add_role(@gm, 'approved')
        @gm = Character[@gm.id]

        say "# #{@name}: a party of #{@seats.size} at level #{@level}"
        say ''
      end

      def gm_name
        @gm.name
      end

      def build_party!
        @seats.each_with_index do |seat, i|
          char = Character.create(:name => "#{seat.charclass}#{@level}x#{rand(100000)}", :room => @room)
          builder = AutoBuilder.new(char)

          builder.build_level_one(seat.charclass, ancestry: seat.ancestry, heritage: seat.heritage,
                                                  background: seat.background)
          builder.advance_to(@level)

          char = Character[char.id]
          @build_notes[char.name] = builder.notes.select { |note| note.start_with?('!!', '??', 'level') }
          @party << char
          Scene[@scene.id].participants.add(char)

          say "## #{char.name}: level #{char.pf2_level} #{char.pf2_base_info['ancestry']} " \
              "(#{char.pf2_base_info['heritage']}) #{seat.charclass}, #{char.pf2_base_info['background']}"
          say "  feats: #{(char.pf2_feats || {}).values.flatten.join(', ')}"
          choices = (char.pf2_level_tracker || {}).values.map { |entry| entry['feat_choices'] }.compact.reduce({}, :merge)
          say "  feat choices: #{choices.map { |feat, choice| "#{feat}: #{Array(choice).join('/')}" }.join(', ')}" unless choices.empty?
          say "  build notes: #{@build_notes[char.name].join(' | ')}" unless @build_notes[char.name].empty?
        end

        say ''
      end

      # A kit is what the character would choose, so one they are untrained in is the scenario's mistake.
      def wear!(char, text)
        untrained = type(char, text).said.map { |line| clean(line) }.find { |line| line.start_with?('You are untrained') }

        @audit.find('kit', "#{char.name}: #{text}", untrained) if untrained
      end

      # Money to spend, then the kit: bought, worn and wielded by the player, its runes etched by staff.
      def outfit!
        say '## Outfitting'

        @party.each_with_index do |char, i|
          kit = @seats[i].kit || {}

          Pf2egear.pay_player(char, 50_000_000, 'Scenario', 'Starting wealth')

          Array(kit['weapons']).each { |weapon| type(char, "buy weapons=#{weapon}") }
          type(char, "buy armor=#{kit['armor']}") if kit['armor']
          type(char, "buy shields=#{kit['shields']}") if kit['shields']
          Array(kit['consumables']).each { |item, count| type(char, "buy consumables=#{item}/#{count || 1}") }

          Array(kit['weapons']).each_index { |n| wear!(char, "equip weapons=#{n}") }
          wear!(char, 'equip armor=0') if kit['armor']
          type(char, 'equip shields=0') if kit['shields']

          etch!(char, kit['runes'] || {}, Array(kit['weapons']).size, kit['armor'])
          prepare_spells!(char)
          prepare_alchemy!(char, Array(kit['alchemy']))
          type(char, 'gear')
        end

        say ''
      end

      def etch!(char, runes, weapons, armor)
        weapons.times do |n|
          type(@gm, "etch/potency #{char.name}=weapons/#{n}/#{runes['potency']}") if runes['potency'].to_i > 0
          type(@gm, "etch/striking #{char.name}=weapons/#{n}/#{runes['striking']}") if runes['striking'].to_i > 0
          Array(runes['property']).each { |rune| type(@gm, "etch/property #{char.name}=weapons/#{n}/#{rune}") }
        end

        return unless armor

        type(@gm, "etch/potency #{char.name}=armor/0/#{runes['armor_potency']}") if runes['armor_potency'].to_i > 0
        type(@gm, "etch/resilient #{char.name}=armor/0/#{runes['resilient']}") if runes['resilient'].to_i > 0
      end

      # A prepared caster fills every slot they have, with spells that do something in a fight first.
      def prepare_spells!(char)
        magic = Character[char.id].magic

        return unless magic

        (magic.tradition || {}).keys.reject { |key| key == 'innate' }.each do |charclass|
          next unless Pf2emagic.get_caster_type(charclass) == 'prepared'

          (magic.spells_per_day[charclass] || {}).each_pair do |rank, count|
            candidates = preparable(char, charclass, rank)
            filled = 0

            candidates.each do |spell|
              break if filled >= count.to_i

              filled += 1 if type(char, "prepare #{charclass}/#{rank.to_s == 'cantrip' ? 0 : rank}=#{spell}").ok?
            end
          end
        end

        type(char, 'prepared')
      end

      def preparable(char, charclass, rank)
        char = Character[char.id]
        known = Pf2emagic::Entries.known_lists(char)[charclass]
        pool = if known && !known.empty?
                 Array(known[rank.to_s])
               else
                 AutoBuilder.new(char).spell_pool(rank.to_s == 'cantrip' ? 'cantrip' : rank.to_i, charclass)
               end

        # Two of each where a list is short, so a rank's every slot is filled.
        ordered = pool.sort_by { |spell| fighting?(spell) ? 0 : 1 }
        ordered + ordered
      end

      def fighting?(spell)
        mechanics = Global.read_config('pf2e_spell_mechanics', spell) || {}

        %w{save attack damage outcomes}.any? { |key| mechanics.key?(key) } || healing?(spell)
      end

      def healing?(spell)
        traits = Array((Global.read_config('pf2e_spells', spell) || {})['traits'])

        traits.include?('healing')
      end

      def prepare_alchemy!(char, items)
        return if items.empty?

        items.each do |item|
          type(@gm, "formulas/add #{char.name}=consumables/#{item}")
          type(char, "alchemy/prepare #{item}/2")
        end

        type(char, 'alchemy')
      end

      # ------------------------------------------------------------------------------
      # The fight

      def encounter
        @encounter && PF2Encounter[@encounter.id]
      end

      def fight!(wave, carries_on: nil)
        @wave = wave
        say "## Encounter: #{wave.map { |count, creature| "#{count} #{creature}" }.join(', ')}"

        type(@gm, carries_on ? "encounter =#{carries_on.id}" : 'encounter')
        @encounter = PF2Encounter.scene_active_encounter(Scene[@scene.id])

        raise "#{@name}: the GM could not start an encounter" unless @encounter

        @encounters << @encounter

        @party.each { |char| type(char, 'e/join') }
        type(@gm, 'e/rest') unless carries_on
        wave.each { |count, creature| type(@gm, "e/add #{count} #{creature}") }
        type(@gm, 'e/view')
        type(@gm, 'e/next')
        interactions!

        @rounds.times do |round|
          break if foes.empty?

          say "### Round #{round + 1}"
          order_size = Combatants.rows(encounter).size

          order_size.times do
            ending = frightened_before_turn_ends
            heard_before = @lines.size
            type(@gm, 'e/next')
            @audit.safely('frightened easing') { frightened_eased!(ending) }
            @audit.safely('recovery check') { recovery_rolled!(@lines[heard_before..]) }
            break if foes.empty?

            act_on_turn
          end

          rescue_the_fallen
        end

        type(@gm, 'e/history')
        type(@gm, 'e/undo')
        type(@gm, 'e/redo')
        type(@gm, 'e/award')
        @party.each { |char| type(@gm, "e/award #{encounter.id}=#{char.name}=80/10 gp") }
        type(@gm, "encounter/end #{encounter.id}")

        say ''
        @encounter
      end

      def act_on_turn
        name = ActiveEffects.current_turn(encounter)
        row = Combatants.rows(encounter).find { |one| one['name'] == name }

        return unless row

        if row['npc']
          creature_turn(row) if Pf2eNpc[row['npc']]&.hp_left.to_i.positive?
        elsif row['char']
          player_turn(Character[row['char']])
        end
      end

      def foes
        Combatants.rows(encounter).select { |row| row['npc'] && Pf2eNpc[row['npc']] && Pf2eNpc[row['npc']].hp_left > 0 }
      end

      def foe
        foes.min_by { |row| Pf2eNpc[row['npc']].hp_left }
      end

      def state_of(char)
        CombatantStates.of(encounter, Character[char.id])
      end

      def hp_of(char)
        state = state_of(char)

        state ? Pf2eHP.get_current_hp(state) : 0
      end

      def max_hp_of(char)
        state = state_of(char)

        state ? Pf2eHP.get_max_hp(state) : 0
      end

      def down?(char)
        hp_of(char) <= 0
      end

      # The GM's correction for a player knocked out: what play at a table would be the cleric's next
      # action, here so that everyone plays every round.
      def rescue_the_fallen
        @party.select { |char| down?(char) }.each do |char|
          type(@gm, "condition/set #{char.name}=dying/0")
          type(@gm, "heal #{char.name}=#{max_hp_of(char)}")
        end
      end

      # ------------------------------------------------------------------------------
      # A creature's turn: its GM strikes the player with the most hit points left and, the first time,
      # uses one of its own abilities or spells. The probes knock a character out on purpose; spreading
      # the blows lets everyone play the fight through.

      def creature_turn(row)
        target = @party.reject { |char| down?(char) }.max_by { |char| hp_of(char) } || @party.first
        npc = Pf2eNpc[row['npc']]
        block = npc.stat_block || {}

        type(@gm, "e/as ##{row['id']}=strike #{target.name}")

        # A player answers a hit with what the game offers: Nimble Dodge where it would turn the hit, then
        # Shield Block behind a raised shield.
        AttackAnswers.offered(state_of(target)).first(1).each { |name| attempt(target, :act, name, "e/act #{name.downcase}") }
        attempt(target, :act, 'Shield Block', 'e/act shield block') if ShieldBlock.offered?(state_of(target))

        unless @tried[:creatures][row['id']]
          @tried[:creatures][row['id']] = true

          ability = Array(block['actions']).find { |one| %w{action free}.include?(one['type'].to_s) }
          type(@gm, "e/as ##{row['id']}=act #{ability['name']}=#{target.name}") if ability

          spell = creature_spell(block)
          type(@gm, "e/as ##{row['id']}=cast #{spell}=#{target.name}") if spell
        end

        type(@gm, "e/creature ##{row['id']}")
      end

      def creature_spell(block)
        casting = Array(block['spellcasting']).first

        return nil unless casting

        spells = casting['spells'] || {}
        rank = spells.keys.reject { |key| key.to_s == '0' }.max_by(&:to_i)

        rank ? Array(spells[rank]).find { |spell| fighting?(spell) } || Array(spells[rank]).first : nil
      end

      # ------------------------------------------------------------------------------
      # A player's turn: up to three things they have not yet tried, else a Strike.

      def player_turn(char)
        return if down?(char)

        # Someone who starts their turn on the ground gets up first.
        type(char, 'e/act stand') if (state_of(char).pf2_conditions || {}).key?('Prone')

        agenda = (@agendas ||= {})[[ char.id, encounter.id ]] ||= agenda_for(char)
        undone = agenda.reject { |kind, what, _text| @tried[char.id].key?([ kind, what ]) }
        undone = undone.sort_by { |kind, _what, _text| kind == :heal ? 0 : 1 } if ally_hurt?

        # A command that cannot be typed yet - Drain Bonded Item before a spell is cast - waits.
        undone.lazy.map { |kind, what, text| [ kind, what, text.respond_to?(:call) ? text.call : text ] }
              .select { |_kind, _what, command| command }.first(3).each do |kind, what, command|
          break if foes.empty?

          attempt(char, kind, what, command)
        end

        return unless undone.empty? && foe

        attempt(char, :strike, 'again', "e/strike ##{foe['id']}")
      end

      def ally_hurt?
        @party.any? { |char| hp_of(char) < max_hp_of(char) / 2 }
      end

      def hurt_ally
        @party.min_by { |char| hp_of(char).to_f / [ max_hp_of(char), 1 ].max }
      end

      def foe_ref
        -> { "##{(foe || {})['id']}" }
      end

      # Everything this character can try, as [ kind, what, command ]. A command is a lambda where its
      # target is chosen when it is typed.
      def agenda_for(char)
        state = state_of(char)
        out = []

        out << [ :look, 'sheet', 'e/sheet' ]
        out << [ :look, 'gear', 'e/gear' ]
        out << [ :look, 'turn', 'e/turn' ]

        Array(state.weapons.to_a).each_with_index do |weapon, n|
          name = weapon.name
          out << [ :strike, name, -> { "e/strike #{foe_ref.call}=#{name}" } ]
          out << [ :equipment, "unequip #{name}", "e/unequip weapons=#{n}" ] if n.zero?
          out << [ :equipment, "equip #{name}", "e/equip weapons=#{n}" ] if n.zero?
        end
        out << [ :strike, 'fist', -> { "e/strike #{foe_ref.call}=fist" } ]
        out << [ :look, 'why', 'e/why' ]

        out << [ :act, 'Raise a Shield', 'e/act raise a shield' ] unless state.shields.to_a.empty? || ShieldBlock.cannot_raise(state)
        out << [ :act, 'Demoralize', -> { "e/act demoralize=#{foe_ref.call}" } ]

        # What the game offers them, and what their class, heritage and background say they have.
        granted = Array((Character[char.id].pf2_actions || {})['actions'])
        # A healing action is for whoever is worst hurt; anything else is aimed at a foe. Shield Block and
        # Nimble Dodge answer a hit, and are used when one offers them.
        answers = [ ShieldBlock::NAME ] + AttackAnswers.reactions(state)
        (class_actions(state) + granted).uniq { |action| Domains.slug(action) }.each do |action|
          next if answers.include?(action) || Acting::COMMANDS.key?(Domains.slug(action))

          if action == BondedItem::NAME
            out << [ :ability, action, -> { (spell = cast_today(char)) && "e/act #{action.downcase}/#{spell}" } ]
          elsif Array(Actions.info(action)['traits']).include?('healing')
            out << [ :heal, action, -> { "e/act #{action}=#{hurt_ally.name}" } ]
          else
            out << [ :ability, action, -> { "e/act #{action}=#{foe_ref.call}" } ]
          end
        end

        spells_for(char, state).each { |entry| out << entry }

        # A bomb is thrown at a foe; anything else is drunk, or given to whoever is worst hurt.
        state.consumables.to_a.each_with_index do |item, n|
          name = item.name

          if Consumables.bomb?(name)
            out << [ :strike, name, -> { "e/strike #{foe_ref.call}=#{name}" } ]
          elsif Consumables.info(name)['heal']
            out << [ :heal, name, -> { "e/use consumables=#{n}/#{hurt_ally.name}" } ]
          else
            out << [ :item, name, "e/use consumables=#{n}" ]
          end
        end

        out << [ :refocus, 'refocus', 'e/refocus' ] if Pf2emagic.focus_pool_max(Character[char.id].magic).to_i > 0

        (Character[char.id].pf2_alchemy_plan || {}).each_key { |item| out << [ :alchemy, item, "e/alchemy #{item}" ] }

        out
      end

      # A spell they prepared today and have cast, which Drain Bonded Item gives back.
      def cast_today(char)
        magic = state_of(char).magic

        return nil unless magic

        (magic.spells_prepared || {}).each do |charclass, ranks|
          (ranks || {}).each do |rank, spells|
            next if rank.to_s == 'cantrip'

            left = Array(((magic.spells_today || {})[charclass] || {})[rank])
            Array(spells).uniq.each { |spell| return spell if Array(spells).count(spell) > left.count(spell) }
          end
        end

        nil
      end

      # The actions a character's own feats and features give them, which no one else has.
      def class_actions(state)
        Actions.available(state, 'combat').reject { |name| Actions.info(name)['for'] == 'everyone' }
      end

      def spells_for(char, state)
        magic = state.magic

        return [] unless magic

        out = []
        today = magic.spells_today || {}

        (magic.tradition || {}).keys.reject { |key| key == 'innate' }.each do |charclass|
          casting = Pf2emagic.get_caster_type(charclass)
          slots = today[charclass] || {}

          if casting == 'prepared'
            slots.each_pair do |rank, spells|
              Array(spells).uniq.each { |spell| out << cast_entry(spell, rank, charclass) }
            end
          else
            known = Pf2emagic::Entries.known_lists(Character[char.id])[charclass] || {}

            known.each_pair do |rank, spells|
              next unless rank.to_s == 'cantrip' || slots[rank.to_s].to_i > 0

              Array(spells).first(rank.to_s == 'cantrip' ? 5 : 2).each { |spell| out << cast_entry(spell, rank, charclass) }
            end
          end
        end

        Pf2emagic::Entries.focus_types(magic).each do |focus_type|
          Pf2emagic::Entries.focus_spells(magic, focus_type).each { |spell| out << cast_entry(spell, nil, nil, 'focus') }
          Pf2emagic::Entries.focus_cantrips(magic, focus_type).each { |spell| out << cast_entry(spell, nil, nil, 'focusc') }
        end

        Array(today['innate']).each { |rank, spells| Array(spells).each { |spell| out << cast_entry(spell, rank, nil, 'innate') } } if today['innate'].is_a?(Hash)

        out.uniq { |kind, what, _text| [ kind, what ] }
      end

      def cast_entry(spell, rank, charclass, how = nil)
        suffix = ''
        suffix += "/rank #{rank}" if rank && rank.to_s != 'cantrip' && how.nil?
        suffix += "/class #{charclass}" if charclass
        suffix += "/#{how}" if how
        way = Acting.way_needed(spell, [])
        suffix += "/#{way.args['ways'].split(', ').first.downcase}" if way.err?
        label = how ? "#{spell} (#{how})" : spell

        if healing?(spell)
          [ :heal, label, -> { "e/cast #{spell}=#{hurt_ally.name}#{suffix}" } ]
        elsif fighting?(spell)
          [ :spell, label, -> { "e/cast #{spell}=#{foe_ref.call}#{suffix}" } ]
        else
          [ :spell, label, "e/cast #{spell}#{suffix}" ]
        end
      end

      # ------------------------------------------------------------------------------
      # Between encounters, and after

      def rest!
        say '## The GM rests the party'
        type(@gm, 'e/rest')
      end

      def wrap_up!
        say '## After'
        @party.each do |char|
          type(char, 'sheet')
          type(char, 'gear')
        end
      end

      def run!
        stage!
        build_party!
        outfit!

        first = fight!(@waves[0])
        second = @waves[1] ? fight!(@waves[1], carries_on: first) : nil

        wrap_up!
        [ first, second ].compact
      end

      # ------------------------------------------------------------------------------
      # What it found

      def errors
        @outcomes.select(&:error)
      end

      # Per player, everything they tried and how it went, the first time they tried it.
      def coverage
        @party.each_with_object({}) do |char, out|
          out[char.name] = @tries.select { |one| one.who == char.name }
                                 .uniq { |one| [ one.kind, one.what ] }
                                 .map { |one| [ one.kind, one.what, one.outcome.status ] }
        end
      end

      def report
        lines = [ "# #{@name}", '' ]

        coverage.each_pair do |who, rows|
          ok = rows.count { |_kind, _what, status| status == 'ok' }
          lines << "## #{who}: #{ok}/#{rows.size} ok"
          rows.each { |kind, what, status| lines << "- #{kind} #{what}: #{status}" }
          lines << ''
        end

        lines << '## Errors'
        errors.each { |one| lines << "- #{one.who}: #{one.text} -> #{one.status}" }
        lines << ''
        lines << '## Interactions'
        @probes.each { |name, status| lines << "- #{name}: #{status}" }
        lines << ''
        lines << "## Arithmetic: #{@audit.counts.map { |what, count| "#{count} #{what}" }.join(', ')}"
        @audit.findings.each { |one| lines << "- #{one}" }
        lines.join("\n")
      end

      def cleanup!
        @encounters.each { |one| PF2Encounter[one.id]&.delete }
        @party.each { |char| Character[char.id]&.delete }
        [ @gm, @scene, @room ].each { |one| one&.class&.[](one.id)&.delete }
      end
    end
  end
end
