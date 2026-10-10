require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a creature's ability deals and the save against it, from its stat block's words.
    describe CreatureAbilities do
      it "should read a Constrict's listed damage and save" do
        expect(CreatureAbilities.damage_save('(2d10+17) bludgeoning, DC 40 Fortitude')).to eq(
          'formula' => '2d10+17', 'type' => 'bludgeoning', 'dc' => 40, 'save' => 'fortitude')
      end

      it "should read it where the save is called basic" do
        expect(CreatureAbilities.damage_save('(1d8) bludgeoning, DC 17 basic Fortitude%rThe monster deals the listed amount.')).to eq(
          'formula' => '1d8', 'type' => 'bludgeoning', 'dc' => 17, 'save' => 'fortitude')
      end

      it "should read a breath's damage and the save its sentence names" do
        text = 'The fire scamp breathes flames in a 15-foot cone that deals 2d4 fire damage to each creature ' \
               'within the area (DC 17 Reflex save).'

        expect(CreatureAbilities.damage_save(text)).to eq('formula' => '2d4', 'type' => 'fire', 'dc' => 17, 'save' => 'reflex')
      end

      it "should leave an ability that lists its outcomes to the GM" do
        text = 'Deals 4d6 cold damage (DC 25 Fortitude save).%rCritical Success unaffected%rCritical Failure frozen'

        expect(CreatureAbilities.damage_save(text)).to be_nil
      end

      it "should find nothing in words that deal no damage" do
        expect(CreatureAbilities.damage_save('The kraken moves through the water up to 280 feet.')).to be_nil
      end

      # A save whose outcomes the words give, where they leave conditions: an aura of fear, a stench.
      describe "an ability whose words call for a save" do
        def presence
          '30 feet. DC 23 Will%rA creature that first enters the area must attempt a Will save.%r' \
            "Regardless of the result of the saving throw, the creature is temporarily immune to this monster's " \
            'Frightful Presence for 1 minute.%rCritical Success The creature is unaffected by the presence.%r' \
            'Success The creature is Frightened 1.%rFailure The creature is Frightened 2.%r' \
            'Critical Failure The creature is Frightened 4.'
        end

        def stench
          '10 feet. DC 14 Fortitude%rA creature entering the aura or starting its turn in the area must succeed at a ' \
            "Fortitude save or become Sickened 1 (plus Slowed 1 as long as it's sickened on a critical failure). A creature " \
            'that succeeds at its save or recovers from being sickened is temporarily immune to all stench auras for 1 minute.'
        end

        it "should read the save and each outcome that has a paragraph of its own" do
          expect(CreatureAbilities.saving(presence)).to include(
            'dc' => 23, 'save' => 'will', 'basic' => false,
            'outcomes' => { 'success' => [ { 'condition' => 'Frightened', 'value' => 1 } ],
                            'failure' => [ { 'condition' => 'Frightened', 'value' => 2 } ],
                            'criticalFailure' => [ { 'condition' => 'Frightened', 'value' => 4 } ] }
          )
        end

        it "should keep each outcome's words for the room" do
          expect(CreatureAbilities.saving(presence)['outcome_text']['criticalSuccess']).to eq 'The creature is unaffected by the presence.'
        end

        it "should read how long whoever saved is immune to it afterwards, whatever they rolled" do
          expect(CreatureAbilities.saving(presence)['immune']).to eq('after' => 'any', 'rounds' => 10)
        end

        it "should read the outcomes of a save a sentence gives: succeed, or else" do
          expect(CreatureAbilities.saving(stench)).to include(
            'dc' => 14, 'save' => 'fortitude',
            'outcomes' => { 'failure' => [ { 'condition' => 'Sickened', 'value' => 1 } ],
                            'criticalFailure' => [ { 'condition' => 'Sickened', 'value' => 1 }, { 'condition' => 'Slowed', 'value' => 1 } ] }
          )
        end

        it "should read an immunity that only a success gives" do
          expect(CreatureAbilities.saving(stench)['immune']).to eq('after' => 'success', 'rounds' => 10)
        end

        it "should read how long a condition lasts" do
          text = 'The creature must succeed at a DC 20 Will save or be Stunned 1 and Dazzled for 1 minute.'

          expect(CreatureAbilities.saving(text)['outcomes']['failure']).to eq [
            { 'condition' => 'Stunned', 'value' => 1 }, { 'condition' => 'Dazzled', 'until' => 'rounds:10' }
          ]
        end

        it "should read the damage where the words give it against the save" do
          text = 'Each enemy in the swarm\'s space takes 1d6 piercing damage and must attempt a DC 17 basic Reflex save.'

          expect(CreatureAbilities.saving(text)).to include('dc' => 17, 'save' => 'reflex', 'basic' => true,
                                                           'damage' => [ %w{1d6 piercing} ])
        end

        it "should read the persistent damage a failure also takes" do
          text = 'The fire scamp breathes flames in a 15-foot cone that deals 2d4 fire damage to each creature within the area ' \
                 '(DC 17 basic Reflex save). Creatures that fail the save also take 1d4 persistent fire damage.'

          expect(CreatureAbilities.saving(text)).to include('damage' => [ %w{2d4 fire} ], 'persistent' => [ %w{1d4 fire} ])
        end

        it "should leave a condition that depends on something else to the words" do
          text = 'That creature must attempt a DC 22 Fortitude save. If it fails and has not already been slowed by this ability, ' \
                 'it becomes Slowed 1. If the creature was already slowed by this ability, a failed save causes the creature to be ' \
                 'Petrified permanently.'

          expect(CreatureAbilities.saving(text)).to include('dc' => 22, 'save' => 'fortitude', 'outcomes' => {})
        end

        it "should have nothing to say of an affliction, which has stages" do
          expect(CreatureAbilities.saving('Saving Throw DC 19 Fortitude%rMaximum Duration 6 rounds%rStage 1 Clumsy 1 (1 round)')).to be_nil
        end

        it "should have nothing to say of words with no save" do
          expect(CreatureAbilities.saving('The kraken moves through the water up to 280 feet.')).to be_nil
        end
      end
    end
  end
end
