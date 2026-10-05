require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the class feats whose effect is data hand over, once that data reaches the character.
    describe "class feat grants" do

      # Deep Lore and Greater Mental Evolution: "Add one spell to your repertoire of each spell rank
      # you can cast", and one more at each rank the character reaches later.
      describe "a repertoire spell of each rank" do
        it "should open one pick at each rank up to the highest" do
          expect(Pf2emagic.each_rank_picks(3, 1)).to eq('1' => [ 'open' ], '2' => [ 'open' ], '3' => [ 'open' ])
        end

        it "should open nothing for a character with no slots" do
          expect(Pf2emagic.each_rank_picks(0, 1)).to eq({})
        end

        it "should find the ranks a level's slots reach for the first time" do
          committed = (1..8).map(&:to_s)

          expect(Pf2e.new_spell_ranks(committed, { 9 => 2, 'cantrip' => 5 })).to eq [ '9' ]
          expect(Pf2e.new_spell_ranks(committed, { '8' => 4 })).to eq []
          expect(Pf2e.new_spell_ranks(committed, nil)).to eq []
        end
      end

      describe "on a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Grants#{rand(1000000)}")
          @char.update(:pf2_base_info => { 'charclass' => 'Sorcerer' }, :pf2_level => 16)

          slots = (1..8).each_with_object({}) { |rank, per_day| per_day[rank.to_s] = 4 }
          @magic = PF2Magic.create(:character => @char, :spells_per_day => { 'Sorcerer' => slots })
          @char.update(:magic => @magic)
        end

        after(:each) do
          @combat.delete if @combat
          @magic.delete if @magic
          @char.delete if @char
        end

        def feat_magic(name)
          Global.read_config('pf2e_feats', name, 'magic_stats')
        end

        describe "Greater Mental Evolution" do
          it "should open a repertoire pick at each rank the character casts" do
            to_assign = PF2Magic.update_magic(@char, 'Sorcerer', feat_magic('Greater Mental Evolution'), nil)

            expect(to_assign['repertoire'].keys).to eq (1..8).map(&:to_s)
            expect(to_assign['repertoire'].values.uniq).to eq [ [ 'open' ] ]
          end

          # Taken at 17th level, where the level itself opens 9th-rank slots.
          it "should count a rank the level-up in progress opens" do
            @char.update(:advancing => true, :pf2_advancement => { 'magic_stats' => { 'spells_per_day' => { '9' => 2 } } })

            assessed = PF2Magic.assess_magic_stats(Character[@char.id], feat_magic('Greater Mental Evolution'))

            expect(assessed['magic_options']['repertoire'].keys).to eq (1..9).map(&:to_s)
          end

          it "should open a pick at a rank a later level reaches" do
            @char.update(:pf2_feats => { 'charclass' => [ 'Greater Mental Evolution' ] })

            to_assign = { 'repertoire' => { 9 => [ 'open', 'open' ] } }
            advancement = { 'magic_stats' => { 'spells_per_day' => { 9 => 2 } } }

            messages = Pf2e.open_each_rank_picks(Character[@char.id], to_assign, advancement)

            expect(to_assign['repertoire']).to eq('9' => [ 'open', 'open', 'open' ])
            expect(messages.size).to eq 1
            expect(messages.first).to include('Greater Mental Evolution', '9th-rank')
          end

          it "should open nothing at a level that reaches no new rank" do
            @char.update(:pf2_feats => { 'charclass' => [ 'Greater Mental Evolution' ] })

            to_assign = {}

            expect(Pf2e.open_each_rank_picks(Character[@char.id], to_assign, { 'magic_stats' => { 'spells_per_day' => { '8' => 4 } } })).to eq []
            expect(to_assign).to eq({})
          end

          it "should open nothing for a character without the feat" do
            to_assign = {}

            expect(Pf2e.open_each_rank_picks(Character[@char.id], to_assign, { 'magic_stats' => { 'spells_per_day' => { '9' => 2 } } })).to eq []
          end
        end

        it "should add a 10th-rank slot to the one the class gives" do
          @magic.update(:spells_per_day => { 'Sorcerer' => { '10' => 1 } })

          PF2Magic.update_magic(@char, 'Sorcerer', feat_magic('Bloodline Perfection'), nil)

          expect(PF2Magic[@magic.id].spells_per_day['Sorcerer']['10']).to eq 2
        end

        # A signature designated this level joins those already held at its rank.
        it "should keep the signature spells already held at a rank" do
          @magic.update(:signature_spells => { 'Sorcerer' => { '1' => [ 'Fear' ] } })

          Advancement::Apply.designate_signatures(:char => Character[@char.id], :charclass => 'Sorcerer',
                                                  :value => { '1' => [ 'Charm' ], 'up to 3' => [] })

          expect(PF2Magic[@magic.id].signature_spells['Sorcerer']['1']).to eq [ 'Fear', 'Charm' ]
        end

        describe "Monastic Weaponry" do
          before(:each) do
            @combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'unarmed' => 'trained', 'simple' => 'trained' })
            @char.update(:combat => @combat)

            Pf2eCombat.update_combat_stats(@char, Global.read_config('pf2e_feats', 'Monastic Weaponry', 'grants')['combat_stats'])
          end

          def prof(weapon)
            Pf2eCombat.get_weapon_prof(Character[@char.id], weapon)
          end

          def unarmed(rank)
            combat = Pf2eCombat[@combat.id]

            combat.update(:weapon_prof => combat.weapon_prof.merge('unarmed' => rank))
          end

          it "should train a martial monk weapon" do
            expect(prof('Bo Staff')).to eq 'trained'
          end

          it "should leave a martial weapon without the monk trait alone" do
            expect(prof('Longsword')).to eq 'untrained'
          end

          it "should follow the unarmed rank" do
            unarmed('expert')

            expect(prof('Bo Staff')).to eq 'expert'
          end

          it "should stop at master" do
            unarmed('legendary')

            expect(prof('Bo Staff')).to eq 'master'
          end
        end
      end
    end
  end
end
