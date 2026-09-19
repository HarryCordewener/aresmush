require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What an attack does when it hits.
    #
    # The reader this replaced had three defects, all making characters hit harder than the rules
    # allow: a striking rune added both a die and a flat bonus of the same size, Strength was added to
    # every attack including a crossbow's, and the Thief racket read Dexterity without the finesse
    # weapon the racket requires.
    describe Damage do

      def char(level: 5, str: 18, dex: 14, racket: nil)
        scores = { 'Strength' => str, 'Dexterity' => dex }
        double(:pf2_level => level,
               :pf2_base_info => { 'specialize' => racket },
               :pf2_conditions => {}, :pf2_traits => [], :pf2_feats => {},
               :abilities => nil).tap do |it|
          allow(Pf2e).to receive(:ability_mod) { |_c, ability| (scores.fetch(ability, 10) - 10) / 2 }
        end
      end

      def sword(extra = {})
        { 'id' => 'w1', 'name' => 'Longsword', 'group' => 'sword', 'base' => 'longsword',
          'traits' => [], 'ranged' => false, 'unarmed' => false, 'bomb' => false,
          'die' => 'd8', 'damage_type' => 'S', 'striking' => 0 }.merge(extra)
      end

      def bow(extra = {})
        sword('name' => 'Longbow', 'group' => 'bow', 'base' => 'longbow', 'ranged' => true,
              'die' => 'd8', 'damage_type' => 'P').merge(extra)
      end

      before(:each) do
        allow(Effects).to receive(:sources).and_return([])
        allow(Effects).to receive(:options).and_return([])
        allow(Effects).to receive(:context).and_return('actor' => { 'level' => 5 })
      end

      describe "the weapon's own dice" do
        it "should be one die plus the attribute" do
          expect(Damage.formula(char, sword)).to eq '1d8+4 S'
        end

        # A striking rune raises the number of dice. It used to add a flat bonus of the same size as
        # well, so a greater striking longsword read 3d8+7 where the rules say 3d8+4.
        it "should add a die per striking rune and nothing flat" do
          expect(Damage.formula(char, sword('striking' => 2))).to eq '3d8+4 S'
        end
      end

      # `actor/helpers.ts:420`. Strength is added for a melee attack, a propulsive one, or a thrown one
      # that is neither splash nor a bomb.
      describe "which attribute adds to it" do
        it "should add Strength to a melee attack" do
          expect(Damage.formula(char, sword)).to include '+4'
        end

        it "should add nothing to an ordinary ranged attack" do
          expect(Damage.formula(char, bow)).to eq '1d8 P'
        end

        it "should add Strength to a propulsive bow, which is what propulsive means" do
          expect(Damage.formula(char, bow('traits' => [ 'propulsive' ]))).to eq '1d8+4 P'
        end

        it "should add Strength to a thrown weapon" do
          expect(Damage.formula(char, bow('traits' => [ 'thrown' ]))).to eq '1d8+4 P'
        end

        it "should add nothing to a thrown splash weapon" do
          expect(Damage.formula(char, bow('traits' => [ 'thrown', 'splash' ]))).to eq '1d8 P'
        end

        it "should add nothing to a bomb" do
          expect(Damage.formula(char, bow('traits' => [ 'thrown' ], 'bomb' => true))).to eq '1d8 P'
        end
      end

      # The Thief racket adds Dexterity instead of Strength, and only with a finesse weapon.
      describe "a Thief rogue" do
        def thief
          char(:racket => 'Thief', :str => 10, :dex => 18)
        end

        it "should read Dexterity with a finesse weapon" do
          expect(Damage.formula(thief, sword('traits' => [ 'finesse' ]))).to eq '1d8+4 S'
        end

        it "should read Strength with a weapon that is not finesse" do
          expect(Damage.formula(thief, sword)).to eq '1d8 S'
        end
      end

      describe "dice an effect adds" do
        def with_dice(rows)
          allow(Effects).to receive(:damage_dice).and_return(rows)
          allow(Effects).to receive(:modifiers).and_return([])
        end

        def die_row(fields = {})
          { 'source' => 'Something', 'dice' => 1, 'die' => 'd6', 'damage_type' => nil,
            'category' => nil, 'critical' => nil, 'met' => true }.merge(fields)
        end

        it "should join dice of the weapon's own kind into one roll" do
          with_dice([ die_row('die' => 'd8', 'dice' => 2) ])

          expect(Damage.formula(char, sword)).to eq '3d8+4 S'
        end

        it "should keep dice of another kind as their own roll" do
          with_dice([ die_row('damage_type' => 'fire') ])

          expect(Damage.formula(char, sword)).to eq '1d8+4 S + 1d6 fire'
        end

        # Persistent, splash and precision damage are rolled and applied apart from the rest.
        it "should keep a category apart even when the kind matches" do
          with_dice([ die_row('die' => 'd8', 'category' => 'persistent') ])

          expect(Damage.formula(char, sword)).to eq '1d8+4 S + 1d8 persistent S'
        end

        it "should leave out dice that only apply on a critical hit" do
          with_dice([ die_row('critical' => true) ])

          expect(Damage.formula(char, sword)).to eq '1d8+4 S'
        end

        it "should not count dice whose circumstances are unmet" do
          with_dice([ die_row('met' => false) ])

          expect(Damage.formula(char, sword)).to eq '1d8+4 S'
        end

        it "should report the ones it did not count" do
          with_dice([ die_row('met' => false) ])

          expect(Damage.of(char, sword)['conditional'].size).to eq 1
        end
      end

      describe "a flat bonus an effect adds" do
        it "should add to the weapon's own roll" do
          allow(Effects).to receive(:damage_dice).and_return([])
          allow(Effects).to receive(:modifiers)
            .and_return([ { 'source' => 'Something', 'value' => 2, 'type' => 'untyped', 'met' => true } ])

          expect(Damage.formula(char, sword)).to eq '1d8+6 S'
        end

        it "should read a negative one, which is what Enfeebled is" do
          allow(Effects).to receive(:damage_dice).and_return([])
          allow(Effects).to receive(:modifiers)
            .and_return([ { 'source' => 'Enfeebled', 'value' => -2, 'type' => 'status', 'met' => true } ])

          expect(Damage.formula(char, sword)).to eq '1d8+2 S'
        end
      end

      # `values.ts:112`. A row that says nothing about criticals doubles on one; a row that says false
      # applies to both and never doubles; a row that says true applies only to a critical.
      describe "a critical hit" do
        def with_dice(rows)
          allow(Effects).to receive(:damage_dice).and_return(rows)
          allow(Effects).to receive(:modifiers).and_return([])
        end

        def die_row(fields = {})
          { 'source' => 'Something', 'dice' => 1, 'die' => 'd6', 'damage_type' => nil,
            'category' => nil, 'critical' => nil, 'met' => true }.merge(fields)
        end

        it "should double the weapon's own roll" do
          with_dice([])

          expect(Damage.critical(char, sword)).to eq '(1d8+4)x2 S'
        end

        it "should double dice that say nothing about criticals" do
          with_dice([ die_row('die' => 'd8') ])

          expect(Damage.critical(char, sword)).to eq '(2d8+4)x2 S'
        end

        # Deadly and similar dice are added on a critical and not doubled.
        it "should add a critical-only row undoubled" do
          with_dice([ die_row('critical' => true, 'die' => 'd10') ])

          expect(Damage.critical(char, sword)).to eq '(1d8+4)x2+1d10 S'
        end

        it "should leave a critical-only row out of an ordinary hit" do
          with_dice([ die_row('critical' => true, 'die' => 'd10') ])

          expect(Damage.formula(char, sword)).to eq '1d8+4 S'
        end

        # A row that says false is in both, and doubles in neither.
        it "should add a row that never doubles to both, undoubled" do
          with_dice([ die_row('critical' => false, 'die' => 'd6') ])

          expect(Damage.formula(char, sword)).to eq '1d8+4+1d6 S'
          expect(Damage.critical(char, sword)).to eq '(1d8+4)x2+1d6 S'
        end

        it "should double each kind of damage on its own" do
          with_dice([ die_row('damage_type' => 'fire') ])

          expect(Damage.critical(char, sword)).to eq '(1d8+4)x2 S + (1d6)x2 fire'
        end
      end

      # `helpers.ts:118`. A step in die size happens before an outright override of it, and a weapon's
      # die can be raised only once however many effects say to raise it.
      describe "an override" do
        def with_override(*overrides)
          rows = overrides.map { |one|
            { 'source' => 'Something', 'dice' => 0, 'die' => nil, 'damage_type' => nil,
              'category' => nil, 'critical' => nil, 'override' => one, 'met' => true }
          }

          allow(Effects).to receive(:damage_dice).and_return(rows)
          allow(Effects).to receive(:modifiers).and_return([])
        end

        it "should raise the die a step" do
          with_override('upgrade' => true)

          expect(Damage.formula(char, sword)).to eq '1d10+4 S'
        end

        it "should raise it only once however many say to" do
          with_override({ 'upgrade' => true }, { 'upgrade' => true })

          expect(Damage.formula(char, sword)).to eq '1d10+4 S'
        end

        it "should net a raise against a lowering" do
          with_override({ 'upgrade' => true }, { 'downgrade' => true })

          expect(Damage.formula(char, sword)).to eq '1d8+4 S'
        end

        it "should stop at the largest die" do
          with_override('upgrade' => true)

          expect(Damage.formula(char, sword('die' => 'd12'))).to eq '1d12+4 S'
        end

        it "should set the die outright" do
          with_override('dieSize' => 'd4')

          expect(Damage.formula(char, sword)).to eq '1d4+4 S'
        end

        it "should change the kind of damage" do
          with_override('damageType' => 'fire')

          expect(Damage.formula(char, sword)).to eq '1d8+4 fire'
        end

        it "should set how many dice" do
          with_override('diceNumber' => 3)

          expect(Damage.formula(char, sword)).to eq '3d8+4 S'
        end

        # An override adjusts the weapon's dice rather than adding any, so it contributes none itself.
        it "should add no dice of its own" do
          with_override('damageType' => 'fire')

          expect(Damage.of(char, sword)['instances'].size).to eq 1
        end
      end

      describe "what it reports" do
        it "should name what went into each roll" do
          allow(Effects).to receive(:damage_dice).and_return([])
          allow(Effects).to receive(:modifiers).and_return([])

          instance = Damage.of(char, sword)['instances'].first

          expect(instance['sources']).to include 'Longsword', 'Strength'
        end

        it "should give an attack with no die of its own a flat roll" do
          allow(Effects).to receive(:damage_dice).and_return([])
          allow(Effects).to receive(:modifiers).and_return([])

          expect(Damage.formula(char, sword('die' => nil))).to eq '4 S'
        end
      end
    end
  end
end
