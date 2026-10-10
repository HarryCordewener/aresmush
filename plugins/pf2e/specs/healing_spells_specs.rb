require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Heal and Harm, each of which mends one kind of creature and hurts the other: whoever it mends rolls
    # nothing, whoever it hurts has a basic Fortitude save, and the 8 more that two actions give is for
    # the mending alone.
    describe "a spell that heals some and harms others", :dbtest => true do
      include FightBench

      # A grioth cultist (spell DC 20) with Heal and Harm prepared, a zombie shambler (Fortitude +6, weak
      # to vitality 5), and the living hero. Every die at half its faces is a 4 on the d8.
      before(:each) do
        bench!(:hp => 60)
        add('grioth cultist')
        add('zombie shambler')
        next_turn
        Pf2eHP.modify_damage(hero, 30, false, true)
        npc(3).update(:damage => 15)
        @client.said.clear
      end

      after(:each) { clear_bench! }

      def cast(text)
        as(2, "cast #{text}", 0.5)
      end

      describe "Heal" do
        it "should mend the living with one action, and roll no save for it" do
          cast("heal=#{@hero.name}/actions 1")

          expect(heard).to include("#{@hero.name} recovers 4")
          expect(heard).to_not include('rolls Fortitude')
        end

        it "should mend the living by 8 more with two" do
          cast("heal=#{@hero.name}/actions 2")

          expect(heard).to include("#{@hero.name} recovers 12")
          expect(heard).to_not include('rolls Fortitude')
        end

        it "should harm the undead with two, against a basic Fortitude save and without the 8" do
          cast('heal=#3/actions 2')

          expect(heard).to include('Zombie Shambler #3 rolls Fortitude', '9 vitality (weakness 5)')
        end

        it "should harm the undead with one, against the save" do
          cast('heal=#3/actions 1')

          expect(heard).to include('Zombie Shambler #3 rolls Fortitude', '9 vitality (weakness 5)')
        end
      end

      describe "Harm" do
        it "should mend the undead with two actions by 8 more, and roll no save for it" do
          cast('harm=#3/actions 2')

          expect(heard).to include('Zombie Shambler #3 recovers 12')
          expect(heard).to_not include('rolls Fortitude')
        end

        it "should mend the undead with one, and roll no save for it" do
          cast('harm=#3/actions 1')

          expect(heard).to include('Zombie Shambler #3 recovers 4')
          expect(heard).to_not include('rolls Fortitude')
        end

        it "should harm the living with two, against the save and without the 8" do
          cast("harm=#{@hero.name}/actions 2")

          expect(heard).to include("#{@hero.name} rolls Fortitude", '4 void')
        end
      end
    end
  end
end
