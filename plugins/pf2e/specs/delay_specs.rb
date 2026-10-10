require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Delay: someone whose turn has begun waits. What ends their turn happens at once, they leave the
    # order until they say, and when they return - after another's turn - that is where they act from
    # then on. A round gone by without returning is a turn lost.
    describe "delaying", :dbtest => true do
      include FightBench

      # The order is an ogre warrior, a giant rat, and the hero.
      before(:each) do
        bench!
        add('ogre warrior')
        add('giant rat')
        run(PF2InitModCmd, 'encounter/mod #2=60')
        run(PF2InitModCmd, 'encounter/mod #3=50')
        run(PF2InitModCmd, "encounter/mod #{@hero.name}=40")
        next_turn
      end

      after(:each) { clear_bench! }

      def order
        Combatants.rows(encounter).map { |row| row['name'] }
      end

      def delaying?
        !TurnState.of(hero)['delaying'].nil?
      end

      it "should not be begun in someone else's turn" do
        hero_types('e/act delay')

        expect(refused).to eq [ t('pf2e.delay_not_turn', :actor => @hero.name) ]
      end

      describe "once begun" do
        before(:each) do
          turn_to(@hero.name)
          PersistentDamage.add(hero, '1d6', 'fire')
          @before = hero_hp
          hero_types('e/act delay', 0.5)
        end

        it "should say they wait, and how they return" do
          expect(refused).to eq []
          expect(heard).to include(t('pf2e.delay_begun', :actor => @hero.name).gsub(/%x\w/, ''))
          expect(delaying?).to be true
        end

        it "should have what ends their turn happen at once" do
          expect(hero_hp).to eq @before - 3
          expect(heard).to include('persistent fire damage')
        end

        it "should not have it happen again when the order moves on" do
          next_turn

          expect(hero_hp).to eq @before - 3
        end

        it "should leave them without their reaction while they wait" do
          expect(TurnState.turn(hero)['reaction']).to be true
        end

        describe "and returned from after another's turn" do
          before(:each) do
            next_turn
            next_turn
            hero_types('e/act delay')
          end

          it "should put them directly before whoever's turn it is, from here on" do
            expect(order).to eq [ 'Ogre Warrior #2', @hero.name, 'Giant Rat #3' ]
            expect(heard).to include(t('pf2e.delay_returned', :actor => @hero.name, :before => 'Giant Rat #3').gsub(/%x\w/, ''))
          end

          it "should give them their turn: three actions and their reaction" do
            expect(delaying?).to be false
            expect(TurnState.turn(hero)).to include('actions' => 0, 'reaction' => false)
          end

          it "should leave the turn that was running with whoever had it" do
            expect(ActiveEffects.current_turn(encounter)).to eq 'Giant Rat #3'
          end

          it "should bring their next turn where they now stand" do
            next_turn
            next_turn

            expect(ActiveEffects.current_turn(encounter)).to eq @hero.name
          end
        end

        it "should not be returned from before the order has moved on" do
          hero_types('e/act delay')

          expect(refused).to eq [ t('pf2e.delay_not_passed', :actor => @hero.name) ]
        end

        it "should be a turn lost where a round goes by, with their place unchanged" do
          3.times { next_turn }

          expect(ActiveEffects.current_turn(encounter)).to eq @hero.name
          expect(heard).to include(t('pf2e.delay_lost', :name => @hero.name))
          expect(delaying?).to be false
          expect(order).to eq [ 'Ogre Warrior #2', 'Giant Rat #3', @hero.name ]
        end
      end
    end
  end
end
