require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Split Slot (Wizard 6), Spell Combination and Spell Mastery (Wizard 20): what a prepared slot
    # holds, each prepared through the switch its feat's data names.
    describe "feats that change what a slot holds" do

      describe "the data" do
        before(:all) do
          @feats = {}
          %w(ancestry class dedication general skill).each do |file|
            @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
          end
        end

        def switches(key)
          @feats.filter_map { |_name, details| details[key].is_a?(Hash) ? details[key]['switch'] : nil }
        end

        it "should give each feat its own switch" do
          ours = switches('prepared_slot') + switches('mastered_spells')

          expect(ours.sort).to eq %w(spellcombination spellmastery splitslot)
        end

        # A switch both a book and a slot feat declared would route to one and never the other.
        it "should share no switch with a book a feat keeps" do
          expect(switches('spell_book') & switches('prepared_slot')).to eq []
        end
      end

      describe "the rules" do
        split = { 'cast' => 'either', 'count' => 1, 'below_top' => 1 }
        combination = { 'cast' => 'both', 'per_rank' => 1, 'min_rank' => 3, 'components_below' => 2 }

        it "should keep Split Slot at least one rank below the highest" do
          expect(SlotFeats.rank_refusal(split, 4, 5, [])).to be_nil
          expect(SlotFeats.rank_refusal(split, 5, 5, []).key).to eq 'pf2emagic.slot_pair_rank_too_high'
        end

        it "should allow one Split Slot in all" do
          expect(SlotFeats.rank_refusal(split, 2, 5, [ '4' ]).key).to eq 'pf2emagic.slot_pair_all_used'
        end

        it "should keep Spell Combination to rank 3 and up, one at each rank" do
          expect(SlotFeats.rank_refusal(combination, 2, 9, []).key).to eq 'pf2emagic.slot_pair_rank_too_low'
          expect(SlotFeats.rank_refusal(combination, 9, 9, [ '8' ])).to be_nil
          expect(SlotFeats.rank_refusal(combination, 9, 9, [ '9' ]).key).to eq 'pf2emagic.slot_pair_rank_full'
        end

        it "should cast a combination's spells two ranks below its slot" do
          expect(SlotFeats.cast_rank(combination, 9)).to eq 7
          expect(SlotFeats.cast_rank(split, 4)).to eq 4
        end

        mastery = { 'count' => 4, 'max_rank' => 9 }

        it "should master four spells, each of a different rank of 9 or lower" do
          four = { '1' => 'A', '2' => 'B', '3' => 'C', '4' => 'D' }

          expect(SlotFeats.mastery_refusal(mastery, '5', four).key).to eq 'pf2emagic.mastery_all_used'
          expect(SlotFeats.mastery_refusal(mastery, '3', four)).to be_nil
          expect(SlotFeats.mastery_refusal(mastery, '10', {}).key).to eq 'pf2emagic.mastery_rank_too_high'
        end
      end

      describe "on a wizard", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Slots#{rand(1000000)}")
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

        def wizard(feats, top: 5, per_rank: 2)
          per_day = (1..top).each_with_object({}) { |rank, out| out[rank.to_s] = per_rank }
          book = { '1' => [ 'Force Barrage', 'Charm', 'Fear' ], '3' => [ 'Blindness', 'Slow', 'Fireball', 'Haste' ] }
          magic = PF2Magic.create(:character => @char,
                                  :tradition => { 'Wizard' => [ 'arcane', 'trained' ] },
                                  :spell_abil => { 'Wizard' => 'Intelligence' },
                                  :spells_per_day => { 'Wizard' => per_day },
                                  :spellbook => { 'Wizard' => book })

          @char.update(:magic => magic, :pf2_level => top * 2, :pf2_feats => { 'charclass' => feats },
                       :pf2_base_info => { 'charclass' => 'Wizard' })
        end

        def found(switch)
          SlotFeats.for_switch(char, switch)
        end

        def pair(switch, rank, spells)
          SlotFeats.prepare_pair(char, found(switch), rank, spells)
        end

        def cast(spell, level = nil)
          Pf2emagic.cast_spell(char, 'Wizard', spell, [], level)
        end

        it "should route the feats' switches, and not a book's" do
          expect(SlotFeats.switch?('splitslot')).to eq true
          expect(SlotFeats.switch?('esotericpolymath')).to eq false
        end

        it "should find no feat for a switch the wizard lacks" do
          wizard([])

          expect(found('splitslot')).to be_nil
        end

        describe "Split Slot" do
          before(:each) { wizard([ 'Split Slot' ]) }

          it "should prepare two spells in one slot" do
            outcome = pair('splitslot', 3, [ 'Slow', 'Haste' ])

            expect(outcome.state).to include('rank' => '3', 'spells' => [ 'Slow', 'Haste' ], 'cast' => 'either')
          end

          it "should refuse a spell not in the spellbook" do
            expect(pair('splitslot', 3, [ 'Slow', 'Heal' ]).key).to eq 'pf2emagic.slot_pair_spell_refused'
          end

          it "should take one of the rank's slots" do
            pair('splitslot', 3, [ 'Slow', 'Haste' ])

            expect(Pf2emagic.prepare_spell('Fireball', char, 'Wizard', '3')).to be_a Hash
            expect(Pf2emagic.prepare_spell('Blindness', char, 'Wizard', '3')).to eq t('pf2emagic.no_available_slots')
          end

          it "should not go in a full rank" do
            Pf2emagic.prepare_spell('Fireball', char, 'Wizard', '3')
            Pf2emagic.prepare_spell('Blindness', char, 'Wizard', '3')

            expect(pair('splitslot', 3, [ 'Slow', 'Haste' ]).key).to eq 'pf2emagic.slot_pair_no_slot'
          end

          it "should cast either spell after a rest, and lose the other" do
            pair('splitslot', 3, [ 'Slow', 'Haste' ])
            Pf2emagic.generate_spells_today(char)

            stats = cast('Haste', '3')

            expect(stats['spell name']).to eq 'Haste'
            expect(stats['spell level']).to eq '3'
            expect(stats['spell type']).to eq 'Split Slot (3rd-rank slot)'
            expect(cast('Slow', '3')).to be_a String
          end

          it "should empty the slot" do
            pair('splitslot', 3, [ 'Slow', 'Haste' ])

            expect(SlotFeats.unprepare_pair(char, found('splitslot'), nil)).to be_ok
            expect(SlotFeats.pairs(char.magic, 'Wizard')).to eq []
          end
        end

        describe "Spell Combination" do
          before(:each) { wizard([ 'Spell Combination' ], :top => 9) }

          it "should prepare two spells to cast two ranks below the slot" do
            outcome = pair('spellcombination', 5, [ 'Slow', 'Blindness' ])

            expect(outcome.state).to include('rank' => '5', 'cast_rank' => '3', 'cast' => 'both')
          end

          it "should refuse a spell above that rank" do
            expect(pair('spellcombination', 4, [ 'Slow', 'Force Barrage' ]).key).to eq 'pf2emagic.slot_pair_spell_refused'
          end

          it "should allow one at each rank" do
            pair('spellcombination', 5, [ 'Slow', 'Blindness' ])

            expect(pair('spellcombination', 5, [ 'Charm', 'Fear' ]).key).to eq 'pf2emagic.slot_pair_rank_full'
            expect(pair('spellcombination', 6, [ 'Charm', 'Fear' ])).to be_ok
          end

          it "should cast both at once, naming either" do
            pair('spellcombination', 5, [ 'Slow', 'Blindness' ])
            Pf2emagic.generate_spells_today(char)

            stats = cast('Blindness')

            expect(stats['spell name']).to eq 'Slow + Blindness'
            expect(stats['spell level']).to eq '3'
            expect(cast('Slow')).to be_a String
          end
        end

        describe "Spell Mastery" do
          before(:each) { wizard([ 'Spell Mastery' ], :top => 9) }

          def master(spell, rank = nil)
            SlotFeats.master_spell(char, found('spellmastery'), rank, spell)
          end

          it "should prepare a mastered spell at every rest, in a slot of its own" do
            master('Fireball')
            Pf2emagic.prepare_spell('Slow', char, 'Wizard', '3')
            Pf2emagic.prepare_spell('Haste', char, 'Wizard', '3')
            Pf2emagic.generate_spells_today(char)

            expect(char.magic.spells_today['Wizard']['3']).to eq [ 'Haste', 'Slow', 'Fireball' ]
            expect(char.magic.spells_prepared['Wizard']['3']).to eq [ 'Haste', 'Slow' ]
          end

          it "should master a spell at a higher rank" do
            expect(master('Fireball', '5').state).to include('rank' => '5')
          end

          it "should replace the spell mastered at a rank" do
            master('Fireball')

            expect(master('Slow').state).to include('spell' => 'Slow', 'replaced' => 'Fireball')
          end

          it "should hold four at most" do
            master('Charm')
            master('Fireball')
            master('Slow', '4')
            master('Haste', '5')

            expect(master('Blindness', '6').key).to eq 'pf2emagic.mastery_all_used'
          end

          it "should refuse a spell not in the spellbook" do
            expect(master('Heal').key).to eq 'pf2emagic.slot_pair_spell_refused'
          end

          it "should forget a mastered spell" do
            master('Fireball')

            expect(SlotFeats.forget_mastered(char, found('spellmastery'), 'Fireball')).to be_ok
            expect(SlotFeats.mastered(char.magic, 'Wizard')).to eq({})
          end
        end
      end
    end
  end
end
