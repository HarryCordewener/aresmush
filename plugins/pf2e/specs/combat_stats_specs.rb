require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a class table's `combat_stats` block may say, and what happens to a key nobody handles.
    #
    # An unrecognised key is logged rather than dropped: a proficiency a class does not receive
    # leaves no trace on the sheet to notice.
    describe :update_combat_stats do

      def combat_for(char)
        Pf2eCombat.create(:character => char)
      end

      describe "an unknown key", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Stats#{rand(1000000)}")
          @combat = combat_for(@char)
          # `get_create_combat_obj` follows the character's reference, so without this it would
          # make a second combat object and write to that one instead.
          @char.update(:combat => @combat)
        end

        after(:each) do
          @combat.delete if @combat
          @char.delete if @char
        end

        it "should say so rather than dropping it" do
          expect(Global.logger).to receive(:error).with(/armor_light/)

          Pf2eCombat.update_combat_stats(@char, 'armor_light' => 'expert')
        end

        # The Rogue's table sets sneak_attack at chargen, 5, 11 and 17, and `roll sneak attack`
        # reads it off the combat object.
        it "should record sneak attack dice" do
          Pf2eCombat.update_combat_stats(@char, 'sneak_attack' => '2d6')

          expect(Pf2eCombat[@combat.id].sneak_attack).to eq '2d6'
        end

        it "should let a roll string use them" do
          Pf2eCombat.update_combat_stats(@char, 'sneak_attack' => '2d6')

          rolled = Pf2e.get_keyword_value(Character[@char.id], 'sneak attack')

          expect(rolled).to be_a Array
          expect(rolled.size).to eq 2
          expect(rolled).to all(be_between(1, 6))
        end

        it "should give nothing for a character with no sneak attack" do
          expect(Pf2e.get_keyword_value(Character[@char.id], 'sneak attack')).to eq 0
        end
      end

      # A class table names a proficiency at the level the class raises it, and cannot know that a
      # feat raised it further in between - an Oracle's 13th level says Reflex expert to an Oracle
      # whose Evasiveness made it master at 12th.
      describe "a rank already higher than the one written", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Ranks#{rand(1000000)}")
          @combat = Pf2eCombat.create(:character => @char,
            :saves => { 'fortitude' => 'trained', 'reflex' => 'master', 'will' => 'expert' },
            :weapon_prof => { 'simple' => 'expert', 'martial' => 'trained' },
            :perception => 'master', :class_dc => 'expert', :key_abil => 'Strength')
          @char.update(:combat => @combat)
        end

        after(:each) do
          @combat.delete if @combat
          @char.delete if @char
        end

        def combat
          Pf2eCombat[@combat.id]
        end

        it "should keep a save the table would lower" do
          Pf2eCombat.update_combat_stats(@char, 'saves' => { 'reflex' => 'expert' })

          expect(combat.saves['reflex']).to eq 'master'
        end

        it "should still raise the entries beside it" do
          Pf2eCombat.update_combat_stats(@char, 'saves' => { 'reflex' => 'expert', 'fortitude' => 'expert' })

          expect(combat.saves).to eq({ 'fortitude' => 'expert', 'reflex' => 'master', 'will' => 'expert' })
        end

        it "should keep a weapon rank the table would lower" do
          Pf2eCombat.update_combat_stats(@char, 'weapon_prof' => { 'simple' => 'trained', 'advanced' => 'trained' })

          expect(combat.weapon_prof).to eq({ 'simple' => 'expert', 'martial' => 'trained', 'advanced' => 'trained' })
        end

        it "should keep Perception and a class DC the table would lower" do
          Pf2eCombat.update_combat_stats(@char, 'perception' => 'expert', 'class_dc' => 'trained')

          expect(combat.perception).to eq 'master'
          expect(combat.class_dc).to eq 'expert'
        end

        it "should raise Perception past what it was" do
          Pf2eCombat.update_combat_stats(@char, 'perception' => 'legendary')

          expect(combat.perception).to eq 'legendary'
        end

        # A key ability is a choice rather than a rank, so the newest one stands.
        it "should still replace a value that is not a rank" do
          Pf2eCombat.update_combat_stats(@char, 'key_abil' => 'Dexterity')

          expect(combat.key_abil).to eq 'Dexterity'
        end

        # A weapon group holds a rank per category, one level deeper than weapon_prof.
        describe "a weapon group" do
          def mastery
            { 'simple' => 'master', 'martial' => 'master', 'unarmed' => 'master', 'advanced' => 'expert' }
          end

          before(:each) do
            @combat.update(:weapon_group_prof => { 'Sword' => mastery })
          end

          it "should keep the ranks a grant does not mention" do
            Pf2eCombat.update_combat_stats(@char, 'weapon_group_prof' => { 'Sword' => { 'advanced' => 'master' } })

            expect(combat.weapon_group_prof['Sword']).to eq mastery.merge('advanced' => 'master')
          end

          it "should not lower a rank" do
            Pf2eCombat.update_combat_stats(@char, 'weapon_group_prof' => { 'Sword' => { 'martial' => 'trained' } })

            expect(combat.weapon_group_prof['Sword']).to eq mastery
          end

          it "should leave another group alone" do
            Pf2eCombat.update_combat_stats(@char, 'weapon_group_prof' => { 'Axe' => { 'martial' => 'expert' } })

            expect(combat.weapon_group_prof).to eq('Sword' => mastery, 'Axe' => { 'martial' => 'expert' })
          end
        end

        # Resistances to one damage type from two sources do not stack; the higher applies.
        it "should keep the higher of two resistances and add a new one" do
          @combat.update(:defense => { 'resistance' => { 'fire' => 5 } })

          Pf2eCombat.update_combat_stats(@char, 'defense' => { 'resistance' => { 'fire' => 1, 'cold' => 1 } })

          expect(combat.defense).to eq('resistance' => { 'fire' => 5, 'cold' => 1 })
        end

        # An unarmed attack is a definition, so a new one of the same name replaces the old whole.
        it "should replace an unarmed attack rather than merge its fields" do
          @combat.update(:unarmed_attacks => {
            'Claw' => { 'damage' => '1d6', 'damage_type' => 'S', 'traits' => [ 'agile', 'Versatile (P)' ] }
          })

          Pf2eCombat.update_combat_stats(@char, 'unarmed_attacks' => { 'Claw' => { 'damage' => '1d8', 'damage_type' => 'S' } })

          expect(combat.unarmed_attacks).to eq('Claw' => { 'damage' => '1d8', 'damage_type' => 'S' })
        end
      end

      # The Fighter's two group choices, through the rows that apply them.
      describe "a Fighter's weapon group choices", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Groups#{rand(1000000)}")
          @combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'martial' => 'expert' })
          @char.update(:combat => @combat)
        end

        after(:each) do
          @combat.delete if @combat
          @char.delete if @char
        end

        def choose(feature, group)
          Advancement::Apply.feature_options(:char => Character[@char.id], :value => { feature => group })
        end

        def groups
          Pf2eCombat[@combat.id].weapon_group_prof
        end

        it "should keep the mastery group when the legend goes to another" do
          choose('Fighter Weapon Mastery', 'Sword')
          choose('Weapon Legend', 'Axe')

          expect(groups['Sword']).to eq('simple' => 'master', 'martial' => 'master', 'unarmed' => 'master', 'advanced' => 'expert')
          expect(groups['Axe']).to eq('simple' => 'legendary', 'martial' => 'legendary', 'unarmed' => 'legendary', 'advanced' => 'master')
        end

        it "should raise the mastery group when the legend goes to it" do
          choose('Fighter Weapon Mastery', 'Sword')
          choose('Weapon Legend', 'Sword')

          expect(groups['Sword']).to eq('simple' => 'legendary', 'martial' => 'legendary', 'unarmed' => 'legendary', 'advanced' => 'master')
        end

        # Only through the merging writer can a later choice never lower an earlier one.
        it "should not lower a group a stronger source already raised" do
          @combat.update(:weapon_group_prof => { 'Sword' => { 'martial' => 'legendary' } })

          choose('Fighter Weapon Mastery', 'Sword')

          expect(groups['Sword']['martial']).to eq 'legendary'
        end
      end

      # Every `combat_stats` key in every class's chargen and advance blocks has to be one the
      # writer writes, or the class never receives it. Proficiencies nest under `armor_prof` and
      # `weapon_prof`; a bare `light` or `martial` is not a key.
      describe "the shipped class tables" do
        def blocks_for(charclass)
          config = Global.read_config('pf2e_class', charclass) || {}
          advance = (config['advance'] || {}).each_with_object({}) { |(lv, b), out| out[lv.to_s] = b }

          { 'chargen' => config['chargen'] }.merge(advance)
        end

        it "should only use combat stats the writer knows how to write" do
          unknown = []

          (Global.read_config('pf2e_class') || {}).each_key do |charclass|
            blocks_for(charclass).each_pair do |where, block|
              next unless block.is_a?(Hash)

              stats = block['combat_stats']
              next unless stats.is_a?(Hash)

              (stats.keys.map(&:to_s) - Pf2eCombat::STAT_WRITERS.keys - [ 'archetype_class_dcs' ]).each do |key|
                unknown << "#{charclass} at #{where}: combat_stats.#{key}"
              end
            end
          end

          expect(unknown).to eq []
        end
      end
    end
  end
end
