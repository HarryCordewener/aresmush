require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A character's speeds, worked out from their ancestry, heritage, feats and class rather than
    # stored: Speed and its breakdown, the special movement types and where each comes from, and the
    # status bonuses that depend on the moment.
    describe "Pf2e::Movement" do

      def entry(source, fields)
        fields.merge('source' => source)
      end

      def compute(entries = [], **options)
        Movement.compute(25, entries, **options)
      end

      def breastplate(**overrides)
        { 'name' => 'Breastplate', 'penalty' => -5, 'min_str' => 16, 'category' => 'medium' }.merge(overrides)
      end

      describe "Speed" do
        it "should be the ancestry's alone when nothing changes it" do
          result = compute

          expect(Movement.speed_text(result)).to eq '25 feet'
        end

        it "should add each increase and say where it came from" do
          result = compute([ entry('Fleet', 'increase' => 5), entry('Nimble Sil', 'increase' => 5) ])

          expect(Movement.speed_text(result)).to eq '35-ft (25-ft from ancestry, +5 ft from Fleet, +5 ft from Nimble Sil)'
        end

        # Nimble Hooves: "isn't cumulative with any Speed increase from other ancestry feats".
        it "should count only the largest increase in a group" do
          result = compute([
            entry('Nimble Hooves', 'increase' => 5, 'group' => 'ancestry'),
            entry('Nimble Sil', 'increase' => 5, 'group' => 'ancestry'),
            entry('Fleet', 'increase' => 5)
          ])

          expect(result['land']).to eq 35
        end
      end

      describe "special movement" do
        it "should say None. when there is none" do
          expect(Movement.special_text(compute)).to eq 'None.'
        end

        it "should name each type, its speed and its source" do
          result = compute([ entry('Makar heritage', 'swim' => 15), entry('Cave Climber', 'climb' => 10) ])

          expect(Movement.special_text(result)).to eq '15-ft swim speed (Makar heritage); 10-ft climb speed (Cave Climber)'
        end

        it "should keep only the highest source of a type" do
          result = compute([ entry('Makar heritage', 'swim' => 15), entry('Swift Swimmer', 'swim' => 25) ])

          expect(Movement.special_text(result)).to eq '25-ft swim speed (Swift Swimmer)'
        end

        it "should read equal to your Speed as your Speed" do
          result = compute([ entry('Fleet', 'increase' => 5), entry('Quick Climb', 'climb' => 'land') ])

          expect(Movement.special_text(result)).to eq '30-ft climb speed (Quick Climb)'
        end
      end

      describe "armor" do
        it "should take its penalty from every speed" do
          result = compute([ entry('Makar heritage', 'swim' => 15) ], :combat => true, :armor => breastplate)

          expect(Movement.speed_text(result)).to eq '20-ft (25-ft from ancestry, -5 ft from Breastplate)'
          expect(Movement.special_text(result)).to eq '10-ft swim speed (Makar heritage)'
        end

        it "should take 5 feet less from a character strong enough for it" do
          result = compute([], :combat => true, :armor => breastplate('penalty' => -10), :strength => 16)

          expect(Movement.speed_text(result)).to eq '20-ft (25-ft from ancestry, -5 ft from Breastplate)'
        end

        it "should take nothing once strength cancels a 5-foot penalty" do
          result = compute([], :combat => true, :armor => breastplate, :strength => 18)

          expect(Movement.speed_text(result)).to eq '25 feet'
        end

        it "should leave every speed at least 5 feet" do
          result = compute([ entry('Cave Climber', 'climb' => 10) ], :combat => true, :armor => breastplate('penalty' => -10))

          expect(result['special'].first['speed']).to eq 5
        end

        it "should not touch the speeds sheet shows" do
          result = compute([], :armor => breastplate)

          expect(Movement.speed_text(result)).to eq '25 feet'
        end
      end

      describe "conditional movement" do
        def monk_moves
          entry('Monk Moves', 'status_bonus' => 10, 'when' => 'unarmored')
        end

        it "should say None. when there is none" do
          expect(Movement.conditional_text(compute)).to eq 'None.'
        end

        it "should describe each bonus and its source" do
          expect(Movement.conditional_text(compute([ monk_moves ]))).to eq(
            "+10-foot status bonus when you're not wearing armor (Monk Moves)")
        end

        # Status bonuses do not stack, so the lower one says nothing.
        it "should keep only the highest bonus of each kind" do
          result = compute([ monk_moves, entry('Incredible Movement', 'status_bonus' => 15, 'when' => 'unarmored') ])

          expect(Movement.conditional_text(result)).to eq(
            "+15-foot status bonus when you're not wearing armor (Incredible Movement)")
        end

        it "should list panache bonuses beside it" do
          result = compute([
            entry('Vivacious Speed', 'status_bonus' => 15, 'when' => 'panache'),
            entry('Vivacious Speed', 'status_bonus' => 5, 'when' => 'no_panache')
          ])

          expect(Movement.conditional_text(result)).to eq(
            '+15-foot status bonus to your Speeds while you have panache (Vivacious Speed); ' \
            "+5-foot status bonus to your Speeds while you don't have panache (Vivacious Speed)")
        end

        it "should add the unarmored bonus to Speed on csheet when no armor is worn" do
          result = compute([ entry('Fleet', 'increase' => 5), monk_moves ], :combat => true)

          expect(Movement.speed_text(result)).to eq(
            '40-ft (25-ft from ancestry, +5 ft from Fleet, +10 ft status bonus while unarmored (Monk Moves))')
        end

        it "should count clothing as no armor" do
          clothing = { 'name' => "Explorer's Clothing", 'penalty' => 0, 'min_str' => 10, 'category' => 'unarmored' }

          expect(compute([ monk_moves ], :combat => true, :armor => clothing)['land']).to eq 35
        end

        it "should not add it while armor is worn" do
          expect(compute([ monk_moves ], :combat => true, :armor => breastplate)['land']).to eq 20
        end

        it "should not add it on sheet, which shows the permanent Speed" do
          expect(compute([ monk_moves ])['land']).to eq 25
        end

        it "should apply it to Speed alone and not the other movement types" do
          result = compute([ monk_moves, entry('Makar heritage', 'swim' => 15) ], :combat => true)

          expect(result['special'].first['speed']).to eq 15
        end

        it "should never apply panache, which nothing tracks" do
          result = compute([ entry('Stylish Combatant', 'status_bonus' => 5, 'when' => 'panache') ], :combat => true)

          expect(result['land']).to eq 25
        end
      end

      describe "for a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Mover#{rand(1000000)}", :pf2_level => 7,
            :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Ciith', 'heritage' => 'Makar' },
            :pf2_movement => { 'Size' => 'Medium', 'base_speed' => 25, 'Swim' => 15 })
        end

        after(:each) do
          @char.armor.each(&:delete) if @char
          @char.skills.each(&:delete) if @char
          Pf2e::Audit.delete_all!(@char) if @char
          @char.delete if @char
        end

        def holding(*feats)
          @char.update(:pf2_feats => { 'general' => feats })
        end

        def char
          Character[@char.id]
        end

        it "should name the heritage as the source of its movement" do
          expect(Movement.special_text(Movement.for(char))).to eq '15-ft swim speed (Makar heritage)'
        end

        it "should add a feat's increase and the heritage's better swim speed" do
          holding('Fleet', 'Swift Swimmer')

          result = Movement.for(char)

          expect(Movement.speed_text(result)).to eq '30-ft (25-ft from ancestry, +5 ft from Fleet)'
          expect(Movement.special_text(result)).to eq '25-ft swim speed (Swift Swimmer)'
        end

        it "should give Quick Climb's climb speed only at legendary Athletics" do
          holding('Quick Climb')
          Pf2eSkills.create_skill_for_char('Athletics', @char)
          Pf2eSkills.update_skill_for_char('Athletics', @char, 'master')

          expect(Movement.special_text(Movement.for(char))).to_not include('climb')

          Pf2eSkills.update_skill_for_char('Athletics', @char, 'legendary')

          expect(Movement.special_text(Movement.for(char))).to include('25-ft climb speed (Quick Climb)')
        end

        it "should give War Conditioning the movement that was chosen" do
          holding('War Conditioning')
          @char.update(:pf2_to_assign => { 'feat_choices' => { 'War Conditioning' => [ 'Swim' ] } })

          expect(Movement.special_text(Movement.for(char))).to eq '20-ft swim speed (War Conditioning)'
        end

        it "should give a monk Incredible Movement at the level reached" do
          @char.update(:pf2_base_info => @char.pf2_base_info.merge('charclass' => 'Monk'))
          holding('Monk Moves')

          result = Movement.for(char, :combat => true)

          expect(Movement.speed_text(result)).to eq(
            '40-ft (25-ft from ancestry, +15 ft status bonus while unarmored (Incredible Movement))')
          expect(Movement.conditional_text(result)).to eq(
            "+15-foot status bonus when you're not wearing armor (Incredible Movement)")
        end

        it "should take the equipped armor's penalty on csheet" do
          PF2Armor.create(:character => @char, :name => 'Breastplate', :speed_penalty => -5,
                          :min_str => 16, :category => 'medium', :equipped => true)

          result = Movement.for(char, :combat => true)

          expect(Movement.speed_text(result)).to eq '20-ft (25-ft from ancestry, -5 ft from Breastplate)'
          expect(Movement.special_text(result)).to eq '10-ft swim speed (Makar heritage)'
        end
      end

      # What the shipped feats and classes say, against what each feat's text grants.
      describe "the shipped data" do
        before(:all) do
          @feats = {}

          %w(ancestry class dedication general skill).each do |file|
            @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
          end

          @classes = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']
        end

        def movement(name)
          @feats.fetch(name)['movement']
        end

        it "should give the permanent feats their movement" do
          expect(movement('Fleet')).to eq [ { 'increase' => 5 } ]
          expect(movement('Nimble Sil')).to eq [ { 'increase' => 5, 'group' => 'ancestry' } ]
          expect(movement('Nimble Hooves')).to eq [ { 'increase' => 5, 'group' => 'ancestry' } ]
          expect(movement('Cave Climber')).to eq [ { 'climb' => 10 } ]
          expect(movement('Tree Climber (Sildanyar)')).to eq [ { 'climb' => 10 } ]
          expect(movement('Warren Digger')).to eq [ { 'burrow' => 15 } ]
          expect(movement('Soaring Form')).to eq [ { 'fly' => 20 } ]
          expect(movement('Swift Swimmer')).to eq [ { 'swim' => 15 }, { 'swim' => 25, 'prereq' => { 'heritage' => 'Makar' } } ]
          expect(movement("Gecko's Grip")).to eq [ { 'climb' => 15, 'prereq' => { 'heritage' => 'Pantli' } } ]
          expect(movement('Quick Climb')).to eq [ { 'climb' => 'land', 'prereq' => { 'skill' => [ 'Athletics/legendary' ] } } ]
          expect(movement('Quick Swim')).to eq [ { 'swim' => 'land', 'prereq' => { 'skill' => [ 'Athletics/legendary' ] } } ]
        end

        it "should offer War Conditioning's climb or swim as a choice" do
          options = @feats['War Conditioning']['feat_choice']['options']

          expect(options).to eq('Climb' => { 'movement' => [ { 'climb' => 20 } ] },
                                'Swim' => { 'movement' => [ { 'swim' => 20 } ] })
        end

        it "should give the status bonuses their condition" do
          expect(movement('Monk Moves')).to eq [ { 'status_bonus' => 10, 'when' => 'unarmored' } ]
          expect(movement("Swashbuckler's Speed")).to eq [
            { 'status_bonus' => 10, 'when' => 'panache' },
            { 'status_bonus' => 5, 'when' => 'no_panache' }
          ]
          expect(movement('Swashbuckler Dedication')).to eq [
            { 'status_bonus' => 5, 'when' => 'panache', 'source' => 'Stylish Combatant' }
          ]
        end

        it "should give the monk Incredible Movement at 3rd and every 4 levels after" do
          expected = { 3 => 10, 7 => 15, 11 => 20, 15 => 25, 19 => 30 }.map do |level, bonus|
            { 'level' => level, 'status_bonus' => bonus, 'when' => 'unarmored', 'source' => 'Incredible Movement' }
          end

          expect(@classes['Monk']['movement']).to eq expected
        end

        # Half the panache bonus without it, rounded down to 5 feet.
        it "should give the swashbuckler Stylish Combatant and Vivacious Speed" do
          vivacious = { 3 => [ 10, 5 ], 7 => [ 15, 5 ], 11 => [ 20, 10 ], 15 => [ 25, 10 ], 19 => [ 30, 15 ] }
            .flat_map do |level, (with, without)|
              [ { 'level' => level, 'status_bonus' => with, 'when' => 'panache', 'source' => 'Vivacious Speed' },
                { 'level' => level, 'status_bonus' => without, 'when' => 'no_panache', 'source' => 'Vivacious Speed' } ]
            end

          expect(@classes['Swashbuckler']['movement']).to eq(
            [ { 'level' => 1, 'status_bonus' => 5, 'when' => 'panache', 'source' => 'Stylish Combatant' } ] + vivacious)
        end
      end
    end
  end
end
