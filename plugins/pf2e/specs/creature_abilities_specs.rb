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

        it "should read an immunity that only a critical success gives, from that outcome's own paragraph" do
          text = 'Each creature must attempt a DC 34 Will save.%rCritical Success The creature is unaffected and is ' \
                 'temporarily immune for 24 hours.%rSuccess The creature is Stupefied 1 for 1 round.'

          expect(CreatureAbilities.saving(text)['immune']).to eq('after' => 'critical', 'rounds' => 1000)
        end

        it "should read an immunity that only a success gives" do
          expect(CreatureAbilities.saving(stench)['immune']).to eq('after' => 'success', 'rounds' => 10)
        end

        it "should read outcomes given as sentences: on a failure, and what a critical failure makes of it" do
          text = 'The ghost laments its fate, forcing each living creature within 30 feet to attempt a DC 21 Will save. ' \
                 'On a failure, a creature becomes Frightened 2 (or Frightened 3 on a critical failure). On a success, a ' \
                 "creature is temporarily immune to this ghost's frightful moan for 1 minute."

          expect(CreatureAbilities.saving(text)).to include(
            'outcomes' => { 'failure' => [ { 'condition' => 'Frightened', 'value' => 2 } ],
                            'criticalFailure' => [ { 'condition' => 'Frightened', 'value' => 3 } ] },
            'immune' => { 'after' => 'success', 'rounds' => 10 }
          )
        end

        it "should read what a creature that fails becomes" do
          text = '(1d10+7) bludgeoning, DC 26 basic Fortitude%rThe monster deals the listed amount of damage. A creature ' \
                 'that fails this save falls Unconscious, and a creature that succeeds is then temporarily immune.'

          expect(CreatureAbilities.saving(text)['outcomes']['failure']).to eq [ { 'condition' => 'Unconscious' } ]
        end

        it "should read an outcome that opens with if it fails, and how long it lasts" do
          text = '30 feet.%rWhen a creature ends its turn in the aura, it must attempt a DC 25 Fortitude save. If the ' \
                 'creature fails, it becomes Slowed 1 for 1 minute.'

          expect(CreatureAbilities.saving(text)['outcomes']['failure']).to eq [ { 'condition' => 'Slowed', 'value' => 1, 'until' => 'rounds:10' } ]
        end

        it "should read a save named some words before its or-else, and damage only a critical failure takes" do
          text = 'DC 16 Reflex%rEffect The triggering creature must succeed at a Reflex saving throw against the listed DC ' \
                 'or fall off the creature and land Prone. If the save is a critical failure, the triggering creature also ' \
                 'takes 1d6 bludgeoning damage in addition to the normal damage for the fall.'
          read = CreatureAbilities.saving(text)

          expect(read['damage']).to eq []
          expect(read['outcomes']).to eq(
            'failure' => [ { 'condition' => 'Prone' } ],
            'criticalFailure' => [ { 'condition' => 'Prone' }, { 'damage' => '1d6', 'type' => 'bludgeoning' } ]
          )
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

        # A poltergeist's Frighten.
        it "should read an outcome a sentence closes with, and what a critical failure adds for as long as it lasts" do
          text = 'Each creature within 30 feet must attempt a DC 21 Will save, becoming Frightened 2 on a failure. ' \
                 "On a critical failure, it's also Fleeing for as long as it's frightened. " \
                 'On a success, the creature is temporarily immune for 1 minute.'
          read = CreatureAbilities.saving(text)

          expect(read['outcomes']['failure']).to eq [ { 'condition' => 'Frightened', 'value' => 2 } ]
          expect(read['outcomes']['criticalFailure']).to eq [ { 'condition' => 'Frightened', 'value' => 2 }, { 'condition' => 'Fleeing' } ]
          expect(read['immune']).to eq('after' => 'success', 'rounds' => 10)
        end

        it "should read damage whose formula is in brackets" do
          text = 'The triggering enemy takes (2d8+9) bludgeoning damage (DC 25 basic Reflex save).'

          expect(CreatureAbilities.saving(text)).to include('dc' => 25, 'basic' => true, 'damage' => [ %w{2d8+9 bludgeoning} ])
        end

        # A troop's attack: one to three actions, and more damage for each.
        describe "whose damage is by the actions spent on it" do
          def onslaught
            '1 to 3%rFrequency once per round%rEffect The soldiers lash out (DC 18 basic Reflex save). The damage depends ' \
              'on the number of actions.%r1 1d8 bludgeoning damage plus 1d6 sonic damage%r2 (2d6+9) bludgeoning damage%r' \
              '3 (3d6+10) bludgeoning damage'
          end

          it "should read what each number of actions deals" do
            expect(CreatureAbilities.by_actions(onslaught)).to eq(
              1 => [ %w{1d8 bludgeoning}, %w{1d6 sonic} ], 2 => [ %w{2d6+9 bludgeoning} ], 3 => [ %w{3d6+10 bludgeoning} ]
            )
          end

          it "should deal the least where nobody says how many" do
            expect(CreatureAbilities.saving(onslaught)['damage']).to eq [ %w{1d8 bludgeoning}, %w{1d6 sonic} ]
          end

          it "should deal what the actions spent deal" do
            expect(CreatureAbilities.saving(onslaught, 3)['damage']).to eq [ %w{3d6+10 bludgeoning} ]
          end

          it "should have nothing to say of an ability with one cost" do
            expect(CreatureAbilities.by_actions('Deals 2d6 fire damage (DC 20 basic Reflex save).')).to eq({})
          end
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
