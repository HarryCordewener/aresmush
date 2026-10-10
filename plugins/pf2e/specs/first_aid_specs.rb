require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Administer First Aid, to stabilize the dying and to stop bleeding, and the assisted recovery that
    # gives anyone burning or bleeding another flat check.
    describe "first aid", :dbtest => true do
      include FightBench

      # A medic whose Medicine is +20, and a butcher whose Medicine is nothing.
      before(:each) do
        bench!
        add('Medic=ac 10 hp 20; skills medicine 20')
        add('Butcher=ac 10 hp 20; skills medicine 0')
        next_turn
      end

      after(:each) { clear_bench! }

      def dying
        Pf2e.condition_level(hero, 'Dying')
      end

      def bleeding
        PersistentDamage.held(hero).map { |one| one['type'] }
      end

      describe "to stabilize" do
        before(:each) do
          Pf2eHP.modify_damage(hero, Pf2eHP.get_max_hp(hero), false, true)
        end

        it "should be against 5 more than their recovery DC" do
          as(2, "act administer first aid=#{@hero.name}/stabilize")

          expect(heard).to include('vs DC 16')
        end

        it "should leave them no longer dying, unconscious still, and wounded for it" do
          as(2, "act administer first aid=#{@hero.name}/stabilize")

          expect(dying).to eq 0
          expect(held).to have_key('Unconscious')
          expect(Pf2e.condition_level(hero, 'Wounded')).to eq 1
          expect(heard).to include(t('pf2e.recovery_stable', :name => @hero.name).strip)
        end

        it "should leave them nearer death on a critical failure" do
          as(3, "act administer first aid=#{@hero.name}/stabilize", FightBench::LOW)

          expect(dying).to eq 2
        end

        it "should leave them as they are on a failure" do
          as(3, "act administer first aid=#{@hero.name}/stabilize", 0.7)

          expect(dying).to eq 1
        end
      end

      it "should not be tried on someone who is not dying, and cost nothing" do
        as(2, "act administer first aid=#{@hero.name}/stabilize")

        expect(refused).to eq [ t('pf2e.first_aid_not_dying', :target => @hero.name) ]
        expect(TurnState.turn(npc)['actions'].to_i).to eq 0
      end

      describe "to stop bleeding" do
        before(:each) { PersistentDamage.add(hero, '1d6', 'bleed') }

        it "should need the DC of what made them bleed" do
          as(2, "act administer first aid=#{@hero.name}/stop bleeding")

          expect(refused).to eq [ t('pf2e.first_aid_needs_dc', :target => @hero.name) ]
        end

        it "should give them a flat check against DC 10 on a success, which ends the bleeding where it is made" do
          as(2, "act administer first aid=#{@hero.name}/stop bleeding/20", 0.6)

          expect(heard).to include('12 against DC 10')
          expect(bleeding).to eq []
        end

        it "should leave them bleeding where that flat check fails" do
          as(2, "act administer first aid=#{@hero.name}/stop bleeding/20", 0.45)

          expect(heard).to include('9 against DC 10')
          expect(bleeding).to eq [ 'bleed' ]
        end

        it "should deal them their bleed at once on a critical failure" do
          before = hero_hp
          as(3, "act administer first aid=#{@hero.name}/stop bleeding/20", FightBench::LOW)

          expect(hero_hp).to eq before - 1
          expect(bleeding).to eq [ 'bleed' ]
        end
      end

      it "should not be tried to stop the bleeding of someone who is not bleeding" do
        as(2, "act administer first aid=#{@hero.name}/stop bleeding/20")

        expect(refused).to eq [ t('pf2e.first_aid_not_bleeding', :target => @hero.name) ]
      end

      # Two actions spent putting out the flames, or having them put out: another flat check, at once.
      describe "an assisted recovery" do
        before(:each) { PersistentDamage.add(hero, '1d6', 'fire') }

        it "should roll the flat check again, and end the damage where it is made" do
          hero_types('e/act assisted recovery', 0.8)

          expect(refused).to eq []
          expect(heard).to include('16 against DC 15')
          expect(bleeding).to eq []
        end

        it "should leave it where the check fails" do
          hero_types('e/act assisted recovery', 0.5)

          expect(bleeding).to eq [ 'fire' ]
        end

        it "should be against the DC the GM allows for help that is apt" do
          hero_types('e/act assisted recovery/10', 0.5)

          expect(heard).to include('10 against DC 10')
          expect(bleeding).to eq []
        end

        it "should cost two actions" do
          hero_types('e/act assisted recovery', 0.5)

          expect(TurnState.turn(hero)['actions']).to eq 2
        end

        it "should be given to another" do
          as(2, "act assisted recovery=#{@hero.name}", 0.8)

          expect(bleeding).to eq []
        end

        it "should be for the kind named, where they take more than one" do
          PersistentDamage.add(hero, '1d6', 'bleed')
          hero_types('e/act assisted recovery/bleed', 0.8)

          expect(bleeding).to eq [ 'fire' ]
        end

        it "should need the kind named, where they take more than one" do
          PersistentDamage.add(hero, '1d6', 'bleed')
          hero_types('e/act assisted recovery', 0.8)

          expect(refused).to eq [ t('pf2e.assisted_which', :kinds => 'fire, bleed') ]
        end
      end

      it "should not give a recovery to someone taking no persistent damage" do
        hero_types('e/act assisted recovery')

        expect(refused).to eq [ t('pf2e.assisted_nothing', :target => @hero.name) ]
      end
    end
  end
end
