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

      # What a player says after an action's name that is about its effect - the rank it is at, a
      # counter, an answer to what it asks - reaches the effect, as `effect/add` takes them.
      describe "what is said about an action's effect" do
        it "should pass the rank, a counter and an answer to the effect" do
          said = Acting.said([ 'rank 6', 'value 3', 'fire' ], false)

          expect(Acting.effect_options(said)).to eq [ 'rank 6', 'value 3', 'fire' ]
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

          expect(Acting.spell_damage(mechanics, 5).first.first).to eq '10d6'
        end

        # Gouging Claw's bleed at 10th rank is 2 and one more for each of nine ranks.
        it "should add up what it adds, dice with dice and numbers with numbers" do
          mechanics = { 'rank' => 0, 'damage' => [ { 'formula' => '2d6', 'type' => 'slashing' },
                                                   { 'formula' => '2', 'type' => 'bleed', 'category' => 'persistent' } ],
                        'heightening' => { 'interval' => 1, 'damage' => [ '1d6', '1' ] } }

          expect(Acting.spell_damage(mechanics, 10).map(&:first)).to eq [ '11d6', '11' ]
        end

        it "should replace its damage at a fixed rank" do
          mechanics = { 'rank' => 1, 'damage' => [ { 'formula' => '2d6', 'type' => 'fire' } ],
                        'heightening' => { 'fixed' => { '3' => [ '4d6' ], '5' => [ '6d6' ] } } }

          expect(Acting.spell_damage(mechanics, 4).first.first).to eq '4d6'
        end
      end

      describe "casting one way or another" do
        def heal
          Acting.spell_mechanics('Heal').last
        end

        it "should read how many actions it is cast with" do
          expect(Acting.said([ 'actions 2' ], false)['actions']).to eq 2
        end

        it "should take Heal's two-action form, which heals more at range" do
          chosen = Acting.variant(heal, Acting.said([ 'actions 2' ], false))

          expect(chosen['damage'].first['formula']).to eq '1d8+8'
          expect(chosen['range']).to eq '30 feet'
        end

        it "should keep a spell as it is when no variant is asked for" do
          expect(Acting.variant(heal, Acting.said([], false))['damage'].first['formula']).to eq '1d8'
        end

        # Gouging Claw slashes or pierces, as the caster chooses; cast without choosing, it would deal
        # damage of no kind at all, which nothing resists.
        it "should ask which way when the way decides the kind of damage" do
          expect(Acting.way_needed('Gouging Claw', []).code).to eq :way_needed
          expect(Acting.way_needed('Gouging Claw', [ 'slashing' ]).ok?).to be true
        end

        it "should not ask of a spell whose ways are a choice the caster may leave" do
          expect(Acting.way_needed('Heal', []).ok?).to be true
          expect(Acting.way_needed('Fireball', []).ok?).to be true
        end

        it "should find a variant by a word of its name" do
          darts = Acting.spell_mechanics('Needle Darts').last

          expect(Acting.variant(darts, Acting.said([ 'silver' ], false))['name']).to include 'Silver'
        end
      end

      # What the importer reads from a spell's outcomes is only what the engine can do.
      describe "the outcomes the spell data holds" do
        before(:all) do
          @mechanics = YAML.load_file('game/config/pf2e_spell_mechanics.yml')['pf2e_spell_mechanics']
          @conditions = YAML.load_file('game/config/pf2e_conditions.yml')['pf2e_conditions'].keys
        end

        def left
          @mechanics.values.flat_map { |one| (one['outcomes'] || {}).values.flatten }
        end

        it "should name only conditions the game has" do
          expect(left.map { |one| one['condition'] }.compact.uniq - @conditions).to eq []
        end

        it "should time each with a duration the engine counts" do
          known = %w{turn-end next-turn-start next-turn-end its-turn-end its-next-turn-start its-next-turn-end}

          expect(left.map { |one| one['until'] }.compact.uniq.reject { |one| known.include?(one) || one.match?(/\Arounds:\d+\z/) }).to eq []
        end
      end

      # A save that is not basic says in its own text what each outcome does to the damage.
      describe "how much of a spell's damage an outcome deals" do
        it "should scale a basic save the basic way" do
          expect(Acting.damage_factor({ 'basic' => true }, Degree::SUCCESS)).to eq 0.5
        end

        it "should scale another save by the spell's own words" do
          combustion = Acting.spell_mechanics('Combustion').last

          expect(Acting.damage_factor(combustion, Degree::SUCCESS)).to eq 0.5
          expect(Acting.damage_factor(combustion, Degree::CRITICAL_FAILURE)).to eq 2
        end

        it "should leave an outcome its text says nothing about to the GM" do
          expect(Acting.damage_factor({ 'basic' => false, 'damage_scale' => { 'criticalSuccess' => 0 } },
                                      Degree::FAILURE)).to be_nil
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
