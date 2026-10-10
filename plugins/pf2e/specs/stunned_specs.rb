require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Stunned is paid off in actions: as a turn starts it takes as many actions as its value, and its
    # value falls by what it took. What it takes counts toward what slowed would.
    describe "being stunned", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        add('goblin warrior')
      end

      after(:each) { clear_bench! }

      def starts_turn
        @client.said.clear
        turn_to(@hero.name)
      end

      it "should take its value in actions from the turn, and be gone" do
        Pf2e.set_condition(hero, 'Stunned', 2)
        starts_turn

        expect(TurnState.actions(hero)).to eq 1
        expect(held).to_not have_key('Stunned')
        expect(heard).to include(t('pf2e.turn_stunned', :name => @hero.name, :lost => 2, :left => 0).strip)
      end

      it "should leave what the turn could not pay for the next" do
        Pf2e.set_condition(hero, 'Stunned', 4)
        starts_turn

        expect(TurnState.actions(hero)).to eq 0
        expect(Pf2e.condition_level(hero, 'Stunned')).to eq 1
      end

      it "should count toward what slowed takes, not on top of it" do
        Pf2e.set_condition(hero, 'Stunned', 1)
        Pf2e.set_condition(hero, 'Slowed', 2)
        starts_turn

        expect(TurnState.actions(hero)).to eq 1
      end

      it "should give the turn after its actions back" do
        Pf2e.set_condition(hero, 'Stunned', 1)
        starts_turn
        next_turn
        turn_to(@hero.name)

        expect(TurnState.actions(hero)).to eq 3
      end

      it "should be told by the turn's own count" do
        Pf2e.set_condition(hero, 'Stunned', 2)
        starts_turn

        expect(TurnState.summary(hero)).to include('0 of 1')
      end
    end
  end
end
