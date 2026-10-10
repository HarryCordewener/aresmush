require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A creature of the GM's own making, described on one line: its figures, then whatever else it has,
    # each part after a semicolon and named by its first word.
    describe Described do

      def read(text)
        Described.read('Bandit', text)
      end

      def block(text)
        read(text).state
      end

      it "should not take a name for a description" do
        expect(read('Grik the Bold')).to be_nil
      end

      describe "its figures" do
        it "should be read in any order, signed or not" do
          expect(block('AC 15 Fort +6 Ref 8 Will 4 Perception 5 HP 20 Level 2')).to include(
            'name' => 'Bandit', 'level' => 2, 'ac' => 15, 'hp' => 20, 'perception' => 5,
            'saves' => { 'fortitude' => 6, 'reflex' => 8, 'will' => 4 }
          )
        end

        it "should hold its attribute modifiers, for a skill it does not list" do
          expect(block('ac 15 hp 20 str 4 dex -1')['abilities']).to eq('str' => 4, 'dex' => -1)
        end

        it "should hold its Speeds" do
          expect(block('ac 15 hp 20 speed 25 fly 40')['speeds']).to eq('land' => 25, 'fly' => 40)
        end

        it "should need its hit points" do
          expect(read('ac 15').code).to eq :described_needs
        end
      end

      it "should hold its skills" do
        expect(block('ac 15 hp 20; skills Athletics +8, stealth 9')['skills']).to eq('Athletics' => 8, 'Stealth' => 9)
      end

      it "should hold what it is immune to" do
        expect(block('ac 15 hp 20; immune poison, death effects')['immunities']).to eq %w{poison death-effects}
      end

      it "should hold what it is weak to and what it resists" do
        found = block('ac 15 hp 20; weak fire 5, cold iron 10; resist physical 3, cold 5')

        expect(found['weaknesses']).to eq('fire' => 5, 'cold-iron' => 10)
        expect(found['resistances']).to eq('physical' => 3, 'cold' => 5)
      end

      it "should hold what a resistance lets through" do
        found = block('ac 15 hp 20; resist physical 10 except silver or adamantine, fire 5')

        expect(found['resistances']).to eq('physical' => { 'value' => 10, 'except' => %w{silver adamantine} }, 'fire' => 5)
        expect(Npcs.listed_words(found['resistances'])).to eq [ 'physical 10 (except silver, adamantine)', 'fire 5' ]
      end

      it "should hold its traits, size and rarity" do
        expect(block('ac 15 hp 20; traits Humanoid, human; size large; rarity uncommon')).to include(
          'traits' => %w{humanoid human}, 'size' => 'large', 'rarity' => 'uncommon'
        )
      end

      it "should hold its senses" do
        expect(block('ac 15 hp 20; senses darkvision, scent 30 feet')['senses']).to eq [ 'darkvision', 'scent 30 feet' ]
      end

      describe "a shield" do
        it "should be its Hardness and its Hit Points, raised for +2 to AC" do
          expect(block('ac 15 hp 20; shield 5 20')['shield']).to eq('name' => 'Shield', 'hardness' => 5, 'hp' => 20, 'ac' => 2)
        end

        it "should take a name and a bonus of its own" do
          expect(block('ac 15 hp 20; shield tower shield 5 20 +3')['shield']).to eq(
            'name' => 'Tower Shield', 'hardness' => 5, 'hp' => 20, 'ac' => 3
          )
        end

        it "should give the creature Shield Block" do
          expect(block('ac 15 hp 20; shield 5 20')['actions'].map { |one| one.slice('name', 'type') }).to eq [
            { 'name' => 'Shield Block', 'type' => 'reaction' }
          ]
        end

        it "should be refused without both figures, with how to write one" do
          expect(read('ac 15 hp 20; shield 5').code).to eq :described_shield
        end
      end

      describe "a Strike" do
        it "should be its name, its bonus and what it deals" do
          expect(block('ac 15 hp 20; strike shortsword +9 1d6+4 piercing')['strikes']).to eq [
            { 'name' => 'Shortsword', 'bonus' => 9, 'damage' => [ [ '1d6+4', 'piercing', nil ] ], 'traits' => [] }
          ]
        end

        it "should have its traits" do
          found = block('ac 15 hp 20; strike short sword +9 1d6+4 piercing (agile, finesse, deadly d8)')['strikes'].first

          expect(found['name']).to eq 'Short Sword'
          expect(found['traits']).to eq %w{agile finesse deadly-d8}
        end

        it "should deal each kind of damage it names" do
          found = block('ac 15 hp 20; strike jaws +12 2d8+6 piercing plus 1d6 fire')['strikes'].first

          expect(found['damage']).to eq [ [ '2d8+6', 'piercing', nil ], [ '1d6', 'fire', nil ] ]
        end

        it "should deal persistent damage as persistent" do
          found = block('ac 15 hp 20; strike claw +12 1d8 slashing plus 1d4 persistent bleed')['strikes'].first

          expect(found['damage'].last).to eq [ '1d4', 'bleed', 'persistent' ]
        end

        it "should be ranged with a range" do
          found = block('ac 15 hp 20; ranged shortbow +9 1d6 piercing (range 60, deadly d10)')['strikes'].first

          expect(Npcs.range_of(found)).to eq 60
          expect(found['traits']).to eq %w{range-increment-60 deadly-d10}
        end

        it "should be one of as many as it has" do
          found = block('ac 15 hp 20; strike jaws +12 2d8 piercing; strike claw +12 1d8 slashing (agile)')['strikes']

          expect(found.map { |one| one['name'] }).to eq %w{Jaws Claw}
        end

        it "should be refused without what it deals" do
          found = read('ac 15 hp 20; strike jaws +12')

          expect(found.code).to eq :described_strike
          expect(found.args['words']).to eq 'jaws +12'
        end
      end

      describe "an ability" do
        it "should be its name and its words, for one action" do
          found = block('ac 15 hp 20; ability Tail Sweep: Each creature within reach takes 2d6 bludgeoning damage (DC 20 basic Reflex save).')

          expect(found['actions']).to eq [ { 'name' => 'Tail Sweep', 'type' => 'action', 'cost' => 1, 'traits' => [],
                                             'text' => 'Each creature within reach takes 2d6 bludgeoning damage (DC 20 basic Reflex save).' } ]
        end

        it "should cost what it says" do
          found = block('ac 15 hp 20; ability Fire Breath [2]: Fire.; ability Riposte [reaction]: Strikes back.; ' \
                        'ability Stench [passive]: Smells.; ability Snarl [free]: Snarls.')['actions']

          expect(found.map { |one| [ one['name'], one['type'], one['cost'] ] }).to eq [
            [ 'Fire Breath', 'action', 2 ], [ 'Riposte', 'reaction', nil ], [ 'Stench', 'passive', nil ], [ 'Snarl', 'free', nil ]
          ]
        end

        it "should be what its damage and save are read from" do
          found = block('ac 15 hp 20; ability Tail Sweep: Each creature within reach takes 2d6 bludgeoning damage (DC 20 basic Reflex save).')

          expect(CreatureAbilities.damage_save(found['actions'].first['text'])).to eq(
            'formula' => '2d6', 'type' => 'bludgeoning', 'dc' => 20, 'save' => 'reflex'
          )
        end

        it "should be refused without its words" do
          expect(read('ac 15 hp 20; ability Tail Sweep').code).to eq :described_ability
        end
      end

      it "should refuse a part it has no name for, and say which" do
        found = read('ac 15 hp 20; spells fireball')

        expect(found.code).to eq :described_part
        expect(found.args['words']).to eq 'spells fireball'
      end

      it "should be a stat block an adjustment applies to" do
        elite = Adjustments.apply(block('ac 15 hp 20 level 2; strike jaws +9 1d8+4 piercing'), 'elite')

        expect(elite['ac']).to eq 17
        expect(elite['strikes'].first['damage']).to eq [ [ '1d8+6', 'piercing', nil ] ]
      end
    end
  end
end
