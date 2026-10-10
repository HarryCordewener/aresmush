require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Someone sickened spends an action retching: a Fortitude save against the DC of what sickened them,
    # which makes them less sickened by one on a success and by two on a critical success.
    describe "retching", :dbtest => true do
      include FightBench

      before(:each) { bench! }
      after(:each) { clear_bench! }

      def sickened
        Pf2e.condition_level(hero, 'Sickened')
      end

      # Ghoul Soldier: Stench, a DC 15 Fortitude save or Sickened 1.
      describe "by someone a creature's stench sickened" do
        before(:each) do
          add('ghoul soldier')
          next_turn
          as(2, "enter stench=#{@hero.name}", 0.3)
        end

        it "should roll Fortitude against the DC of what sickened them" do
          hero_types('e/act retch', FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include("#{@hero.name} uses Retch", 'Fortitude', 'vs DC 15')
        end

        it "should leave them less sickened on a success" do
          hero_types('e/act retch', FightBench::HIGH)

          expect(sickened).to eq 0
        end

        it "should leave them as sickened on a failure" do
          hero_types('e/act retch', FightBench::LOW)

          expect(sickened).to eq 1
        end

        it "should cost an action" do
          hero_types('e/act retch', FightBench::LOW)

          expect(TurnState.turn(hero)['actions']).to eq 1
        end
      end

      describe "by someone the GM sickened" do
        before(:each) do
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=sickened/2")
        end

        it "should need the DC, which the game was never given" do
          hero_types('e/act retch')

          expect(refused).to eq [ t('pf2e.act_needs_dc', :action => 'Retch', :condition => 'Sickened') ]
          expect(TurnState.turn(hero)['actions'].to_i).to eq 0
        end

        it "should take the DC they name, and ease by one on a success" do
          hero_types('e/act retch/10')

          expect(sickened).to eq 1
        end

        it "should ease by two on a critical success" do
          hero_types('e/act retch/5', FightBench::HIGH)

          expect(sickened).to eq 0
        end
      end

      it "should be refused to someone who is not sickened" do
        hero_types('e/act retch/15')

        expect(refused).to eq [ t('pf2e.act_not_condition', :action => 'Retch', :condition => 'Sickened') ]
      end
    end
  end
end
