require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Divine Access (the Oracle's 11th-level feature, Player Core 2) and Mysterious Repertoire
    # (Oracle 14): spells from beyond the divine list in an Oracle's repertoire.
    describe "divine access" do

      describe "the data" do
        before(:all) do
          @deities = YAML.load_file("game/config/pf2e_deities.yml")['pf2e_deities']
          @specialty = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']
          @class = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']

          @spells = {}
          Dir.glob("game/config/pf2e_spells_*.yml").each { |file| @spells.merge!(YAML.load_file(file)['pf2e_spells']) }

          @feats = YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats']
        end

        # A name that is not a spell would be offered as a pick nothing can cast.
        it "should name a real spell for every deity's cleric spell" do
          missing = @deities.flat_map do |deity, info|
            Array(info['cleric_spells']).reject { |spell| @spells.key?(spell) }.map { |spell| "#{deity}: #{spell}" }
          end

          expect(missing).to eq []
        end

        it "should give every mystery at least one deity to choose" do
          @specialty['Oracle'].each_pair do |mystery, info|
            deities = @deities.select { |_d, d_info| (Array(d_info['domains']) & Array(info['domains'])).any? }

            expect(deities).to_not be_empty, "#{mystery} has no deity sharing its domains"
          end
        end

        it "should open at 11th level: a deity, then up to three of its cleric spells" do
          block = @class['Oracle']['advance'][11]['feat_choice']['Divine Access']

          expect(block['from']).to eq 'mystery_deities'
          expect(block['deity_spells']).to eq true

          steps = []
          step = block['then_choose']

          while step
            steps << step
            step = step['then_choose']
          end

          expect(steps.map { |s| s['from'] }).to eq %w(deity_cleric_spells) * 3
          expect(steps.map { |s| s['skip_if_empty'] }).to eq [ true ] * 3
        end

        it "should let Mysterious Repertoire hold one off-list spell" do
          expect(@feats['Mysterious Repertoire']['off_list_repertoire']).to eq 1
        end
      end

      describe "the tradition rule" do
        def check(extra)
          Pf2emagic::SpellPick.check({
            'list' => 'repertoire', 'rank' => '1', 'spell' => 'Force Barrage', 'tradition' => 'divine',
            'details' => { 'base_level' => 1, 'tradition' => [ 'arcane', 'occult' ] }, 'known' => {}
          }.merge(extra))
        end

        it "should refuse an off-list spell without room for one" do
          expect(check({}).key).to eq 'pf2emagic.class_does_not_get_spell'
        end

        it "should allow an off-list spell into a repertoire with room for one" do
          expect(check('off_list_room' => true)).to be_nil
        end

        it "should not open a spellbook to off-list spells" do
          expect(check('list' => 'spellbook', 'off_list_room' => true).key).to eq 'pf2emagic.class_does_not_get_spell'
        end
      end

      describe "on an oracle", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Access#{rand(1000000)}")

          per_day = (1..6).each_with_object({}) { |rank, out| out[rank.to_s] = 3 }
          magic = PF2Magic.create(:character => @char,
                                  :tradition => { 'Oracle' => [ 'divine', 'trained' ] },
                                  :spell_abil => { 'Oracle' => 'Charisma' },
                                  :spells_per_day => { 'Oracle' => per_day },
                                  :repertoire => { 'Oracle' => { '1' => [ 'Heal', 'Ill Omen' ] } })

          @char.update(:magic => magic, :pf2_level => 11,
                       :pf2_base_info => { 'charclass' => 'Oracle', 'specialize' => 'Ancestors' })
        end

        after(:each) do
          live = Character[@char.id]

          live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
          live.magic.delete if live.magic
          live.delete
        end

        def char
          Character[@char.id]
        end

        def block
          Pf2e.class_choice_block_for(char, 'Divine Access')
        end

        # The picks so far, as a level-up in progress holds them.
        def picked(labels)
          @char.update(:pf2_to_assign => { 'feat_choices' => { 'Divine Access' => labels } })
        end

        # The picks, as the ledger's fold records a finished level.
        def chosen(labels)
          @char.update(:pf2_level_tracker => { '11' => { 'feat_choices' => { 'Divine Access' => labels } } })
        end

        describe "Divine Access" do
          it "should open with the level" do
            info = Global.read_config('pf2e_class', 'Oracle', 'advance')[11]

            expect(Pf2e.granted_choice_names(info)).to include 'Divine Access'
          end

          it "should offer the deities who grant one of the mystery's domains" do
            expect(Pf2e.choice_options(char, 'Divine Access', block))
              .to eq %w(Althea Daeus Gunahkar Illotha Serriel Vardama)
          end

          it "should then offer that deity's cleric spells" do
            picked([ 'Althea' ])

            expect(Pf2e.choice_options(char, 'Divine Access', block['then_choose']))
              .to eq [ 'Containment', 'Soothe', 'Unfettered Pack' ]
          end

          it "should not offer a spell already picked" do
            picked([ 'Althea', 'Soothe' ])

            expect(Pf2e.choice_options(char, 'Divine Access', block['then_choose']['then_choose']))
              .to eq [ 'Containment', 'Unfettered Pack' ]
          end

          it "should close a step with nothing left to offer" do
            picked([ 'Althea', 'Soothe', 'Containment', 'Unfettered Pack' ])

            last = block['then_choose']['then_choose']

            expect(Pf2e.open_chained_choice(char, 'Divine Access', last)).to eq []
          end

          # The path advance/option takes: the step in hand, the option matched against it, then
          # the pick staged and the next step opened.
          it "should take a level-up from the deity through each of its spells" do
            to_assign = {}
            Pf2e.open_feat_choice(to_assign, 'Divine Access')
            @char.update(:advancing => true, :pf2_advancement => {}, :pf2_to_assign => to_assign)

            offered = [ 'Althea', 'Unfettered Pack', 'Soothe', 'Containment' ].map do |label|
              key, step = Pf2e.validate_feat_choice(char, 'Divine Access')
              options = Pf2e.choice_options(char, key, step)

              Pf2e.resolve_feat_choice(char, key, step, Pf2e.match_choice_option(char, key, step, label), nil)

              options
            end

            expect(offered[0]).to include('Althea', 'Vardama')
            expect(offered[1]).to eq [ 'Containment', 'Soothe', 'Unfettered Pack' ]
            expect(offered[3]).to eq [ 'Containment' ]

            expect(Pf2e.choice_labels_for(char, 'Divine Access')).to eq [ 'Althea', 'Unfettered Pack', 'Soothe', 'Containment' ]
            expect(Pf2e.validate_feat_choice(char, 'Divine Access')).to be_a(String)
            expect(Pf2emagic::Entries.known_at(char.magic, 'Oracle', '4')).to include('Containment')
          end

          it "should add the spells at their own ranks, once the oracle casts at them" do
            chosen([ 'Althea', 'Soothe', 'Containment', 'Unfettered Pack' ])

            magic = char.magic

            expect(Pf2emagic::Entries.known_at(magic, 'Oracle', '1')).to include('Soothe')
            expect(Pf2emagic::Entries.known_at(magic, 'Oracle', '4')).to include('Containment')
            expect(Pf2emagic::Entries.known_at(magic, 'Oracle', '6')).to_not include('Unfettered Pack')
          end

          it "should add a spell when the oracle reaches its rank" do
            chosen([ 'Althea', 'Unfettered Pack' ])
            char.magic.update(:spells_per_day => { 'Oracle' => char.magic.spells_per_day['Oracle'].merge('7' => 2) })

            expect(Pf2emagic::Entries.known_at(char.magic, 'Oracle', '7')).to include('Unfettered Pack')
          end

          it "should count the spells a level-up in progress picks" do
            picked([ 'Althea', 'Soothe' ])

            expect(Pf2emagic::Entries.known_at(char.magic, 'Oracle', '1')).to include('Soothe')
          end

          # Added through a choice rather than learned, so a level-up never records them.
          it "should leave them out of the lists a level-up records" do
            chosen([ 'Althea', 'Soothe', 'Containment' ])

            expect(Pf2emagic::Entries.known_lists(char)['Oracle']).to eq('1' => [ 'Heal', 'Ill Omen' ])
          end
        end

        describe "Mysterious Repertoire" do
          def mysterious
            @char.update(:pf2_feats => { 'charclass' => [ 'Mysterious Repertoire' ] })
          end

          def repertoire(spells)
            char.magic.update(:repertoire => { 'Oracle' => { '1' => spells } })
          end

          it "should leave no room without the feat" do
            expect(Pf2emagic.off_list_room?(char, 'Oracle')).to eq false
          end

          it "should leave room for one off-list spell" do
            mysterious

            expect(Pf2emagic.off_list_room?(char, 'Oracle')).to eq true
          end

          # Ill Omen is occult, and the Ancestors mystery grants it.
          it "should not count the mystery's own spells" do
            mysterious
            repertoire([ 'Heal', 'Ill Omen' ])

            expect(Pf2emagic.off_list_picks(char, 'Oracle')).to eq []
          end

          it "should leave no room once an off-list spell is held" do
            mysterious
            repertoire([ 'Heal', 'Force Barrage' ])

            expect(Pf2emagic.off_list_room?(char, 'Oracle')).to eq false
          end

          it "should leave room for a swap that gives the off-list spell up" do
            mysterious
            repertoire([ 'Heal', 'Force Barrage' ])

            expect(Pf2emagic.off_list_room?(char, 'Oracle', 'Force Barrage')).to eq true
          end

          it "should not count Divine Access's spells" do
            mysterious
            chosen([ 'Althea', 'Soothe', 'Containment' ])

            expect(Pf2emagic.off_list_room?(char, 'Oracle')).to eq true
          end

          it "should let a repertoire pick through the class's check" do
            mysterious

            expect(Pf2emagic.check_spell(char, 'Oracle', '1', 'Force Barrage', true)).to be_a(Array)
          end

          it "should refuse the same pick without the feat" do
            expect(Pf2emagic.check_spell(char, 'Oracle', '1', 'Force Barrage', true)).to be_a(String)
          end
        end
      end
    end
  end
end
