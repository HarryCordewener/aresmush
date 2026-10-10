require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Elite and Weak, as Monster Core has them and Foundry applies them: every figure and DC two higher or
    # lower, hit points by the level the creature started at, what it deals two more or less - four where
    # it can only do it now and then - and its level one or two away.
    describe Adjustments do

      def block(level = 3)
        { 'level' => level, 'ac' => 18, 'hp' => 45, 'perception' => 9,
          'saves' => { 'fortitude' => 11, 'reflex' => 8, 'will' => 6 },
          'skills' => { 'Athletics' => 10, 'Stealth' => 7 },
          'strikes' => [ { 'name' => 'Jaws', 'bonus' => 12, 'damage' => [ [ '1d8+6', 'piercing', nil ], [ '1d6', 'fire', nil ] ] },
                         { 'name' => 'Claw', 'bonus' => 12, 'damage' => [ [ '1d6', 'slashing', nil ] ] } ],
          'spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'dc' => 20, 'attack' => 12, 'spells' => { '1' => [ 'Force Barrage' ] } } ],
          'actions' => [
            { 'name' => 'Fire Breath', 'type' => 'action', 'cost' => 2,
              'text' => "The creature breathes fire that deals 4d6 fire damage in a 15-foot cone (DC 20 basic Reflex save).%rIt can't use Fire Breath again for 1d4 rounds." },
            { 'name' => 'Tail Sweep', 'type' => 'action', 'cost' => 1,
              'text' => 'Each creature within reach takes 2d6+3 bludgeoning damage with a DC 20 basic Reflex save.' },
            { 'name' => 'Constrict', 'type' => 'action', 'cost' => 1, 'text' => '(1d8+6) bludgeoning, DC 20 basic Fortitude' },
            { 'name' => 'Burning', 'type' => 'passive',
              'text' => 'Its Strikes deal an extra 1d6 fire damage and 1d4 persistent fire damage, ended by a DC 15 flat check.' }
          ] }
      end

      def text_of(adjusted, ability)
        adjusted['actions'].find { |one| one['name'] == ability }['text']
      end

      it "should know the adjustments there are" do
        expect(Adjustments.names).to eq %w{elite weak}
      end

      it "should leave a creature with no adjustment as it is" do
        expect(Adjustments.apply(block, nil)).to eq block
      end

      it "should leave the stat block it was given alone" do
        given = block

        Adjustments.apply(given, 'elite')

        expect(given).to eq block
      end

      describe "elite" do
        def elite(level = 3)
          Adjustments.apply(block(level), 'elite')
        end

        it "should raise its defences, Perception and skills by two" do
          expect(elite.slice('ac', 'perception', 'saves', 'skills')).to eq(
            'ac' => 20, 'perception' => 11, 'saves' => { 'fortitude' => 13, 'reflex' => 10, 'will' => 8 },
            'skills' => { 'Athletics' => 12, 'Stealth' => 9 }
          )
        end

        it "should raise its Strikes by two" do
          expect(elite['strikes'].map { |one| one['bonus'] }).to eq [ 14, 14 ]
        end

        it "should add two to the first damage of each Strike" do
          expect(elite['strikes'].map { |one| one['damage'].map(&:first) }).to eq [ [ '1d8+8', '1d6' ], [ '1d6+2' ] ]
        end

        it "should raise its spells' DC and attack by two" do
          expect(elite['spellcasting'].first.slice('dc', 'attack')).to eq('dc' => 22, 'attack' => 14)
        end

        it "should raise the DCs its abilities name by two, and add two to what they deal" do
          expect(text_of(elite, 'Tail Sweep')).to eq 'Each creature within reach takes 2d6+5 bludgeoning damage with a DC 22 basic Reflex save.'
          expect(text_of(elite, 'Constrict')).to eq '(1d8+8) bludgeoning, DC 22 basic Fortitude'
        end

        it "should add four to what an ability deals that it cannot use every round" do
          expect(text_of(elite, 'Fire Breath')).to include('deals 4d6+4 fire damage', 'DC 22 basic Reflex', 'again for 1d4 rounds')
        end

        it "should leave alone a flat check, extra damage and persistent damage" do
          expect(text_of(elite, 'Burning')).to eq block['actions'].last['text']
        end

        { 1 => 10, -1 => 10, 2 => 15, 4 => 15, 5 => 20, 19 => 20, 20 => 30 }.each do |level, more|
          it "should add #{more} hit points to a creature that started at level #{level}" do
            expect(elite(level)['hp']).to eq 45 + more
          end
        end

        { -1 => 1, 0 => 2, 1 => 2, 7 => 8 }.each do |level, becomes|
          it "should make a level #{level} creature level #{becomes}" do
            expect(elite(level)['level']).to eq becomes
          end
        end

        it "should say what it is" do
          expect(elite['adjustment']).to eq 'elite'
        end
      end

      describe "weak" do
        def weak(level = 3)
          Adjustments.apply(block(level), 'weak')
        end

        it "should lower its defences, Perception and skills by two" do
          expect(weak.slice('ac', 'perception', 'saves', 'skills')).to eq(
            'ac' => 16, 'perception' => 7, 'saves' => { 'fortitude' => 9, 'reflex' => 6, 'will' => 4 },
            'skills' => { 'Athletics' => 8, 'Stealth' => 5 }
          )
        end

        it "should take two from the first damage of each Strike" do
          expect(weak['strikes'].map { |one| one['damage'].map(&:first) }).to eq [ [ '1d8+4', '1d6' ], [ '1d6-2' ] ]
        end

        it "should lower the DCs its abilities name by two, and take from what they deal" do
          expect(text_of(weak, 'Tail Sweep')).to eq 'Each creature within reach takes 2d6+1 bludgeoning damage with a DC 18 basic Reflex save.'
          expect(text_of(weak, 'Fire Breath')).to include('deals 4d6-4 fire damage', 'DC 18 basic Reflex')
        end

        { 1 => 10, 2 => 10, 3 => 15, 5 => 15, 6 => 20, 20 => 20, 21 => 30 }.each do |level, fewer|
          it "should take #{fewer} hit points from a creature that started at level #{level}" do
            expect(weak(level)['hp']).to eq 45 - fewer
          end
        end

        it "should leave a creature at least one hit point" do
          expect(Adjustments.apply(block(1).merge('hp' => 6), 'weak')['hp']).to eq 1
        end

        { 1 => -1, 2 => 1, 7 => 6, 0 => -1 }.each do |level, becomes|
          it "should make a level #{level} creature level #{becomes}" do
            expect(weak(level)['level']).to eq becomes
          end
        end
      end

      describe "a spell an adjusted creature casts" do
        def formulas
          [ [ '6d6', 'fire', nil, [ 'damage' ] ], [ '1d6', 'fire', 'persistent', [ 'damage' ] ] ]
        end

        def creature(adjustment)
          double(:adjustment => adjustment)
        end

        it "should deal four more from an elite creature, in its first damage" do
          expect(Adjustments.spell_damage(creature('elite'), { 'rank' => 3 }, formulas).map(&:first)).to eq [ '6d6+4', '1d6' ]
        end

        it "should deal two more where the spell is a cantrip, cast at will" do
          expect(Adjustments.spell_damage(creature('elite'), { 'rank' => 0 }, formulas).map(&:first)).to eq [ '6d6+2', '1d6' ]
        end

        it "should deal four less from a weak creature" do
          expect(Adjustments.spell_damage(creature('weak'), { 'rank' => 3 }, formulas).map(&:first)).to eq [ '6d6-4', '1d6' ]
        end

        it "should deal what it deals from any other creature, and from a character" do
          expect(Adjustments.spell_damage(creature(nil), { 'rank' => 3 }, formulas)).to eq formulas
          expect(Adjustments.spell_damage(Object.new, { 'rank' => 3 }, formulas)).to eq formulas
        end
      end
    end
  end
end
