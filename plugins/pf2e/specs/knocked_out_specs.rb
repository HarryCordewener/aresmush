require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What becomes of someone reduced to no hit points, beyond their dying: when they next act, what they
    # can do meanwhile, and the blows that kill outright or do not kill at all.
    describe "being knocked out", :dbtest => true do
      include FightBench

      # A hero of 30 hit points, an ogre warrior (Ogre Hook +12, 1d10+7) first in the order and a giant
      # rat between them.
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

      def dying
        Pf2e.condition_level(hero, 'Dying')
      end

      # The ogre's hook with every die at its most: a critical hit for more than the hero has.
      def dropped_by_the_ogre
        as(2, "strike #{@hero.name}", 1.0)
      end

      describe "by a blow in someone else's turn" do
        before(:each) { dropped_by_the_ogre }

        it "should leave them dying" do
          expect(dying).to eq 2
        end

        # Last in the order is directly before the first.
        it "should leave them where they are, who already act directly before whoever's turn it was" do
          expect(order).to eq [ 'Ogre Warrior #2', 'Giant Rat #3', @hero.name ]
          expect(heard).to_not include('now acts')
        end

        it "should leave the turn with whoever had it" do
          expect(ActiveEffects.current_turn(encounter)).to eq 'Ogre Warrior #2'
        end

        it "should not move them again for being hit while they lie there" do
          as(2, "strike #{@hero.name}", 1.0)

          expect(heard).to_not include('now acts')
        end

        it "should not let them Strike, though the hit that dropped them is the last thing that happened" do
          hero_types('e/strike #2=claw')

          expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => @hero.name) ]
        end

        it "should not let them use an action that answers no hit" do
          hero_types('e/act stand')

          expect(refused).to eq [ t('pf2e.act_cannot_act', :actor => @hero.name) ]
        end
      end

      describe "in the turn of someone later in the order" do
        before(:each) do
          next_turn
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=40 slashing")
        end

        it "should move them to act directly before that one, and say so" do
          expect(order).to eq [ 'Ogre Warrior #2', @hero.name, 'Giant Rat #3' ]
          expect(heard).to include(t('pf2e.act_order_moved', :target => @hero.name, :before => 'Giant Rat #3').strip)
        end

        it "should leave the turn with whoever had it" do
          expect(ActiveEffects.current_turn(encounter)).to eq 'Giant Rat #3'
        end

        it "should come to their turn after everyone else has had theirs" do
          next_turn

          expect(ActiveEffects.current_turn(encounter)).to eq 'Ogre Warrior #2'

          next_turn

          expect(ActiveEffects.current_turn(encounter)).to eq @hero.name
        end
      end

      describe "in their own turn" do
        it "should leave them where they are in the order" do
          turn_to(@hero.name)
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=40 slashing")

          expect(order).to eq [ 'Ogre Warrior #2', 'Giant Rat #3', @hero.name ]
          expect(heard).to_not include('now acts')
        end
      end

      describe "a creature" do
        it "should stay where it is in the order" do
          run(PF2DamagePlayerCmd, 'damage #3=40 slashing')

          expect(order).to eq [ 'Ogre Warrior #2', 'Giant Rat #3', @hero.name ]
        end
      end

      # Damage of twice someone's hit points or more in one blow is death, whatever their dying.
      describe "by massive damage" do
        def twice
          Pf2eHP.get_max_hp(hero) * 2
        end

        it "should kill outright, from a Plotmaster" do
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=#{twice} slashing")

          expect(Pf2e.dead?(hero)).to be true
          expect(heard).to include(t('pf2e.act_dead', :target => @hero.name).strip)
        end

        it "should not kill at one less" do
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=#{twice - 1} slashing")

          expect(Pf2e.dead?(hero)).to be false
          expect(dying).to eq 1
        end

        it "should spare them where the damage may not kill" do
          run(PF2DamagePlayerCmd, "damage/ndc #{@hero.name}=#{twice} slashing")

          expect(Pf2e.dead?(hero)).to be false
          expect(heard).to include(t('pf2e.act_spared', :target => @hero.name).strip)
        end
      end

      # A nonlethal blow knocks out and does not kill.
      describe "by a nonlethal blow" do
        before(:each) do
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=35 bludgeoning nonlethal")
        end

        it "should leave them unconscious with no hit points, and not dying" do
          expect(dying).to eq 0
          expect(held).to have_key('Unconscious')
          expect(hero_hp).to eq 0
        end

        it "should say so" do
          expect(heard).to include(t('pf2e.act_knocked_out', :target => @hero.name).strip)
        end

        it "should not leave them wounded" do
          expect(Pf2e.condition_level(hero, 'Wounded')).to eq 0
        end

        it "should have them wake when they are healed" do
          run(PF2HealPlayerCmd, "heal #{@hero.name}=5")

          expect(held).to_not have_key('Unconscious')
        end

        it "should not kill, however hard" do
          run(PF2HealPlayerCmd, "heal #{@hero.name}=100")
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=500 bludgeoning nonlethal")

          expect(Pf2e.dead?(hero)).to be false
          expect(dying).to eq 0
        end

        it "should have no recovery check rolled for them" do
          turn_to(@hero.name)

          expect(heard).to_not include('recovery check')
        end
      end

      describe "by a creature's nonlethal Strike" do
        it "should leave them unconscious, and not dying" do
          add('Thug=ac 15 hp 30; strike sap +30 4d10 bludgeoning (nonlethal)')
          as(4, "strike #{@hero.name}", 0.5)

          expect(dying).to eq 0
          expect(held).to have_key('Unconscious')
        end
      end
    end
  end
end
