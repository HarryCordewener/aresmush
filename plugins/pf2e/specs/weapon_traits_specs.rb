require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What a weapon's traits make of a Strike with it, beyond its dice: how it is held, which of its edges
    # is used, and what the Strikes before it this turn give it.
    describe WeaponTraits do

      def weapon(*traits, **more)
        { 'name' => 'Blade', 'traits' => traits, 'damage_type' => 'S', 'die' => 'd8', 'striking' => 0 }.merge(more.transform_keys(&:to_s))
      end

      def struck(target, hit = true, with = 'Blade')
        { 'strike' => with, 'target' => target, 'hit' => hit }
      end

      def values(rows)
        rows.map { |row| row['value'] }
      end

      describe "sweep" do
        it "should add 1 to hit once it has been swung at someone else this turn" do
          mods = WeaponTraits.attack_modifiers(weapon('Sweep'), [ struck('Goblin') ], 'Orc', [])

          expect(mods.map { |one| one.slice('type', 'value') }).to eq [ { 'type' => 'circumstance', 'value' => 1 } ]
        end

        it "should add nothing against the same target, nor for another weapon's swing" do
          expect(WeaponTraits.attack_modifiers(weapon('Sweep'), [ struck('Goblin') ], 'Goblin', [])).to eq []
          expect(WeaponTraits.attack_modifiers(weapon('Sweep'), [ struck('Goblin', true, 'Axe') ], 'Orc', [])).to eq []
        end
      end

      describe "backswing" do
        it "should add 1 to hit after a miss with it this turn" do
          expect(values(WeaponTraits.attack_modifiers(weapon('Backswing'), [ struck('Orc', false) ], 'Orc', []))).to eq [ 1 ]
        end

        it "should add nothing after a hit" do
          expect(WeaponTraits.attack_modifiers(weapon('Backswing'), [ struck('Orc', true) ], 'Orc', [])).to eq []
        end
      end

      describe "volley" do
        it "should take 2 from a shot said to be inside its volley range" do
          expect(values(WeaponTraits.attack_modifiers(weapon('Volley (30)'), [], 'Orc', [ 'volley' ]))).to eq [ -2 ]
        end

        it "should take nothing otherwise" do
          expect(WeaponTraits.attack_modifiers(weapon('Volley (30)'), [], 'Orc', [])).to eq []
        end
      end

      describe "forceful" do
        it "should add a die's worth to the second Strike with it in a turn, and twice that to the third" do
          glaive = weapon('Forceful')

          expect(values(WeaponTraits.damage_modifiers(glaive, [], false))).to eq []
          expect(values(WeaponTraits.damage_modifiers(glaive, [ struck('Orc') ], false))).to eq [ 1 ]
          expect(values(WeaponTraits.damage_modifiers(glaive, [ struck('Orc'), struck('Orc', false) ], false))).to eq [ 2 ]
        end

        it "should count the dice a striking rune adds" do
          expect(values(WeaponTraits.damage_modifiers(weapon('Forceful', :striking => 1), [ struck('Orc') ], false))).to eq [ 2 ]
        end
      end

      describe "backstabber" do
        it "should deal 1 precision damage to someone off-guard" do
          rows = WeaponTraits.damage_modifiers(weapon('Backstabber'), [], true)

          expect(rows.map { |row| row.slice('value', 'category') }).to eq [ { 'value' => 1, 'category' => 'precision' } ]
        end

        it "should deal 2 with a +3 weapon, and nothing to someone on guard" do
          expect(values(WeaponTraits.damage_modifiers(weapon('Backstabber', :rune => 3), [], true))).to eq [ 2 ]
          expect(WeaponTraits.damage_modifiers(weapon('Backstabber'), [], false)).to eq []
        end
      end

      describe "versatile" do
        it "should deal the other kind of damage where that is said" do
          expect(WeaponTraits.wielded(weapon('Versatile (P)'), [ 'piercing' ])['damage_type']).to eq 'P'
        end

        it "should stay as it is with nothing said, or its own kind said" do
          expect(WeaponTraits.wielded(weapon('Versatile (P)'), [])['damage_type']).to eq 'S'
          expect(WeaponTraits.wielded(weapon('Versatile (P)'), [ 'slashing' ])['damage_type']).to eq 'S'
        end

        it "should refuse a kind the weapon cannot deal" do
          expect(WeaponTraits.wielded(weapon('Versatile (P)'), [ 'bludgeoning' ]).code).to eq :not_versatile
        end

        it "should change the kind a creature's Strike deals" do
          sword = { 'name' => 'Longsword', 'traits' => [ 'versatile-p' ], 'damage' => [ [ '1d8+3', 'slashing', nil ] ] }

          expect(WeaponTraits.wielded(sword, [ 'piercing' ])['damage']).to eq [ [ '1d8+3', 'piercing', nil ] ]
        end
      end

      describe "lethal and nonlethal" do
        it "should make a lethal weapon's Strike nonlethal at 2 less to hit" do
          sap = WeaponTraits.wielded(weapon, [ 'nonlethal' ])

          expect(sap['traits']).to include('nonlethal')
          expect(values(WeaponTraits.attack_modifiers(sap, [], 'Orc', [ 'nonlethal' ]))).to eq [ -2 ]
        end

        it "should make a nonlethal weapon's Strike lethal at 2 less to hit" do
          fist = WeaponTraits.wielded(weapon('Nonlethal'), [ 'lethal' ])

          expect(fist['traits'].map(&:downcase)).to_not include('nonlethal')
          expect(values(WeaponTraits.attack_modifiers(fist, [], 'Orc', [ 'lethal' ]))).to eq [ -2 ]
        end

        it "should take nothing from a Strike made the way the weapon is" do
          expect(WeaponTraits.attack_modifiers(weapon('Nonlethal'), [], 'Orc', [ 'nonlethal' ])).to eq []
        end
      end

      describe "reload" do
        it "should be the weapon's own, or what a creature's Strike says in its traits" do
          expect(WeaponTraits.reload(weapon(:reload => 2))).to eq 2
          expect(WeaponTraits.reload('traits' => [ 'reload-1' ])).to eq 1
          expect(WeaponTraits.reload(weapon)).to eq 0
        end
      end
    end

    describe "a weapon's traits in a fight", :dbtest => true do
      include FightBench

      # Every die at half its faces: a 10 on the d20, 4 on a d8, 6 on a d12. The hero adds 2 to damage.
      before(:each) do
        bench!
        add('Dummy=ac 5 hp 500; resist piercing 5')
        next_turn
        turn_to(@hero.name)
      end

      after(:each) { clear_bench! }

      def arm(name)
        Pf2egear.create_item(hero, 'weapons', name, 1, Global.read_config('pf2e_weapons', name)).update(:equipped => true)
      end

      def strikes(text)
        hero_types("e/strike #2=#{text}", 0.5)
      end

      describe "a weapon for one hand or two" do
        before(:each) { arm('Bastard Sword') }

        it "should deal its one-handed die" do
          strikes('bastard sword')

          expect(heard).to include('6 slashing')
        end

        it "should deal its two-handed die where that is said" do
          strikes('bastard sword/two-handed')

          expect(heard).to include('8 slashing')
        end
      end

      it "should refuse two hands on a weapon that gains nothing by them" do
        arm('Glaive')
        strikes('glaive/two-handed')

        expect(refused).to eq [ t('pf2e.strike_not_two_hand', :weapon => 'Glaive') ]
      end

      describe "a versatile weapon" do
        before(:each) { arm('Longsword') }

        it "should deal the kind of damage said, which is what is resisted" do
          strikes('longsword/piercing')

          expect(heard).to include('1 piercing (resistance -5)')
        end

        it "should refuse a kind it cannot deal" do
          strikes('longsword/bludgeoning')

          expect(refused).to eq [ t('pf2e.strike_not_versatile', :weapon => 'Longsword', :kinds => 'slashing or piercing') ]
        end
      end

      describe "a weapon that is loaded" do
        before(:each) { arm('Heavy Crossbow') }

        it "should be shot once" do
          strikes('heavy crossbow')

          expect(refused).to eq []
        end

        it "should not be shot again until it is reloaded" do
          strikes('heavy crossbow')
          strikes('heavy crossbow')

          expect(refused).to eq [ t('pf2e.strike_unloaded', :weapon => 'Heavy Crossbow', :actions => 'two actions') ]
        end

        it "should be reloaded for as many actions as it takes, and shot again" do
          strikes('heavy crossbow')
          hero_types('e/reload')

          expect(heard).to include(t('pf2e.reloaded', :actor => @hero.name, :weapon => 'Heavy Crossbow', :actions => 'two actions').gsub(/%x\w/, ''))
          expect(TurnState.turn(hero)['actions']).to eq 3

          strikes('heavy crossbow')

          expect(refused).to eq []
        end

        it "should be loaded by an action that has its taker Interact to reload" do
          @hero.update(:pf2_feats => { 'charclass' => [ 'Covered Reload' ] })
          strikes('heavy crossbow')
          hero_types('e/act covered reload')

          expect(refused).to eq []
          expect(heard).to include(t('pf2e.act_reloaded', :actor => @hero.name, :weapon => 'Heavy Crossbow').strip)

          strikes('heavy crossbow')

          expect(refused).to eq []
        end

        it "should be risked on a flat check by someone grabbed, as anything that takes the hands is" do
          strikes('heavy crossbow')
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=grabbed")
          hero_types('e/reload', 0.2)

          expect(heard).to include(t('pf2e.act_risk_lost', :actor => @hero.name, :condition => 'Grabbed', :action => 'Interact',
                                                         :die => 4, :dc => 5).strip)
          expect(Loading.held(hero)).to eq [ 'Heavy Crossbow' ]
        end

        it "should have nothing to reload while it is loaded" do
          hero_types('e/reload')

          expect(refused).to eq [ t('pf2e.reload_nothing') ]
        end
      end

      it "should make a fist's blow lethal for 2 less to hit" do
        strikes('fist')
        plain = heard[/\(10 ([+-]\d+)\)/, 1].to_i
        TurnState.started(hero, encounter.round)
        strikes('fist/lethal')

        expect(heard[/\(10 ([+-]\d+)\)/, 1].to_i).to eq plain - 2
      end
    end
  end
end
