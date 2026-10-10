require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # A venom, a disease, a curse: a save as it is caught, a stage for a failure, and a save again as each
    # stage's time is up, moving it up or down until it ends.
    describe Afflictions do

      def wasp
        'Saving Throw DC 19 Fortitude%rMaximum Duration 6 rounds%rStage 1 no effect (1 round)%r' \
          'Stage 2 Clumsy 2 (1 round)%rStage 3 Paralyzed (1 round)'
      end

      it "should read its save, how long it can last, and each stage" do
        expect(Afflictions.read('Giant Wasp Venom', wasp, %w{poison})).to include(
          'name' => 'Giant Wasp Venom', 'dc' => 19, 'save' => 'fortitude', 'rounds' => 6, 'poison' => true,
          'stages' => [ { 'words' => 'no effect', 'conditions' => [], 'damage' => [], 'rounds' => 1 },
                        { 'words' => 'Clumsy 2', 'conditions' => [ { 'condition' => 'Clumsy', 'value' => 2 } ], 'damage' => [], 'rounds' => 1 },
                        { 'words' => 'Paralyzed', 'conditions' => [ { 'condition' => 'Paralyzed' } ], 'damage' => [], 'rounds' => 1 } ]
        )
      end

      it "should read a stage's damage, and a condition it names without a capital" do
        text = 'Saving Throw DC 16 Fortitude%rMaximum Duration 6 rounds%rStage 1 1d6 poison damage (1 round)%r' \
               'Stage 2 1d6 poison damage and stupefied 1 (1 round)'
        stage = Afflictions.read('Doru Venom', text, %w{poison})['stages'].last

        expect(stage['damage']).to eq [ %w{1d6 poison} ]
        expect(stage['conditions']).to eq [ { 'condition' => 'Stupefied', 'value' => 1 } ]
      end

      it "should read a stage that is as an earlier one" do
        text = 'Saving Throw DC 16 Fortitude%rStage 1 Enfeebled 1 (1 day)%rStage 2 as stage 1 (1 day)'
        stages = Afflictions.read('Fly Pox', text, %w{disease})['stages']

        expect(stages.last['conditions']).to eq stages.first['conditions']
        expect(stages.last['rounds']).to be_nil
      end

      it "should read an onset, a virulent one, and one found partway through an ability's words" do
        text = 'The ghoul whispers.%rForbidden Cravings (curse) A creature can still eat.%rSaving Throw DC 17 Will%r' \
               'Onset 1 day%rStage 1 Sickened 1 (1 day)'
        read = Afflictions.read('Ghoul Whispers', text, %w{curse virulent})

        expect(read).to include('dc' => 17, 'save' => 'will', 'onset' => '1 day', 'virulent' => true, 'poison' => false)
      end

      it "should have nothing to say of words with no stages" do
        expect(Afflictions.read('Bite', 'The wolf bites.', [])).to be_nil
      end

      describe "how a save moves a stage" do
        it "should take one off for a success and two for a critical success" do
          expect(Afflictions.step(Degree::SUCCESS, false, 0)).to eq(-1)
          expect(Afflictions.step(Degree::CRITICAL_SUCCESS, false, 0)).to eq(-2)
        end

        it "should add one for a failure and two for a critical failure" do
          expect(Afflictions.step(Degree::FAILURE, false, 0)).to eq 1
          expect(Afflictions.step(Degree::CRITICAL_FAILURE, false, 0)).to eq 2
        end

        it "should need two successes running against a virulent one, and take only one off for a critical success" do
          expect(Afflictions.step(Degree::SUCCESS, true, 0)).to eq 0
          expect(Afflictions.step(Degree::SUCCESS, true, 1)).to eq(-1)
          expect(Afflictions.step(Degree::CRITICAL_SUCCESS, true, 0)).to eq(-1)
        end
      end
    end

    describe "afflictions in a fight", :dbtest => true do
      include FightBench

      before(:each) do
        bench!(:hp => 200)
        add('giant wasp')
        next_turn
      end

      after(:each) { clear_bench! }

      def afflicted
        Afflictions.on(hero).first
      end

      # Giant Wasp: Stinger +12 with Giant Wasp Venom, DC 19 Fortitude.
      def stung(save)
        as(2, "strike #{@hero.name}", FightBench::HITS)
        @stung = heard
        as(2, "act giant wasp venom=#{@hero.name}", save) unless afflicted || heard.include?('Giant Wasp Venom')
      end

      it "should have whoever a venomous Strike hits save against the venom at once" do
        @dice = FightBench::HITS
        run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

        expect(heard).to include("#{@hero.name} rolls Fortitude", 'vs DC 19')
      end

      it "should leave whoever saves untouched" do
        as(2, "act giant wasp venom=#{@hero.name}", 1.0)

        expect(afflicted).to be_nil
      end

      it "should put whoever fails at stage 1, and whoever critically fails at stage 2" do
        as(2, "act giant wasp venom=#{@hero.name}", 0.6)
        expect(afflicted).to include('name' => 'Giant Wasp Venom', 'stage' => 1)

        clear = Afflictions.cure(hero, 'Giant Wasp Venom')
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)
        expect(afflicted['stage']).to eq 2
      end

      it "should leave a stage's conditions on them, named for the affliction" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)

        expect(Pf2e.condition_level(hero, 'Clumsy')).to eq 2
        expect(Pf2e.condition_labels(hero, false)).to include('Clumsy 2 (Giant Wasp Venom)')
      end

      it "should have them save again at the end of their turn once the stage's round is up, and move the stage" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)
        @dice = FightBench::LOW
        turn_to(@hero.name)
        @client.said.clear
        next_turn
        expect(afflicted['stage']).to eq 2

        turn_to(@hero.name)
        @client.said.clear
        next_turn

        expect(heard).to include("#{@hero.name} rolls Fortitude", 'Giant Wasp Venom')
        expect(afflicted['stage']).to eq 3
        expect(held).to have_key('Paralyzed')
        expect(held).to_not have_key('Clumsy')
      end

      it "should end when a save takes the stage below 1, and take its conditions with it" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)
        @dice = 1.0
        turn_to(@hero.name)
        next_turn
        turn_to(@hero.name)
        next_turn

        expect(afflicted).to be_nil
        expect(held).to_not have_key('Clumsy')
      end

      it "should end when it has lasted as long as it can" do
        as(2, "act giant wasp venom=#{@hero.name}", 0.6)
        @dice = 0.6
        8.times do
          turn_to(@hero.name)
          next_turn
        end

        expect(afflicted).to be_nil
      end

      it "should go up a stage for a poison caught again, and not start over" do
        as(2, "act giant wasp venom=#{@hero.name}", 0.6)
        as(2, "act giant wasp venom=#{@hero.name}", 0.6)

        expect(Afflictions.on(hero).size).to eq 1
        expect(afflicted['stage']).to eq 2
      end

      it "should deal a stage's damage as the stage is reached" do
        add('doru')
        before = hero_hp
        as(3, "act doru venom=#{@hero.name}", 0.6)

        expect(hero_hp).to be < before
        expect(heard).to include('poison')
      end

      it "should pass by a creature immune to poison" do
        add('skeleton guard')
        as(2, 'act giant wasp venom=#3', FightBench::LOW)

        expect(heard).to include('immune')
        expect(Afflictions.on(npc(3))).to eq []
      end

      it "should leave whoever a stage paralyzes unable to act" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)
        run(PF2EncounterAfflictionCmd, "e/affliction #{@hero.name}=giant wasp venom/3")
        hero_types('e/strike #2=fist')

        expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => @hero.name) ]
      end

      it "should leave a paralyzed creature unable to act too" do
        Pf2e.set_condition(npc, 'Paralyzed')
        as(2, "strike #{@hero.name}")

        expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => 'Giant Wasp #2') ]
      end

      it "should remind them of it as their turn starts" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)

        expect(Turns.reminder(hero, 1)).to include('Giant Wasp Venom', 'stage 2')
      end

      it "should be the GM's to cure, or set at a stage" do
        as(2, "act giant wasp venom=#{@hero.name}", FightBench::LOW)
        run(PF2EncounterAfflictionCmd, "e/affliction #{@hero.name}=giant wasp venom/3")
        expect(afflicted['stage']).to eq 3

        run(PF2EncounterAfflictionCmd, "e/affliction #{@hero.name}=giant wasp venom/0")
        expect(afflicted).to be_nil
        expect(held).to_not have_key('Paralyzed')
      end
    end
  end
end
