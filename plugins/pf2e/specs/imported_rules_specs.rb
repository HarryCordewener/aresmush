require "plugin_test_loader"
require "json"

module AresMUSH

  # Every rule element in config, held against the vocabulary that reads it.
  #
  # The rows are imported from the pf2e system's own packs, which is the point: their system is the
  # reference implementation of these mechanics. What they replaced was hand-written and wrong in the
  # same direction every time - of 51 item bonuses, 10 granted a conditional bonus unconditionally, and
  # of 14 hand-written conditions, Unconscious penalised the wrong save.
  #
  # So this asserts against the tables rather than against a list someone has to remember to update: a
  # selector no statistic answers to, a kind nothing applies, a field nothing reads, or a formula the
  # reader cannot parse fails here rather than in front of a player.
  describe "imported rules", :dbtest => true do

    CATALOGUES = %w{pf2e_conditions pf2e_magicitem pf2e_armor pf2e_weapons pf2e_shields pf2e_gear
                    pf2e_consumables pf2e_feats pf2e_effects}.freeze

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config
    end

    def rows
      CATALOGUES.flat_map do |catalogue|
        (Global.read_config(catalogue) || {}).flat_map do |name, info|
          next [] unless info.is_a?(Hash) && info['rules']

          info['rules'].map { |row| [ "#{catalogue} / #{name}", row ] }
        end
      end
    end

    # Every domain any statistic can produce, which is the whole vocabulary a selector may name.
    def reachable
      saves = %w{Fortitude Reflex Will}.flat_map { |s|
        Pf2e::Domains.for('save', Pf2e.canonical_save(s), Pf2e::LINKED_ABILITY[s.downcase])
      }
      skills = (Global.read_config('pf2e_skills') || {}).flat_map { |name, info|
        Pf2e::Domains.for(Pf2eSkills.lore?(name) ? 'lore' : 'skill', name, info['key_abil'])
      }
      plain = %w{hp ac perception class_dc spell_dc spell_attack initiative healing}.flat_map { |kind|
        Pf2e::ABILITIES.flat_map { |ability| Pf2e::Domains.for(kind, nil, ability) }
      }
      speeds = Pf2e::Domains::MOVEMENT.flat_map { |type| Pf2e::Domains.for('speed', type) }

      # An attack and its damage carry the weapon's own facts, so their domains are generated from the
      # catalogue's own weapon names, groups and base types rather than from a representative one.
      weapons = (Global.read_config('pf2e_weapons') || {})
      attacks = weapons.first(400).flat_map { |name, info|
        [ true, false ].flat_map { |ranged|
          descriptor = { 'name' => name, 'group' => info['group'], 'base' => info['base'] || name,
                         'prof' => 'expert', 'ranged' => ranged,
                         'unarmed' => Pf2e.has_trait?(info['traits'], 'unarmed') }

          Pf2e::Domains.for('attack', descriptor, 'Strength') +
            Pf2e::Domains.for('damage', descriptor, 'Strength')
        }
      }
      shapes = Pf2e::ABILITIES.flat_map { |ability|
        %w{unarmed weapon}.product([ true, false ]).flat_map { |kind, ranged|
          descriptor = { 'ranged' => ranged, 'unarmed' => kind == 'unarmed' }

          Pf2e::Domains.for('attack', descriptor, ability) +
            Pf2e::Domains.for('damage', descriptor, ability)
        }
      }

      (saves + skills + plain + speeds + attacks + shapes).uniq
    end

    # Two kinds of selector cannot be checked against a list. One names the item carrying the rule and
    # resolves to an id we cannot know here. The other is built off the name of an attack a character
    # has, which a feat can invent - Tiger Stance grants a tiger claw, so `tiger-claw-damage` is a real
    # domain that no catalogue contains. Both are checked by shape; everything else against the list,
    # which is what still catches `healing` and `will-dc`.
    # What a field looks like once the wearer's or taker's answer has filled it in. A ChoiceSet answer
    # is a slug, so a plain one stands for every answer the set could give: the claim being checked is
    # that the shape reaches something, not that a particular choice does.
    def once_chosen(text)
      text.to_s.gsub(Pf2e::Rules::INTERPOLATION, 'chosen')
    end

    # A selector naming the choice its taker made, or the item it sits on, is checked as a shape: what
    # it reaches depends on the answer, and an answer that reaches nothing is a rule that is ignored
    # rather than a rule that is wrong.
    def resolvable?(selector, held)
      return true if selector.to_s.match?(Pf2e::Rules::INTERPOLATION)

      slug = Pf2e::Domains.slug(selector)

      held.include?(slug) || Pf2e::Domains.derived?(slug)
    end

    it "should have imported rules to check" do
      expect(rows.size).to be > 300
    end

    it "should carry only kinds we apply" do
      strays = rows.reject { |_where, row| Pf2e::Rules.known?(row['key']) }
                   .map { |where, row| "#{where}: #{row['key'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should carry only fields we read" do
      strays = rows.flat_map { |where, row|
        fields = Pf2e::Rules::BY_KEY[row['key'].to_s]['fields']

        (row.keys.map(&:to_s) - fields).map { |field| "#{where}: #{field}" }
      }

      expect(strays.uniq).to eq []
    end

    it "should name only selectors some statistic answers to" do
      held = reachable

      strays = rows.reject { |_where, row| SELECTORLESS.include?(row['key']) }
                   .flat_map { |where, row|
        Pf2e::Rules.selectors_of(row).reject { |selector| resolvable?(selector, held) }
                   .map { |selector| "#{where}: #{selector}" }
      }

      expect(strays.uniq).to eq []
    end

    # Kinds that reach no statistic, so they name no domain: one declares a circumstance, one writes a
    # value, three describe damage, two describe an attack, one asks a question, one brings another
    # condition with it, one gives temporary hit points, one changes a thing the character has, one heals
    # as a turn starts, three change the character's body or what is around it - size, an aura, a battle
    # form - three change the character themselves - their traits, how much Dexterity counts, their hit
    # points - and BaseSpeed names a kind of movement.
    SELECTORLESS = %w{RollOption ActiveEffectLike Immunity Weakness Resistance AdjustStrike Strike
                      BaseSpeed Sense MartialProficiency CriticalSpecialization ChoiceSet
                      GrantItem TempHP ItemAlteration FastHealing CreatureSize Aura
                      BattleForm ActorTraits DexterityModifierCap LoseHitPoints}.freeze

    # Of those, the two that still carry a `selector` - because a movement type and a sense are not
    # domains, they are the thing being granted.
    NAMES_ITS_OWN_THING = %w{BaseSpeed Sense}.freeze

    # Kinds whose `value` is a word rather than arithmetic: a trait, a kind of damage, a sense, and what
    # an alteration makes a thing into.
    NOT_ARITHMETIC = %w{ActiveEffectLike AdjustStrike Strike DamageAlteration ItemAlteration CreatureSize
                        Aura BattleForm}.freeze
    IWR_KINDS = %w{Immunity Weakness Resistance}.freeze

    # A row may name one selector or several, and their data uses both spellings.
    it "should have a selector on everything that reaches a statistic, and on nothing else" do
      reaching, apart = rows.partition { |_where, row| !SELECTORLESS.include?(row['key']) }

      expect(reaching.reject { |_where, row| Pf2e::Rules.selectors_of(row).any? }
                     .map(&:first).uniq).to eq []
      expect(apart.reject { |_where, row| NAMES_ITS_OWN_THING.include?(row['key']) }
                  .select { |_where, row| Pf2e::Rules.selectors_of(row).any? }
                  .map(&:first).uniq).to eq []
    end

    it "should have an option on every declaration" do
      declarations = rows.select { |_where, row| row['key'] == 'RollOption' }

      expect(declarations.reject { |_where, row| row['option'] }.map(&:first).uniq).to eq []
    end

    # A path the registry cannot write would be an effect that silently does nothing.
    it "should write only paths the registry knows" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row| Pf2e::Paths.writable?(once_chosen(row['path'])) }
                     .map { |where, row| "#{where}: #{row['path']}" }

      expect(strays.uniq).to eq []
    end

    it "should write with only the modes the registry applies" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row| Pf2e::Paths::MODES.key?(row['mode'].to_s) }
                     .map { |where, row| "#{where}: #{row['mode'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # A kind of damage we cannot resolve would resist nothing, so the type has to be a plain word - or
    # an interpolation naming the choice its wearer made, which resolves to one before it is read.
    it "should resist only kinds of damage it can name" do
      iwr = rows.select { |_where, row| IWR_KINDS.include?(row['key']) }

      strays = iwr.reject { |_where, row|
        Array(row['type']).all? { |one| !once_chosen(one).include?('{') }
      }
                  .map { |where, row| "#{where}: #{row['type'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should give a weakness and a resistance a value, since that is how much it is" do
      valued = rows.select { |_where, row| %w{Weakness Resistance}.include?(row['key']) }

      expect(valued.reject { |_where, row| row['value'] }.map(&:first).uniq).to eq []
    end

    it "should have immunities and resistances, which conditions and items both declare" do
      expect(rows.count { |_where, row| IWR_KINDS.include?(row['key']) }).to be > 5
    end

    # An adjustment has to name a mode the arithmetic knows, or suppress instead.
    it "should adjust modifiers only with modes we apply" do
      adjusting = rows.select { |_where, row| row['key'] == 'AdjustModifier' }

      strays = adjusting.reject { |_where, row|
        row['suppress'] || Pf2e::Paths::MODES.key?(row['mode'].to_s)
      }.map { |where, row| "#{where}: #{row['mode'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # An outcome adjustment has to name an outcome and a change `Pf2e::Degree` knows.
    it "should adjust outcomes only in ways Degree reads" do
      adjusting = rows.select { |_where, row| row['key'] == 'AdjustDegreeOfSuccess' }
      outcomes = Pf2e::Degree::NAMES + [ 'all' ]

      strays = adjusting.flat_map { |where, row|
        row['adjustment'].to_h.reject { |outcome, named|
          outcomes.include?(outcome.to_s) && Pf2e::Degree::ADJUSTMENTS.key?(named.to_s)
        }.map { |outcome, named| "#{where}: #{outcome}=#{named}" }
      }

      expect(strays.uniq).to eq []
    end

    it "should have adjustments of both kinds, since that is what the foundations were for" do
      expect(rows.count { |_where, row| row['key'] == 'AdjustModifier' }).to be > 20
      expect(rows.count { |_where, row| row['key'] == 'AdjustDegreeOfSuccess' }).to be > 20
    end

    # A sense is the thing being granted rather than a domain, and it has to be one we know.
    it "should grant senses we know" do
      senses = rows.select { |_where, row| row['key'] == 'Sense' }

      strays = senses.reject { |_where, row| row['selector'].to_s.match?(/\A[a-z-]+\z/) }
                     .map { |where, row| "#{where}: #{row['selector'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # A proficiency has to say what it copies, and a crit spec rule has to say when it applies.
    it "should say what each granted proficiency copies" do
      granted = rows.select { |_where, row| row['key'] == 'MartialProficiency' }

      expect(granted.reject { |_where, row| row['sameAs'] && row['definition'] }
                    .map(&:first).uniq).to eq []
    end

    it "should say when a critical specialisation applies" do
      spec = rows.select { |_where, row| row['key'] == 'CriticalSpecialization' }

      expect(spec.reject { |_where, row| row['predicate'] }.map(&:first).uniq).to eq []
    end

    # An alteration has to name a property the damage reader applies.
    it "should alter damage only in ways the reader applies" do
      altering = rows.select { |_where, row| row['key'] == 'DamageAlteration' }
      known = %w{damage-type dice-number dice-faces}

      strays = altering.reject { |_where, row| known.include?(row['property'].to_s) }
                       .map { |where, row| "#{where}: #{row['property'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # The importer and `Pf2e::Rules` have to want the same fields. A field the importer accepts and does
    # not write is a rule that arrives saying less than Foundry wrote - which is how every imported
    # `slug` went missing, and with it every adjustment's aim: a row with no slug adjusts *every*
    # modifier its selector reaches.
    describe "the importer's vocabulary" do
      def importer
        found = `python3 scripts/import_foundry_rules.py --fields 2>/dev/null`

        found.empty? ? nil : JSON.parse(found)
      end

      def ours
        Pf2e::Rules::KINDS.each_with_object({}) do |row, out|
          out[row['key']] = (row['fields'] + Array(Pf2e::Rules::PRESENTATION[row['key']])).sort
        end
      end

      it "should read the same fields the importer accepts" do
        theirs = importer

        skip 'python3 is not available' unless theirs

        expect(theirs['fields'].transform_values(&:sort)).to eq ours
      end

      it "should leave out the same fields the importer leaves out" do
        theirs = importer

        skip 'python3 is not available' unless theirs

        mine = Pf2e::Rules::PRESENTATION.transform_values(&:sort)

        expect(theirs['presentation'].transform_values(&:sort)).to eq mine
      end
    end

    # Every kind of rule on what we stock that is not about Foundry's canvas, crafting or a roll's target:
    # thirty-one.
    it "should have all thirty-one kinds it reads" do
      expect(rows.map { |_where, row| row['key'] }.uniq.size).to eq 31
    end

    # An aura's effects have to be effects the catalogue holds, or it puts nothing on anyone.
    it "should project only effects that exist" do
      auras = rows.select { |_where, row| row['key'] == 'Aura' }

      strays = auras.flat_map { |where, row|
        Array(row['effects']).map { |one| Pf2e::Grants.target(one['uuid']) }
                             .reject { |catalogue, name| catalogue == 'effects' && Pf2e::ActiveEffects.catalogue.key?(name) }
                             .map { |_catalogue, name| "#{where}: #{name}" }
      }

      expect(strays.uniq).to eq []
    end

    # An alteration has to change something this engine models, on a kind of thing it has.
    it "should alter only things and properties that are modelled" do
      altering = rows.select { |_where, row| row['key'] == 'ItemAlteration' }

      strays = altering.reject { |_where, row|
        Pf2e::Alterations::PROPERTIES.key?(row['property'].to_s) &&
          (row['itemId'] || Pf2e::Alterations::KINDS.include?(row['itemType'].to_s))
      }.map { |where, row| "#{where}: #{row['itemType']} #{row['property']}" }

      expect(strays.uniq).to eq []
    end

    # An effect granting another effect has to name one the catalogue holds, or it brings nothing.
    it "should grant effects that exist" do
      named = rows.select { |_where, row| row['key'] == 'GrantItem' }
                  .map { |where, row| [ where, Pf2e::Grants.target(row['uuid']) ] }
                  .select { |_where, (catalogue, _name)| catalogue == 'effects' }

      strays = named.reject { |_where, (_catalogue, name)| Pf2e::ActiveEffects.catalogue.key?(name) }
                    .map { |where, (_catalogue, name)| "#{where}: #{name}" }

      expect(strays.uniq).to eq []
    end

    # A grant has to name something a catalogue here holds, or it would bring nothing with it.
    it "should grant only things a catalogue here holds" do
      grants = rows.select { |_where, row| row['key'] == 'GrantItem' }

      strays = grants.reject { |_where, row| Pf2e::Grants.target(row['uuid']) }
                     .map { |where, row| "#{where}: #{row['uuid']}" }

      expect(strays.uniq).to eq []
    end

    it "should grant conditions that exist" do
      named = rows.select { |_where, row| row['key'] == 'GrantItem' }
                  .map { |where, row| [ where, Pf2e::Grants.target(row['uuid']) ] }
                  .select { |_where, (catalogue, _name)| catalogue == 'conditions' }

      strays = named.reject { |_where, (_catalogue, name)|
        Global.read_config('pf2e_conditions', Pf2e.canonical_condition(name))
      }.map { |where, (_catalogue, name)| "#{where}: #{name}" }

      expect(strays.uniq).to eq []
    end

    # A granted speed names a kind of movement rather than a domain, and the kind has to be one that
    # exists.
    it "should grant speeds only of kinds of movement we have" do
      speeds = rows.select { |_where, row| row['key'] == 'BaseSpeed' }

      strays = speeds.reject { |_where, row| Pf2e::Domains::MOVEMENT.include?(row['selector'].to_s) }
                     .map { |where, row| "#{where}: #{row['selector'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # An attack we could not roll is not an attack.
    it "should grant attacks that have damage of their own" do
      strikes = rows.select { |_where, row| row['key'] == 'Strike' }

      strays = strikes.reject { |_where, row| row.dig('damage', 'base', 'die') }
                      .map(&:first)

      expect(strays.uniq).to eq []
    end

    # Everything an AdjustStrike can change has to be something the descriptor carries, and a list of
    # words is only ever added to.
    it "should adjust attacks only in ways that change something" do
      adjusting = rows.select { |_where, row| row['key'] == 'AdjustStrike' }

      strays = adjusting.reject { |_where, row|
        field = Pf2e::Rules::STRIKE_PROPERTIES[row['property'].to_s]

        next false unless field
        next row['mode'].to_s == 'add' if Pf2e::Rules::STRIKE_LISTS.include?(field)

        Pf2e::Paths::MODES.key?(row['mode'].to_s)
      }.map { |where, row| "#{where}: #{row['property']} #{row['mode']}" }

      expect(strays.uniq).to eq []
    end

    it "should have granted speeds, attacks and adjusted attacks" do
      %w{BaseSpeed Strike AdjustStrike}.each do |kind|
        expect(rows.count { |_where, row| row['key'] == kind }).to(be > 5, kind)
      end
    end

    it "should have writes, since that is the second half of some feats" do
      expect(rows.count { |_where, row| row['key'] == 'ActiveEffectLike' }).to be > 40
    end

    # A write's value is stored as it stands, so it has to be something we can store and read back.
    it "should write only values we can hold" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.reject { |_where, row|
        [ String, Integer, Float, TrueClass, FalseClass ].any? { |kind| row['value'].is_a?(kind) }
      }.map { |where, row| "#{where}: #{row['value'].class}" }

      expect(strays.uniq).to eq []
    end

    it "should have declarations, since most of what an item offers is one" do
      expect(rows.count { |_where, row| row['key'] == 'RollOption' }).to be > 50
    end

    # Only a modifier's `type` is a stacking type. On an immunity or a resistance it is a kind of damage,
    # which is a different vocabulary in the same field name.
    it "should name only modifier types the stacking rule knows" do
      modifiers = rows.select { |_where, row| row['key'] == 'FlatModifier' && row['type'] }

      strays = modifiers.reject { |_where, row| Pf2e::Modifiers::TYPES.include?(row['type'].to_s) }
                        .map { |where, row| "#{where}: #{row['type'].inspect}" }

      expect(strays.uniq).to eq []
    end

    # A value that is a number or an expression has to be readable. A write's value may be neither - a
    # list of forms, a word - and those are written as they stand rather than evaluated.
    it "should carry values the formula reader can read" do
      strays = rows.flat_map { |where, row|
        Pf2e::Rules::FORMULA_FIELDS
          .select { |field| row[field].is_a?(Numeric) || row[field].is_a?(String) }
          .reject { |field| Pf2e::Formula.parses?(row[field]) || NOT_ARITHMETIC.include?(row['key']) }
          .map { |field| "#{where}: #{field} #{row[field].inspect}" }
      }

      expect(strays.uniq).to eq []
    end

    # A write's value, where it is arithmetic, still has to be readable: Breath Control's is
    # `25 * (5 + @actor.abilities.con.mod)`.
    it "should carry writable arithmetic the formula reader can read" do
      writes = rows.select { |_where, row| row['key'] == 'ActiveEffectLike' }

      strays = writes.select { |_where, row| row['value'].is_a?(String) }
                     .select { |_where, row| row['value'].match?(/[@(]/) }
                     .reject { |_where, row| Pf2e::Formula.parses?(row['value']) }
                     .map { |where, row| "#{where}: #{row['value'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should carry circumstances the predicate reader finds valid" do
      strays = rows.select { |_where, row| row['predicate'] }
                   .reject { |_where, row| Pf2e::Predicate.valid?(row['predicate']) }
                   .map { |where, row| "#{where}: #{row['predicate'].inspect}" }

      expect(strays.uniq).to eq []
    end

    it "should have conditional rows, since most item bonuses are conditional" do
      expect(rows.count { |_where, row| row['predicate'] }).to be > 20
    end

    it "should have damage dice, since that is what most feats that touch damage add" do
      expect(rows.count { |_where, row| row['key'] == 'DamageDice' }).to be > 20
    end

    # An override raises a die, sets it outright, or changes the kind of damage. Every one has exactly
    # one property, which is what their own validation requires.
    it "should carry only overrides the damage reader applies" do
      known = %w{upgrade downgrade dieSize diceNumber damageType}

      strays = rows.select { |_where, row| row['override'] }
                   .flat_map { |where, row|
                     (row['override'].keys.map(&:to_s) - known).map { |key| "#{where}: #{key}" }
                   }

      expect(strays.uniq).to eq []
    end

    it "should have overrides, since that is how a die size is raised" do
      expect(rows.count { |_where, row| row['override'] }).to be > 5
    end

    # One vocabulary, not two: a block left behind next to a `rules:` block would be read by different
    # code and counted twice.
    it "should have nothing left carrying the vocabularies this replaced" do
      left = CATALOGUES.flat_map { |catalogue|
        (Global.read_config(catalogue) || {})
          .select { |_n, i| i.is_a?(Hash) && (i['bonus'] || i['modifies'] || i['affected_stat']) }.keys
      }

      expect(left).to eq []
    end
  end
end
