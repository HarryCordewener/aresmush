require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # The abilities creatures share, played by the book: what each needs, what it rolls, and what it
    # leaves behind.
    describe MonsterAbilities do

      describe "an ability's first line" do
        it "should give its damage, each kind of it, and its save" do
          expect(MonsterAbilities.header('1d4 bludgeoning, 1d4 acid, DC 17 basic Fortitude%rThe monster deals...')).to include(
            'damage' => [ %w{1d4 bludgeoning}, %w{1d4 acid} ], 'dc' => 17, 'save' => 'fortitude', 'basic' => true
          )
        end

        it "should give the size it swallows and what cuts a way out" do
          expect(MonsterAbilities.header('Medium, (1d8+1) bludgeoning, 1d6 acid, Rupture 5%rThe monster attempts...')).to include(
            'size' => 'medium', 'damage' => [ %w{1d8+1 bludgeoning}, %w{1d6 acid} ], 'rupture' => 5
          )
        end

        it "should give an engulfing creature's save, damage and escape DC" do
          expect(MonsterAbilities.header('DC 22 Reflex, (4d6) acid damage, escape dc=22, Rupture 15%rThe monster Strides...')).to include(
            'dc' => 22, 'save' => 'reflex', 'basic' => false, 'damage' => [ %w{4d6 acid} ], 'escape_dc' => 22, 'rupture' => 15
          )
        end

        it "should give the Strike a trample is made with" do
          expect(MonsterAbilities.header('Medium or smaller, hoof, DC 18 basic Reflex%rThe monster Strides...')).to include(
            'size' => 'medium', 'words' => [ 'hoof' ], 'dc' => 18, 'save' => 'reflex', 'basic' => true
          )
        end
      end
    end

    describe "the abilities creatures share, in a fight", :dbtest => true do
      include FightBench

      # A hero with hit points enough to be hit more than once.
      before(:each) { bench!(:hp => hit_points) }
      after(:each) { clear_bench! }

      def hit_points
        30
      end

      # Snapping Flytrap: Leaf +11 with Improved Grab, Athletics +11, AC 18, 50 hit points.
      # Swallow Whole: Medium, (1d8+1) bludgeoning, 1d6 acid, Rupture 5.
      describe "Swallow Whole" do
        before(:each) do
          add('snapping flytrap')
          next_turn
        end

        def grab!
          as(2, "strike #{@hero.name}", 0.3)
          as(2, "act improved grab=#{@hero.name}", 0.3)
        end

        def swallow!(dice = FightBench::HITS)
          grab!
          as(2, "act swallow whole=#{@hero.name}", dice)
        end

        it "should need the creature to hold whoever it swallows" do
          as(2, "act swallow whole=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.hold_none', :actor => 'Snapping Flytrap #2', :action => 'Swallow Whole') ]
        end

        it "should not swallow someone larger than it can" do
          grab!
          @hero.update(:pf2_size => 'Large')
          as(2, "act swallow whole=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.swallow_too_big', :actor => 'Snapping Flytrap #2', :target => @hero.name, :size => 'medium') ]
        end

        # It is an attack, and the creature's second of the turn after the Strike that grabbed.
        it "should roll Athletics against their Reflex DC, as an attack" do
          swallow!

          expect(heard).to match(/Swallow Whole on #{@hero.name}: Athletics \d+ \(12 \+6\) vs Reflex DC \d+ - success/)
        end

        it "should leave them grabbed where it fails" do
          swallow!(FightBench::LOW)

          expect(Holding.inside(hero)).to be_nil
          expect(held).to have_key('Grabbed').or have_key('Restrained')
        end

        describe "once it has swallowed them" do
          before(:each) { swallow! }

          it "should hold them inside it, slowed, for as long as they are there" do
            expect(Holding.inside(hero)).to include('kind' => 'Swallow Whole', 'rupture' => 5)
            expect(held['Grabbed']['by']).to eq 'Snapping Flytrap #2'
            expect(held['Grabbed']).to_not have_key('expires')
            expect(Pf2e.condition_level(hero, 'Slowed')).to eq 1
          end

          it "should deal its damage as it swallows them" do
            # 1d8+1 and 1d6 with the dice at 12 in 20: 5 + 1 and 4.
            expect(heard).to include("Damage to #{@hero.name}: 6 bludgeoning + 4 acid")
          end

          it "should deal its damage again at the end of each of their turns" do
            before = hero_hp
            turn_to(@hero.name)
            next_turn

            expect(hero_hp).to eq before - 10
          end

          it "should not be able to Strike them" do
            as(2, "strike #{@hero.name}")

            expect(refused).to eq [ t('pf2e.swallowed_cannot_attack', :actor => 'Snapping Flytrap #2', :target => @hero.name) ]
          end

          it "should not be able to swallow another while one as large as it can hold is inside" do
            as(2, "act swallow whole=#{@hero.name}")

            expect(refused).to eq [ t('pf2e.swallow_full', :actor => 'Snapping Flytrap #2') ]
          end

          it "should be off-guard to them" do
            hero_types('e/strike #2=fist', 0.5)

            expect(heard).to include('vs AC 16')
          end

          it "should be cut open by slashing damage of its Rupture value or more from inside, which frees them" do
            hero_types('e/strike #2=claw', 0.75)

            expect(heard).to include(t('pf2e.hold_cut_free', :target => @hero.name, :actor => 'Snapping Flytrap #2').strip)
            expect(held).to_not have_key('Grabbed')
            expect(held).to_not have_key('Slowed')
          end

          it "should not be cut open by a blow that is neither slashing nor piercing" do
            hero_types('e/strike #2=fist', 0.75)

            expect(Holding.inside(hero)).to_not be_nil
          end

          it "should let them out when they Escape" do
            hero_types('e/act escape', 1.0)

            expect(refused).to eq []
            expect(Holding.inside(hero)).to be_nil
            expect(held).to_not have_key('Slowed')
          end

          it "should keep them inside when it drops, and say how they are got out" do
            run(PF2DamagePlayerCmd, "damage #2=#{npc.hp_left}")

            expect(heard).to include('still inside Snapping Flytrap #2')
            expect(Holding.inside(hero)).to_not be_nil
          end

          it "should stop dealing its damage once it has dropped" do
            run(PF2DamagePlayerCmd, "damage #2=#{npc.hp_left}")
            before = hero_hp
            turn_to(@hero.name)
            next_turn

            expect(hero_hp).to eq before
          end

          it "should free them of what being inside did when the GM lets them out" do
            run(PF2ConditionSetCmd, "condition/set #{@hero.name}=grabbed/0")

            expect(held).to_not have_key('Slowed')
          end
        end
      end

      # Living Tar: Engulf, DC 22 Reflex, (4d6) acid damage, escape DC 22, Rupture 15.
      describe "Engulf" do
        def hit_points
          60
        end

        before(:each) do
          add('living tar')
          next_turn
        end

        it "should engulf whoever fails the Reflex save, with its damage, and slow them" do
          as(2, "act engulf=#{@hero.name}", FightBench::LOW)

          expect(heard).to include("#{@hero.name} rolls Reflex")
          expect(Holding.inside(hero)).to include('kind' => 'Engulf', 'escape_dc' => 22, 'rupture' => 15)
          expect(Pf2e.condition_level(hero, 'Slowed')).to eq 1
          expect(heard).to include("Damage to #{@hero.name}")
        end

        it "should leave alone whoever makes the save" do
          as(2, "act engulf=#{@hero.name}", 1.0)

          expect(Holding.inside(hero)).to be_nil
          expect(hero_hp).to eq Pf2eHP.get_max_hp(hero)
        end

        it "should be escaped against the DC it lists" do
          as(2, "act engulf=#{@hero.name}", FightBench::LOW)
          hero_types('e/act escape', 0.5)

          expect(heard).to include('vs DC 22')
        end
      end

      # Moose: Trample, Medium or smaller, hoof, DC 20 basic Reflex. Hoof 1d8+7 bludgeoning.
      describe "Trample" do
        before(:each) do
          add('moose')
          add('goblin warrior')
          next_turn
        end

        it "should deal the listed Strike's damage to each creature named, against a basic Reflex save" do
          as(2, "act trample=#{@hero.name},#3", FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include("#{@hero.name} rolls Reflex", 'Goblin Warrior #3 rolls Reflex', 'vs DC 20')
          expect(heard).to include('bludgeoning')
          expect(hero_hp).to be < 30
        end

        it "should cost three actions" do
          as(2, "act trample=#{@hero.name}")

          expect(TurnState.turn(npc)['actions']).to eq 3
        end
      end

      # Forest Troll: Rend, Claw. Claw +14, 2d8+5 slashing.
      describe "Rend" do
        def hit_points
          200
        end

        before(:each) do
          add('forest troll')
          next_turn
        end

        it "should need two hits in a row with the listed Strike on the same creature this turn" do
          as(2, "strike #{@hero.name}=claw", FightBench::HIGH)
          as(2, "act rend=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.rend_needs_hits', :actor => 'Forest Troll #2', :strike => 'Claw') ]
        end

        it "should not follow a hit with another Strike" do
          as(2, "strike #{@hero.name}=claw", FightBench::HIGH)
          as(2, "strike #{@hero.name}=jaws", FightBench::HIGH)
          as(2, "act rend=#{@hero.name}")

          expect(refused).to eq [ t('pf2e.rend_needs_hits', :actor => 'Forest Troll #2', :strike => 'Claw') ]
        end

        it "should deal the Strike's damage again without a roll to hit" do
          as(2, "strike #{@hero.name}=claw", FightBench::HIGH)
          as(2, "strike #{@hero.name}=claw", FightBench::HIGH)
          before = hero_hp
          as(2, "act rend=#{@hero.name}", 0.5)

          expect(refused).to eq []
          # 2d8+5 with the dice at 10 in 20: 4 + 4 + 5.
          expect(hero_hp).to eq before - 13
          expect(heard).to_not include('vs AC')
        end
      end

      # Orc Veteran: Ferocity. 23 hit points.
      describe "Ferocity" do
        before(:each) do
          add('orc veteran')
          next_turn
        end

        it "should not be used by a creature that has hit points left" do
          as(2, 'act ferocity')

          expect(refused).to eq [ t('pf2e.ferocity_not_down', :actor => 'Orc Veteran #2') ]
        end

        it "should leave a creature reduced to nothing on its feet at 1 hit point, wounded" do
          run(PF2DamagePlayerCmd, "damage #2=#{npc.hp_left}")
          as(2, 'act ferocity')

          expect(refused).to eq []
          expect(npc.hp_left).to eq 1
          expect(Pf2e.condition_level(npc, 'Wounded')).to eq 1
          expect(TurnState.turn(npc)['reaction']).to be true
        end

        it "should be offered to the GM when the creature drops" do
          run(PF2DamagePlayerCmd, "damage #2=#{npc.hp_left}")

          expect(heard).to include('+e/as #2=act ferocity')
        end

        it "should not be used at Wounded 3" do
          Pf2e.set_condition(npc, 'Wounded', 3)
          run(PF2DamagePlayerCmd, "damage #2=#{npc.hp_left}")
          as(2, 'act ferocity')

          expect(refused).to eq [ t('pf2e.ferocity_wounded', :actor => 'Orc Veteran #2') ]
        end
      end

      # River Drake: Draconic Frenzy, one Fangs Strike and two Tail Strikes.
      describe "an ability that is several Strikes" do
        def hit_points
          200
        end

        before(:each) do
          add('river drake')
          next_turn
        end

        it "should make each of them, each further into the multiple attack penalty, for what the ability costs" do
          as(2, "act draconic frenzy=#{@hero.name}", FightBench::HIGH)

          expect(refused).to eq []
          expect(heard.scan(/strikes #{@hero.name} with (Fangs|Tail)/).flatten).to eq %w{Fangs Tail Tail}
          expect(heard).to include('2nd attack', '3rd attack')
          expect(TurnState.turn(npc)['actions']).to eq 2
          expect(TurnState.turn(npc)['attacks']).to eq 3
        end
      end

      # Cavern Troll: Throw Rock, a ranged Strike with its Rock.
      describe "Throw Rock" do
        def hit_points
          200
        end

        before(:each) do
          add('cavern troll')
          next_turn
        end

        it "should be the Strike it is" do
          as(2, "act throw rock=#{@hero.name}", FightBench::HIGH)

          expect(heard).to include("strikes #{@hero.name} with Rock")
          expect(TurnState.turn(npc)['actions']).to eq 1
        end
      end

      # Grodair: Water Jet with Push, and Push 10 feet.
      describe "a Push that lists its distance" do
        def hit_points
          200
        end

        before(:each) do
          add('grodair')
          next_turn
        end

        it "should say how far it pushes" do
          as(2, "strike #{@hero.name}=water jet", FightBench::HIGH)
          as(2, "act push=#{@hero.name}", FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include(t('pf2e.act_push_distance', :feet => 10, :twice => 20).strip)
        end
      end

      # Fire Scamp: Flame Breath, which it cannot use again for 1d4 rounds.
      describe "an ability that takes rounds to come back" do
        before(:each) do
          add('fire scamp')
          next_turn
        end

        it "should tell the GM when it is back" do
          as(2, "act flame breath=#{@hero.name}", 0.5)

          # 1d4 with the dice at half: 2 rounds, so round 4.
          expect(heard).to include(t('pf2e.recharge_set', :actor => 'Fire Scamp #2', :action => 'Flame Breath', :rounds => 2, :round => 4).strip)
        end

        it "should warn the GM who uses it before then, and use it" do
          as(2, "act flame breath=#{@hero.name}", 0.5)
          as(2, "act flame breath=#{@hero.name}", 0.5)

          expect(heard).to include(t('pf2e.recharge_not_back', :actor => 'Fire Scamp #2', :action => 'Flame Breath', :round => 4).strip)
          expect(heard).to include("#{@hero.name} rolls Reflex")
        end

        it "should say nothing once it is back" do
          as(2, "act flame breath=#{@hero.name}", 0.5)
          6.times { next_turn }
          as(2, "act flame breath=#{@hero.name}", 0.5)

          expect(heard).to_not include('not back')
        end
      end

      # Dullahan: Frightful Presence, 30 feet, DC 23 Will; Frightened 1, 2 or 4 by the save, and immune for
      # a minute after it whatever was rolled.
      describe "an aura that calls for a save" do
        before(:each) do
          add('dullahan')
          next_turn
        end

        it "should have whoever enters it roll the save, and leave what the outcome says" do
          as(2, "enter frightful presence=#{@hero.name}", FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include("#{@hero.name} rolls Will", 'vs DC 23')
          expect(Pf2e.condition_level(hero, 'Frightened')).to eq 4
        end

        # A natural 20 from a level 1 hero falls short of DC 23, and is a success for being a 20.
        it "should leave what a success leaves on a success" do
          as(2, "enter frightful presence=#{@hero.name}", 1.0)

          expect(Pf2e.condition_level(hero, 'Frightened')).to eq 1
        end

        it "should not be saved against again while they are immune to it" do
          as(2, "enter frightful presence=#{@hero.name}", 1.0)
          Pf2e.remove_condition(hero, 'Frightened')
          as(2, "enter frightful presence=#{@hero.name}", FightBench::LOW)

          expect(heard).to include(t('pf2e.act_temp_immune', :target => @hero.name, :action => 'Frightful Presence').strip)
          expect(held).to_not have_key('Frightened')
        end
      end

      describe "an ability of the GM's own making that calls for a save" do
        before(:each) do
          add('Wraith=ac 15 hp 30; ability Dread: DC 5 Will%rCritical Success The creature is unaffected by the dread.%r' \
              'Success The creature is Frightened 1.%rFailure The creature is Frightened 2 and Stunned 1.')
          next_turn
        end

        it "should leave nothing on a critical success, and say what its words say of it" do
          as(2, "act dread=#{@hero.name}", 1.0)

          expect(held).to_not have_key('Frightened')
          expect(heard).to include('unaffected by the dread')
        end

        it "should leave every condition a failure names" do
          as(2, "act dread=#{@hero.name}", FightBench::LOW)

          expect(Pf2e.condition_level(hero, 'Frightened')).to eq 2
          expect(Pf2e.condition_level(hero, 'Stunned')).to eq 1
        end
      end

      # Ghoul Stalker: Stench, DC 14 Fortitude, sickened on a failure; immune for a minute on a success.
      describe "an aura whose save only a success makes them immune to" do
        before(:each) do
          add('ghoul stalker')
          next_turn
        end

        it "should sicken on a failure, and be saved against again" do
          as(2, "enter stench=#{@hero.name}", 0.3)
          expect(Pf2e.condition_level(hero, 'Sickened')).to eq 1

          as(2, "enter stench=#{@hero.name}", 0.3)
          expect(heard).to include("#{@hero.name} rolls Fortitude")
        end

        it "should leave them immune after a success" do
          as(2, "enter stench=#{@hero.name}", 1.0)
          as(2, "enter stench=#{@hero.name}", FightBench::LOW)

          expect(heard).to include(t('pf2e.act_temp_immune', :target => @hero.name, :action => 'Stench').strip)
        end
      end

      # Basilisk, level 5: Petrifying Gaze, DC 22 Fortitude, incapacitation.
      describe "an ability that calls for a save and deals nothing" do
        before(:each) do
          add('basilisk')
          next_turn
        end

        it "should roll the save for the GM to read its words against" do
          as(2, "act petrifying gaze=#{@hero.name}", FightBench::LOW)

          expect(heard).to include("#{@hero.name} rolls Fortitude", 'vs DC 22', 'critical failure')
        end

        it "should go one degree better for a creature of higher level than the basilisk" do
          @hero.update(:pf2_level => 6)
          as(2, "act petrifying gaze=#{@hero.name}", FightBench::LOW)

          expect(heard).to include(t('pf2e.act_incapacitation', :target => @hero.name).strip)
          expect(heard).to match(/vs DC 22 - failure/)
        end
      end

      # Rat Swarm: Swarming Bites, 1d6 piercing to each enemy in its space, DC 17 basic Reflex.
      describe "an ability whose damage and save are in its sentence" do
        before(:each) do
          add('rat swarm')
          add('goblin warrior')
          next_turn
        end

        it "should be aimed at as many as are in it, each saving" do
          as(2, "act swarming bites=#{@hero.name},#3", FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include("#{@hero.name} rolls Reflex", 'Goblin Warrior #3 rolls Reflex')
          expect(hero_hp).to be < Pf2eHP.get_max_hp(hero)
        end
      end

      # Orc Veteran: Reactive Strike.
      describe "a reaction already spent" do
        before(:each) do
          add('orc veteran')
          next_turn
        end

        it "should warn the GM, and go ahead" do
          as(2, "act reactive strike=#{@hero.name}")
          as(2, "act reactive strike=#{@hero.name}")

          expect(heard).to include(t('pf2e.act_reaction_spent', :actor => 'Orc Veteran #2').strip)
          expect(heard).to include("strikes #{@hero.name}")
        end
      end
    end
  end
end
