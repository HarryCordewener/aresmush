require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Disarm, Grapple, Reposition, Shove and Trip are tried on nothing more than one size larger than
    # whoever tries, which Titan Wrestler raises.
    describe "the size of what can be wrestled", :dbtest => true do
      include FightBench

      before(:each) { bench! }
      after(:each) { clear_bench! }

      def too_large(action, target, most = 'one size')
        t('pf2e.act_too_large', :action => action, :target => target, :actor => @hero.name, :most => most)
      end

      # A brontosaurus is Gargantuan, and the hero Medium.
      describe "against something three sizes larger" do
        before(:each) { add('brontosaurus') }

        %w{Disarm Grapple Reposition Shove Trip}.each do |action|
          it "should refuse #{action}, and spend nothing on it" do
            hero_types("e/act #{action.downcase}=#2")

            expect(refused).to eq [ too_large(action, 'Brontosaurus #2') ]
            expect(TurnState.turn(hero)['actions'].to_i).to eq 0
          end
        end

        it "should allow an action that has no such limit" do
          hero_types('e/act demoralize=#2')

          expect(refused).to eq []
        end

        it "should still refuse someone with Titan Wrestler, who reaches two sizes" do
          @hero.update(:pf2_feats => { 'skill' => [ 'Titan Wrestler' ] })
          hero_types('e/act trip=#2')

          expect(refused).to eq [ too_large('Trip', 'Brontosaurus #2', 'two sizes') ]
        end

        it "should allow someone with Titan Wrestler who is legendary in Athletics" do
          @hero.update(:pf2_feats => { 'skill' => [ 'Titan Wrestler' ] })
          skill = Pf2eSkills.create(:name => 'Athletics', :prof_level => 'legendary', :character => @hero)
          hero_types('e/act trip=#2')
          skill.delete

          expect(refused).to eq []
        end
      end

      # A forest troll is Large.
      describe "against something one size larger" do
        before(:each) { add('forest troll') }

        it "should allow it" do
          hero_types('e/act trip=#2')

          expect(refused).to eq []
        end
      end

      # A giant rat is Small.
      describe "a creature" do
        before(:each) do
          add('giant rat')
          next_turn
        end

        it "should be held to it as a character is" do
          @hero.update(:pf2_movement => { 'Size' => 'L' })
          as(2, "act grapple=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.act_too_large', :action => 'Grapple', :target => @hero.name, :actor => 'Giant Rat #2',
                                                         :most => 'one size') ]
        end

        it "should wrestle someone one size larger" do
          as(2, "act grapple=#{@hero.name}")

          expect(refused).to eq []
        end
      end

      # A creature's size is its stat block's, and a character's their ancestry's as their effects leave it.
      describe "how big someone is" do
        it "should be Medium for a character whose ancestry does not say" do
          expect(MonsterAbilities.size_of(hero)).to eq 2
        end

        it "should be what a character's ancestry makes them" do
          @hero.update(:pf2_movement => { 'Size' => 'S' })

          expect(MonsterAbilities.size_of(hero)).to eq 1
        end

        it "should be a creature's stat block's" do
          add('brontosaurus')

          expect(MonsterAbilities.size_of(npc)).to eq 5
        end
      end
    end
  end
end
