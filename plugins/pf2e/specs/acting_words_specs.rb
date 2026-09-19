require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the encounter commands read out of what a player typed, and the arithmetic that needs no
    # database: damage doubled and scaled, a heightened spell's dice, a creature described by its numbers.
    describe "reading what was said in an encounter" do

      describe "the shape of an argument" do
        it "should split the thing done, the target and the circumstances" do
          expect(ActsInEncounter.split('trip=#3/flanking/range 2')).to eq [ 'trip', '#3', [ 'flanking', 'range 2' ] ]
        end

        it "should take an action with no target" do
          expect(ActsInEncounter.split('raise a shield')).to eq [ 'raise a shield', '', [] ]
        end
      end

      describe "circumstances" do
        it "should read flanking, a range increment and a DC" do
          said = Acting.said([ 'flanking', 'range 3', '18' ], false)

          expect(said['flanking']).to be true
          expect(said['range']).to eq 3
          expect(said['dc']).to eq 18
        end

        it "should refuse cover from someone who may not say it" do
          said = Acting.said([ 'greater cover' ], false)

          expect(said['cover']).to be_nil
          expect(said['refused']).to eq [ 'greater cover' ]
        end

        it "should take cover from someone who may" do
          expect(Acting.said([ 'cover' ], true)['cover']).to eq 'standard'
        end

        it "should offer anything else as Foundry's options, and scoped to the action" do
          scene = Acting::Scene.new(nil, nil, nil, nil, false)
          options = Acting.options_for(scene, Acting.said([ 'unintelligible' ], false), 'demoralize')

          expect(options).to include('unintelligible', 'action:demoralize:unintelligible')
        end
      end

      describe "damage" do
        it "should double a formula" do
          expect(DamageRoll.doubled('1d6+1')).to eq '2d6+2'
        end

        it "should halve for a basic save's success and double for its critical failure" do
          rows = [ { 'type' => 'fire', 'amount' => 21 } ]

          expect(DamageRoll.scaled(rows, Degree::SUCCESS).first['amount']).to eq 10
          expect(DamageRoll.scaled(rows, Degree::CRITICAL_FAILURE).first['amount']).to eq 42
          expect(DamageRoll.scaled(rows, Degree::CRITICAL_SUCCESS).first['amount']).to eq 0
        end

        it "should roll a deadly weapon's die on a critical" do
          allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides ] * amount }

          rows = DamageRoll.of_formulas([ [ '1d6', 'piercing', nil ] ], true, 'traits' => [ 'deadly-d10' ])

          expect(rows.first['amount']).to eq 12 + 10
        end
      end

      describe "a heightened spell" do
        it "should add its interval damage for each rank above its own" do
          mechanics = { 'rank' => 3, 'damage' => [ { 'formula' => '6d6', 'type' => 'fire' } ],
                        'heightening' => { 'interval' => 1, 'damage' => [ '2d6' ] } }

          expect(Acting.spell_damage(mechanics, 5).first.first).to eq '6d6+2d6+2d6'
        end

        it "should replace its damage at a fixed rank" do
          mechanics = { 'rank' => 1, 'damage' => [ { 'formula' => '2d6', 'type' => 'fire' } ],
                        'heightening' => { 'fixed' => { '3' => [ '4d6' ], '5' => [ '6d6' ] } } }

          expect(Acting.spell_damage(mechanics, 4).first.first).to eq '4d6'
        end
      end

      describe "a creature described by its numbers" do
        it "should read the numbers off a stat block" do
          described = Combatants.described('Bandit', 'AC 15 Fort +6 Ref 8 Will 4 Perception 5 HP 20')

          expect(described['ac']).to eq 15
          expect(described['saves']).to eq('fortitude' => 6, 'reflex' => 8, 'will' => 4)
          expect(described['hp']).to eq 20
        end

        it "should be nothing without an AC" do
          expect(Combatants.described('Grik', 'Grik the Bold')).to be_nil
        end
      end

      describe "how long a condition lasts" do
        it "should end at the start of the actor's next turn" do
          expect(Turns.expiry('next-turn-start', 'Aria', 2)).to eq('event' => 'turn-start', 'of' => 'Aria', 'round' => 3)
        end

        it "should count a number of rounds" do
          expect(Turns.expiry('rounds:10', 'Aria', 2)).to eq('event' => 'turn-start', 'of' => 'Aria', 'round' => 12)
        end
      end
    end
  end
end
