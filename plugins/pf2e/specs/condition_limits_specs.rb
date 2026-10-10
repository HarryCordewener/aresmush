require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What a condition stops someone doing, or puts at risk: the flat checks of the stupefied, the
    # deafened, the blinded and the dazzled, and what the prone, the raging, the fleeing, the confused,
    # the paralyzed and the sickened cannot do.
    describe "what a condition stops or risks", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        add('Dummy=ac 10 hp 200 will 0')
        next_turn
      end

      after(:each) { clear_bench! }

      def gm_sets(who, condition)
        run(PF2ConditionSetCmd, "condition/set #{who}=#{condition}")
        @client.said.clear
      end

      def spent
        TurnState.turn(hero)['actions'].to_i
      end

      describe "someone deafened" do
        before(:each) { gm_sets(@hero.name, 'deafened') }

        it "should lose an action that is auditory on a flat check of 4 or less, and have spent it" do
          hero_types('e/act demoralize=#2', 0.2)

          expect(heard).to include(t('pf2e.act_risk_lost', :actor => @hero.name, :condition => 'Deafened', :action => 'Demoralize',
                                                         :die => 4, :dc => 5).strip)
          expect(heard).to_not include('Intimidation')
          expect(spent).to eq 1
        end

        it "should keep it on a 5" do
          hero_types('e/act demoralize=#2', 0.25)

          expect(heard).to include('5 against DC 5', 'Intimidation')
        end

        it "should roll nothing for an action that is not auditory" do
          hero_types('e/strike #2=claw')

          expect(heard).to_not include('flat check')
        end
      end

      # Grioth Cultist: Fear prepared once.
      describe "someone stupefied" do
        before(:each) do
          add('grioth cultist')
          gm_sets('#3', 'stupefied/2')
        end

        it "should lose a spell on a flat check below 5 and its value, with the spell spent" do
          as(3, "cast fear=#{@hero.name}", 0.3)

          expect(heard).to include(t('pf2e.act_risk_lost', :actor => 'Grioth Cultist #3', :condition => 'Stupefied', :action => 'Fear',
                                                         :die => 6, :dc => 7).strip)
          expect(held).to_not have_key('Frightened')
          expect(TurnState.used(npc(3), 'Divine Prepared Spells: Fear')).to eq 1
          expect(TurnState.turn(npc(3))['actions']).to eq 2
        end

        it "should cast it on a check that makes it" do
          as(3, "cast fear=#{@hero.name}", 0.35)

          expect(heard).to include('7 against DC 7', 'casts Fear')
        end

        it "should roll nothing for what is no spell" do
          as(3, "strike #{@hero.name}")

          expect(heard).to_not include('flat check')
        end
      end

      describe "someone who cannot see" do
        it "should miss on an 10 or less on the flat check, blinded" do
          gm_sets(@hero.name, 'blinded')
          hero_types('e/strike #2=claw', 0.5)

          expect(heard).to include('blinded, flat check 10 vs DC 11', 'miss')
        end

        it "should roll the attack on an 11, blinded" do
          gm_sets(@hero.name, 'blinded')
          hero_types('e/strike #2=claw', 0.55)

          expect(heard).to include('vs AC 10')
        end

        it "should miss on a 4 or less, dazzled" do
          gm_sets(@hero.name, 'dazzled')
          hero_types('e/strike #2=claw', 0.2)

          expect(heard).to include('dazzled, flat check 4 vs DC 5', 'miss')
        end

        it "should roll the harder check where the target is hidden as well" do
          gm_sets(@hero.name, 'dazzled')
          run(PF2EncounterConcealCmd, 'e/conceal #2=hidden')
          hero_types('e/strike #2=claw', 0.5)

          expect(heard).to include('hidden, flat check 10 vs DC 11')
        end
      end

      describe "someone attacked by what they cannot see" do
        it "should be off-guard to it" do
          add('Brute=ac 10 hp 50; strike club +0 1d4 bludgeoning')
          as(3, "strike #{@hero.name}", 0.5)
          seen = heard[/vs AC (\d+)/, 1].to_i
          run(PF2EncounterConcealCmd, 'e/conceal #3=hidden')
          as(3, "strike #{@hero.name}", 0.5)

          expect(seen).to be > 0
          expect(heard[/vs AC (\d+)/, 1].to_i).to eq seen - 2
        end

        it "should see it once it has struck" do
          add('Brute=ac 10 hp 50; strike club +0 1d4 bludgeoning')
          run(PF2EncounterConcealCmd, 'e/conceal #3=hidden')
          as(3, "strike #{@hero.name}", 0.5)

          expect((encounter.concealment || {})['3']).to be_nil
          expect(heard).to include(t('pf2e.act_concealment_none', :target => 'Brute #3').strip)
        end

        it "should not see what only fog conceals for its having struck" do
          add('Brute=ac 10 hp 50; strike club +0 1d4 bludgeoning')
          run(PF2EncounterConcealCmd, 'e/conceal #3=concealed')
          as(3, "strike #{@hero.name}", 0.5)

          expect((encounter.concealment || {})['3']).to eq 'concealed'
        end
      end

      describe "someone prone" do
        before(:each) { gm_sets(@hero.name, 'prone') }

        it "should not use an action that moves them" do
          hero_types('e/act stride')

          expect(refused).to eq [ t('pf2e.act_prone', :actor => @hero.name, :action => 'Stride') ]
          expect(spent).to eq 0
        end

        it "should Crawl, and Stand" do
          hero_types('e/act crawl')
          hero_types('e/act stand')

          expect(refused).to eq []
          expect(held).to_not have_key('Prone')
        end
      end

      describe "someone raging" do
        before(:each) do
          ActiveEffects.apply(hero, 'Effect: Rage', :encounter => encounter)
          @client.said.clear
        end

        it "should not use an action that takes concentration" do
          hero_types('e/act demoralize=#2')

          expect(refused).to eq [ t('pf2e.act_raging', :actor => @hero.name, :action => 'Demoralize') ]
        end

        it "should Seek" do
          hero_types('e/act seek')

          expect(refused).to eq []
        end

        it "should Strike" do
          hero_types('e/strike #2=claw')

          expect(refused).to eq []
        end

        it "should Demoralize with Raging Intimidation" do
          @hero.update(:pf2_feats => { 'charclass' => [ 'Raging Intimidation' ] })
          hero_types('e/act demoralize=#2')

          expect(refused).to eq []
        end
      end

      describe "someone fleeing" do
        before(:each) { gm_sets(@hero.name, 'fleeing') }

        %w{Delay Ready}.each do |action|
          it "should not #{action}" do
            turn_to(@hero.name)
            hero_types("e/act #{action.downcase}")

            expect(refused).to eq [ t('pf2e.act_cannot_wait', :actor => @hero.name, :action => action, :condition => 'Fleeing') ]
          end
        end
      end

      describe "someone confused" do
        before(:each) { gm_sets(@hero.name, 'confused') }

        it "should not Delay" do
          turn_to(@hero.name)
          hero_types('e/act delay')

          expect(refused).to eq [ t('pf2e.act_cannot_wait', :actor => @hero.name, :action => 'Delay', :condition => 'Confused') ]
        end

        it "should roll a flat check when a Strike hurts them, and come out of it on an 11" do
          add('Brute=ac 10 hp 50; strike club +20 1d4 bludgeoning')
          as(3, "strike #{@hero.name}", 0.55)

          expect(heard).to include(t('pf2e.confused_ended', :target => @hero.name, :die => 11).strip)
          expect(held).to_not have_key('Confused')
        end

        it "should stay confused on a 10" do
          add('Brute=ac 10 hp 50; strike club +20 1d4 bludgeoning')
          as(3, "strike #{@hero.name}", 0.5)

          expect(heard).to include(t('pf2e.confused_goes_on', :target => @hero.name, :die => 10).strip)
          expect(held).to have_key('Confused')
        end

        it "should roll nothing for damage that is no attack or spell" do
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=3 slashing")

          expect(heard).to_not include('flat check')
        end
      end

      # Orc Veteran: Reactive Strike.
      describe "a confused creature" do
        it "should not use a reaction" do
          add('orc veteran')
          gm_sets('#3', 'confused')
          as(3, "act reactive strike=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.act_cannot_react', :actor => 'Orc Veteran #3', :action => 'Reactive Strike', :condition => 'Confused') ]
        end
      end

      describe "someone paralyzed" do
        before(:each) { gm_sets(@hero.name, 'paralyzed') }

        it "should not Strike" do
          hero_types('e/strike #2=claw')

          expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => @hero.name) ]
        end

        it "should Recall Knowledge, which takes only the mind" do
          hero_types('e/act recall knowledge=#2')

          expect(refused).to eq []
        end
      end

      describe "someone with a potion" do
        before(:each) do
          @potion = PF2Consumable.create(:name => 'Healing Potion (Lesser)', :quantity => 2, :character => @hero)
          encounter.states.each(&:delete)
          encounter.update(:participants => encounter.participants.reject { |row| row['char'] })
          Combatants.join(encounter, @hero.name, 10, :holder => Character[@hero.id])
          Pf2eHP.modify_damage(hero, 10, false, true)
        end

        after(:each) { PF2Consumable[@potion.id]&.delete }

        def drinks
          typed(Pf2egear::PF2EncounterUseCmd, 'e/use consumables=0', @hero, 0.5)
        end

        it "should drink it for an action, and be healed by it" do
          before = hero_hp
          drinks

          expect(refused).to eq []
          expect(hero_hp).to be > before
          expect(spent).to eq 1
        end

        it "should be healed by it where they name themselves as who takes it" do
          before = hero_hp
          typed(Pf2egear::PF2EncounterUseCmd, "e/use consumables=0/#{@hero.name}", @hero, 0.5)

          expect(refused).to eq []
          expect(hero_hp).to be > before
          expect(spent).to eq 1
        end

        it "should not drink it sickened" do
          gm_sets(@hero.name, 'sickened/1')
          drinks

          expect(refused).to eq [ t('pf2e.sickened_cannot_ingest', :target => @hero.name, :item => 'Healing Potion (Lesser)') ]
        end

        it "should not drink it unconscious" do
          gm_sets(@hero.name, 'unconscious')
          drinks

          expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => @hero.name) ]
        end
      end
    end
  end
end
