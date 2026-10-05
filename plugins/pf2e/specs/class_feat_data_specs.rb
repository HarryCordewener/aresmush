require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Class feats whose effect is data alone, checked against what the feat's text says it does.
    describe "class feat data" do

      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @spells = {}

        Dir.glob("game/config/pf2e_spells_*.yml").each do |file|
          @spells.merge!(YAML.load_file(file)['pf2e_spells'])
        end

        @magic = YAML.load_file("game/config/pf2e_magic.yml")['pf2e_magic']
        @specialty = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']
        @deities = YAML.load_file("game/config/pf2e_deities.yml")['pf2e_deities']
      end

      def feat(name)
        @feats.fetch(name)
      end

      def spell(name)
        @spells.fetch(name) { raise "No spell named #{name.inspect}" }
      end

      def traits(name)
        Array(spell(name)['traits'])
      end

      # The spells `Pf2emagic.get_spells_by_name` finds for a term: an exact match, or else every
      # name containing it.
      def spells_named(term)
        exact = @spells.keys.find { |name| name.casecmp?(term) }
        return [ exact ] if exact

        @spells.keys.select { |name| name.downcase.match?(term.downcase) }
      end

      describe "init_magic" do
        # The flag grants the spell whose name is the feat's own, so a feat named anything else
        # grants nothing.
        it "should name exactly one spell for each feat that carries it" do
          @feats.each_pair do |name, details|
            next unless details['init_magic']

            expect(spells_named(name).size).to eq(1), "#{name} matches #{spells_named(name).inspect}"
          end
        end
      end

      describe "feats that grant a focus spell" do
        it "should give each a choice" do
          [
            'Initiate Warden', 'Advanced Warden', 'Masterful Warden',
            'Domain Initiate', 'Advanced Domain', "Advanced Deity's Domain", 'Domain Acumen', 'Domain Fluency',
            'Basic Lesson', 'Greater Lesson', 'Major Lesson', 'Diverse Mystery'
          ].each do |name|
            expect(feat(name)['feat_choice']).to be_a(Hash), name
          end
        end

        it "should choose the subclass spell of the tier each names" do
          {
            'Advanced Bloodline' => 'advanced', 'Greater Bloodline' => 'greater',
            'Advanced Revelation' => 'advanced', 'Greater Revelation' => 'greater'
          }.each_pair do |name, tier|
            expect(feat(name)['feat_choice']).to include('auto' => 'subclass_spell', 'from' => 'subclass_spell', 'tier' => tier), name
          end
        end

        it "should let a warden take each feat more than once, for a different spell each time" do
          { 'Initiate Warden' => 1, 'Advanced Warden' => 2, 'Masterful Warden' => 3 }.each_pair do |name, rank|
            expect(feat(name)['repeatable']).to be(true), name
            expect(feat(name)['feat_choice']['from_spells']).to include('traits' => [ 'ranger', 'focus' ], 'base_level' => rank), name
          end
        end

        # Player Core's three lists, which are exactly the ranger's focus spells at ranks 1 to 3.
        it "should offer the warden spells the book lists" do
          wardens = @spells.select { |_n, s| (%w(ranger focus) - Array(s['traits'])).empty? }

          expect(wardens.select { |_n, s| s['base_level'].to_i == 1 }.keys.sort).to eq [ 'Gravity Weapon', 'Heal Companion', 'Magic Hide' ]
          expect(wardens.select { |_n, s| s['base_level'].to_i == 2 }.keys.sort).to eq [ 'Animal Feature', 'Enlarge Companion', "Hunter's Luck", 'Soothing Mist' ]
          expect(wardens.select { |_n, s| s['base_level'].to_i == 3 }.keys.sort).to eq [ 'Ephemeral Tracking', "Ranger's Bramble" ]
        end

        it "should ask Warden's Focus for a warden spell" do
          expect(feat("Warden's Focus")['prereq']['focus_spell']).to include('Gravity Weapon', 'Heal Companion', 'Magic Hide')
        end

        it "should add Fey Caller's three illusions to the druid's list as primal spells" do
          adapted = feat('Fey Caller')['magic_stats']['adapted_spell']

          expect(adapted.map { |a| a['name'] }).to eq [ 'Illusory Disguise', 'Illusory Object', 'Illusory Scene' ]
          expect(adapted.map { |a| a['tradition'] }.uniq).to eq [ 'primal' ]
          adapted.each { |a| expect(a['base_level']).to eq(spell(a['name'])['base_level'].to_i), a['name'] }
        end
      end

      # A pool holds a point per focus spell that costs one, counted from the spells, so nothing in
      # the data declares points. A declaration would be read by nothing.
      it "should declare no focus points anywhere in the data" do
        found = []

        walk = lambda do |node, path|
          case node
          when Hash
            node.each_pair do |key, value|
              found << "#{path}/#{key}" if key.to_s == 'focus_pool'
              walk.call(value, "#{path}/#{key}")
            end
          when Array
            node.each_with_index { |value, i| walk.call(value, "#{path}[#{i}]") }
          end
        end

        Dir.glob("game/config/pf2e_*.yml").each { |file| walk.call(YAML.load_file(file), File.basename(file)) }

        expect(found).to eq []
      end

      # Player Core p. 178: "You learn your choice of the patron's puppet hex or phase familiar hex."
      it "should give a first-level witch her choice of hex" do
        classes = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']
        choice = classes['Witch']['chargen']['feat_choice']["Witch's Hex"]

        expect(choice['options'].keys.sort).to eq [ "Patron's Puppet", 'Phase Familiar' ]

        choice['options'].each_pair do |hex, option|
          expect(option['grants']['magic_stats']['focus_spell']).to eq('hex' => [ hex ])
          expect(traits(hex)).to include('focus', 'hex')
          expect(traits(hex)).not_to include('cantrip')
        end
      end

      describe "bloodline and mystery spells" do
        # Each tier is the focus spell tagged for that subclass at the rank the tier starts at.
        {
          'Sorcerer' => [ 'bloodline', { 'advanced' => 3, 'greater' => 5 } ],
          'Oracle' => [ 'mystery', { 'advanced' => 3, 'greater' => 6 } ]
        }.each_pair do |charclass, (tag, ranks)|
          it "should name each #{tag}'s advanced and greater spell" do
            @specialty.fetch(charclass).each_pair do |subclass, info|
              ranks.each_pair do |tier, rank|
                focus = info["#{tier}_focus_spell"]
                expect(focus).to be_a(Hash), "#{subclass} has no #{tier}_focus_spell"

                name = Array(focus.values.first).first

                expect(traits(name)).to include('focus'), name
                expect(spell(name)['base_level'].to_i).to eq(rank), name
                expect(Array(spell(name)[tag])).to include(subclass.downcase), name
              end
            end
          end
        end
      end

      describe "domains" do
        it "should name real spells for each domain" do
          @magic['domains'].each_pair do |domain, info|
            %w(initial advanced).each do |tier|
              expect(@spells).to have_key(info[tier]), "#{domain} #{tier}: #{info[tier].inspect}"
            end
          end
        end

        # Player Core and Divine Mysteries: every initial domain spell is rank 1 and every advanced
        # one rank 4, each an uncommon cleric focus spell.
        it "should keep every domain spell at its rank" do
          @magic['domains'].each_pair do |domain, info|
            expect(spell(info['initial'])['base_level'].to_i).to eq(1), "#{domain}: #{info['initial']}"
            expect(spell(info['advanced'])['base_level'].to_i).to eq(4), "#{domain}: #{info['advanced']}"
            expect(traits(info['initial'])).to include('cleric', 'focus', 'uncommon'), info['initial']
            expect(traits(info['advanced'])).to include('cleric', 'focus', 'uncommon'), info['advanced']
          end
        end

        it "should give each deity only domains the game has" do
          @deities.each_pair do |deity, info|
            (Array(info['domains']) + Array(info['alternate_domains'])).each do |domain|
              expect(@magic['domains']).to have_key(domain), "#{deity}: #{domain}"
            end
          end
        end

        it "should give each mystery Player Core 2's four domains" do
          expected = {
            'Ancestors' => %w(Death Duty Family Soul), 'Battle' => %w(Destruction Might Protection Zeal),
            'Bones' => %w(Death Decay Undeath Vigil), 'Cosmos' => %w(Darkness Moon Nothingness Star),
            'Flames' => %w(Dust Fire Star Sun), 'Life' => %w(Death Healing Pain Soul),
            'Lore' => %w(Knowledge Magic Secrecy Truth), 'Tempest' => %w(Air Cold Lightning Water)
          }

          expect(@specialty['Oracle'].keys.sort).to eq expected.keys.sort

          expected.each_pair do |mystery, domains|
            expect(@specialty['Oracle'][mystery]['domains']).to eq(domains), mystery
            domains.each { |d| expect(@magic['domains']).to have_key(d) }
          end
        end
      end

      describe "lessons" do
        it "should name a hex and a familiar spell that exist for each lesson" do
          @magic['lessons'].each_pair do |tier, lessons|
            lessons.each_pair do |lesson, info|
              expect(traits(info['hex'])).to include('hex', 'focus'), lesson

              Array(info['spell']).each { |name| expect(@spells).to have_key(name), "#{lesson}: #{name}" }
            end
          end
        end
      end

      describe "refocus" do
        def refills
          [
            'Bloodline Focus', 'Bonded Focus', 'Devoted Focus', 'Domain Focus', 'Hex Focus',
            'Inspirational Focus', 'Meditative Focus', 'Primal Focus', "Revelation's Focus", "Warden's Focus"
          ]
        end

        it "should mark each feat that refills the pool" do
          refills.each do |name|
            expect(@feats.fetch(name)['refocus']).to eq('refill'), name
          end
        end

        # A feat marked by mistake would hand a whole pool back on every Refocus.
        it "should mark only feats whose text says the pool refills" do
          @feats.each_pair do |name, details|
            next unless details['refocus']

            expect(details['shortdesc']).to match(/refill your focus pool|regain all your Focus Points/i), name
          end
        end
      end

      describe "composition cantrips" do
        it "should grant each as a composition cantrip" do
          [ 'Dirge of Doom', 'Song of Marching', 'House of Imaginary Walls' ].each do |name|
            expect(feat(name)['init_magic']).to be(true), name
            expect(traits(name)).to include('cantrip', 'composition'), name
          end
        end
      end

      describe "order spells" do
        it "should grant the spells named after their feats" do
          [ 'Primal Summons', 'Impaling Briars' ].each do |name|
            expect(feat(name)['init_magic']).to be(true), name
            expect(traits(name)).to include('focus', 'druid'), name
          end
        end

        it "should grant the spells named otherwise by name" do
          { 'Wind Caller' => 'Stormwind Flight', 'Invoke Disaster' => 'Storm Lord' }.each_pair do |name, granted|
            expect(feat(name)['magic_stats']).to eq('focus_spell' => { 'order' => [ granted ] })
            expect(traits(granted)).to include('focus', 'druid'), granted
          end
        end
      end

      it "should raise Animal Skin's unarmored defense to expert" do
        expect(feat('Animal Skin')['grants']).to eq('combat_stats' => { 'armor_prof' => { 'unarmored' => 'expert' } })
      end

      it "should train Monastic Weaponry's monk weapons" do
        expect(feat('Monastic Weaponry')['grants']).to eq('combat_stats' => { 'weapon_prof' => { 'monk' => 'trained' } })
      end

      # Neither is the Additional Lore feat, whose Lore rises at 3rd, 7th and 15th level.
      it "should train the Lore each feat names" do
        skills = YAML.load_file("game/config/pf2e_skills.yml")['pf2e_skills']

        { 'Bardic Lore' => 'Bardic Lore', 'Underworld Investigator' => 'Underworld Lore' }.each_pair do |name, lore|
          expect(feat(name)['grants']).to eq('skill' => [ lore ])
          expect(skills).to have_key(lore)
        end
      end

      # A class table sets a rank's slots outright, so a feat adds to them. The rank is a string
      # because the stored slots are keyed by string, and a number would miss them.
      it "should add a 10th-rank slot for each feat whose text gives one" do
        givers = @feats.select { |_name, details| details['shortdesc'].to_s.match?(/additional 10th-rank spell slot/i) }

        expect(givers.keys).to include('Perfect Encore', "Archwizard's Might")

        givers.each_pair do |name, details|
          expect(details['magic_stats']).to eq('spells_per_day' => { '10' => '+1' }), name
        end
      end

      it "should add a repertoire spell of each rank for Deep Lore and Greater Mental Evolution" do
        [ 'Deep Lore', 'Greater Mental Evolution' ].each do |name|
          expect(feat(name)['magic_stats']).to eq('repertoire_each_rank' => 1), name
        end
      end

      describe "prerequisites" do
        def class_feats
          YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats']
        end

        # A name under `feat` or `orfeat` is matched against the feats a character holds, so one
        # that names anything else can never be met.
        it "should name only feats under feat and orfeat" do
          # These wait on the familiar and companion systems: a patron's tradition, and holding an
          # animal companion.
          waiting = [ 'Spirit Familiar (Witch)', 'Stitched Familiar', 'Side by Side (Ranger)' ]
          known = @feats.keys.map(&:downcase)

          class_feats.each_pair do |name, details|
            next if waiting.include?(name)

            prereq = details['prereq'] || {}

            Array(prereq['feat']).concat(Array(prereq['orfeat'])).each do |wanted|
              expect(known).to include(wanted.to_s.downcase), "#{name} asks for #{wanted.inspect}"
            end
          end
        end

        # Every name a `feature` prereq asks for is one a class table grants: a feature, or an
        # option of a class choice.
        it "should name only features a class grants" do
          granted = []

          collect = lambda do |node|
            case node
            when Hash
              node.each_pair do |key, value|
                granted.concat(Array(value).map(&:to_s)) if key.to_s == 'charclass_feature'
                granted.concat(value['options'].keys) if %w(charclass_choice choose).include?(key.to_s) && value.is_a?(Hash) && value['options'].is_a?(Hash)
                collect.call(value)
              end
            when Array
              node.each { |item| collect.call(item) }
            end
          end

          %w(class specialty).each { |file| collect.call(YAML.load_file("game/config/pf2e_#{file}.yml")) }

          @feats.each_pair do |name, details|
            Array((details['prereq'] || {})['feature']).each do |wanted|
              expect(granted).to include(wanted), "#{name} asks for the feature #{wanted.inspect}"
            end
          end
        end

        it "should ask for what each feat's text names" do
          {
            'Heal Mount' => { 'level' => 8, 'feat' => [ 'Faithful Steed' ], 'focus_spell' => [ 'Lay on Hands' ] },
            'Rejuvenating Touch' => { 'level' => 18, 'focus_spell' => [ 'Lay on Hands' ] },
            'Discordant Voice' => { 'level' => 18, 'focus_spell' => [ 'Courageous Anthem' ] },
            'Restorative Channel' => { 'level' => 8, 'divine_font' => [ 'heal' ] },
            'Heroic Recovery' => { 'level' => 10, 'divine_font' => [ 'heal' ] },
            'Fast Channel' => { 'level' => 14, 'divine_font' => [ 'heal', 'harm' ] },
            'Perfect Form Control' => { 'level' => 18, 'feat' => [ 'Form Control' ], 'ability' => [ 'Strength/18' ] },
            "Champion's Sacrifice" => { 'level' => 12 },
            'Reflexive Riposte' => { 'level' => 10, 'feature' => [ 'Opportune Riposte' ] },
            'Impossible Riposte' => { 'level' => 14, 'feature' => [ 'Opportune Riposte' ] },
            'Parry and Riposte' => { 'level' => 18, 'feature' => [ 'Opportune Riposte' ] },
            'Radiant Armament' => { 'level' => 10, 'feature' => [ 'Blessed Armament' ] },
            'Armament Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Armament' ] },
            'Shield Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Shield' ] },
            'Spectral Advance' => { 'level' => 10, 'feature' => [ 'Blessed Swiftness' ] },
            'Swift Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Swiftness' ] },
            'Bloodline Perfection' => { 'level' => 20, 'feature' => [ 'Bloodline Paragon' ] },
            'Sanctify Armament' => { 'level' => 8, 'sanctification' => [ 'holy', 'unholy' ] },
            'Aura of Faith' => { 'level' => 12, 'sanctification' => [ 'holy', 'unholy' ] },
            'Aura of Righteousness' => { 'level' => 14, 'sanctification' => [ 'holy' ] },
            'Eternal Blessing' => { 'level' => 16, 'sanctification' => [ 'holy' ] },
            'Eternal Bane' => { 'level' => 16, 'sanctification' => [ 'unholy' ] },
            'Prevailing Position' => { 'level' => 10, 'stances' => 1 },
            'Fuse Stance' => { 'level' => 16, 'stances' => 2 },
            'Interweave Dispel' => { 'level' => 14, 'repertoire_spell' => [ 'Dispel Magic' ] },
            'Enhanced Familiar' => { 'level' => 2, 'familiar' => true }
          }.each_pair do |name, prereq|
            expect(feat(name)['prereq']).to eq(prereq), name
          end
        end

        it "should name each class's own version of a feat that has one per class" do
          {
            'Implausible Purchase (Investigator)' => 'Predictive Purchase (Investigator)',
            'Implausible Purchase (Rogue)' => 'Predictive Purchase (Rogue)',
            'Ricochet Feint' => 'Ricochet Stance (Rogue)',
            'Advanced Efficient Alchemy' => 'Efficient Alchemy (Alchemist)',
            'Mature Animal Companion (Druid)' => 'Animal Companion',
            'Incredible Companion (Druid)' => 'Mature Animal Companion (Druid)',
            'Incredible Companion (Ranger)' => 'Mature Animal Companion (Ranger)'
          }.each_pair do |name, wanted|
            expect(feat(name)['prereq']['feat']).to eq([ wanted ]), name
          end

          expect(feat('Master of Many Styles')['prereq']['orfeat']).to eq [ 'Opening Stance', 'Reflexive Stance' ]
        end

        # Enhanced Familiar asks for a familiar, however the character came by it. Pet only mentions
        # a familiar gained later, which "you gain a familiar" does not match.
        it "should flag every feat whose text gives a familiar, and only those" do
          @feats.each_pair do |name, details|
            gives = details['shortdesc'].to_s.match?(/\byou gain a familiar\b/i)

            expect(details['familiar'] == true).to eq(gives), name
          end
        end
      end

      # Player Core p. 186.
      it "should give Witch's Armaments its three unarmed attacks, one per taking" do
        details = feat("Witch's Armaments")
        attacks = details['feat_choice']['options'].transform_values { |option| option['grants']['attack'] }

        expect(details['repeatable']).to be true
        expect(attacks).to eq(
          'Eldritch Nails' => { 'Nails' => { 'damage' => '1d6', 'damage_type' => 'S', 'group' => 'Brawling',
                                             'traits' => [ 'agile', 'unarmed' ] } },
          'Iron Teeth' => { 'Jaws' => { 'damage' => '1d8', 'damage_type' => 'P', 'group' => 'Brawling',
                                        'traits' => [ 'unarmed' ] } },
          'Living Hair' => { 'Hair' => { 'damage' => '1d4', 'damage_type' => 'B', 'group' => 'Brawling',
                                         'traits' => [ 'agile', 'disarm', 'finesse', 'trip', 'unarmed' ] } }
        )
      end

      # "Choose a weapon group. You gain proficiency with all advanced weapons in that group as if
      # they were martial weapons of their weapon group."
      it "should let Advanced Weapon Training choose a group whose advanced weapons count as martial" do
        expect(feat('Advanced Weapon Training')['feat_choice']).to eq(
          'summary' => 'a weapon group', 'from_weapon_groups' => { 'category' => 'advanced' }, 'as_category' => 'martial'
        )
      end

      describe "spell books" do
        it "should give Esoteric Polymath a book of occult spells that keeps the repertoire" do
          expect(feat('Esoteric Polymath')['spell_book']).to eq(
            'name' => 'Book of Occult Spells', 'tradition' => 'occult', 'supplements' => 'Bard',
            'keeps_repertoire' => true, 'switch' => 'esotericpolymath'
          )
        end

        it "should give Arcane Evolution a list of arcane spells" do
          expect(feat('Arcane Evolution')['spell_book']).to eq(
            'name' => 'Arcane Evolution List', 'tradition' => 'arcane', 'supplements' => 'Sorcerer',
            'switch' => 'arcaneevolution'
          )
        end

        # A player types the feat's name to prepare from its book, and a switch cannot hold a space.
        it "should name each book's switch after its feat" do
          @feats.each_pair do |name, details|
            next unless details['spell_book']

            expect(details['spell_book']['switch']).to eq(name.downcase.gsub(/[^a-z]/, '')), name
          end
        end

        # "You become trained in one skill of your choice."
        it "should give Arcane Evolution a skill of the player's choice" do
          expect(feat('Arcane Evolution')['grants']).to eq('skill' => [ 'open' ])
        end

        # Player Core p. 258: a success is a critical success, and a failure can be tried again
        # after a week or a level.
        it "should give Magical Shorthand its Learn a Spell rules" do
          expect(feat('Magical Shorthand')['learn_spell']).to eq('upgrade_success' => true, 'retry_after_days' => 7)
        end

        # Player Core p. 201.
        it "should give Spellbook Prodigy Magical Shorthand, prerequisites waived, and soften a critical failure" do
          prodigy = feat('Spellbook Prodigy')

          expect(prodigy['assoc_charclass']).to eq [ 'Wizard' ]
          expect(prodigy['prereq']).to eq('level' => 1, 'skill' => 'Arcana/trained')
          expect(prodigy['grants']).to eq('feat' => [ { 'name' => 'Magical Shorthand', 'prereqs' => 'ignore' } ])
          expect(prodigy['learn_spell']).to eq('soften_critical_failure' => true)
        end

        # Player Core p. 230, the Learning a Spell table: rank => [ price in gp, typical DC ].
        it "should price Learn a Spell by rank" do
          expect(@magic['learn_spell']).to eq(
            'cantrip' => [ 2, 15 ], 1 => [ 2, 15 ], 2 => [ 6, 18 ], 3 => [ 16, 20 ], 4 => [ 36, 23 ],
            5 => [ 70, 26 ], 6 => [ 140, 28 ], 7 => [ 300, 31 ], 8 => [ 650, 34 ], 9 => [ 1500, 36 ],
            10 => [ 7000, 41 ]
          )
        end
      end

      it "should give Signature Spell Expansion two signatures of 3rd rank or lower" do
        stats = feat('Signature Spell Expansion')['magic_stats']

        expect(stats).to eq('signature_spells' => { 'up to 3' => 2 })
        expect(Pf2emagic.any_rank_cap(stats['signature_spells'].keys.first)).to eq 3
      end
    end
  end
end
