require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a character shrugs off, and what hurts them more.
    #
    # The other side of the damage work: damage has a kind now, so something can care what kind it is.
    # The order and the "highest, not the sum" rule are theirs (`system/damage/iwr.ts`), and the second
    # matters for the same reason it does in modifier stacking - two resistances of 5 are resistance 5.
    describe IWR do

      def held(immunity: [], weakness: [], resistance: [])
        { 'immunity' => immunity, 'weakness' => weakness, 'resistance' => resistance }
      end

      def entry(type, value = nil)
        { 'source' => 'Something', 'type' => type, 'value' => value }
      end

      describe "immunity" do
        it "should take all of it" do
          result = IWR.apply(held(:immunity => [ entry('fire') ]), 12, 'fire')

          expect(result['amount']).to eq 0
        end

        it "should say it was immunity that did it" do
          result = IWR.apply(held(:immunity => [ entry('fire') ]), 12, 'fire')

          expect(result['applied'].first['category']).to eq 'immunity'
          expect(result['applied'].first['adjustment']).to eq(-12)
        end

        it "should not touch damage of another kind" do
          expect(IWR.apply(held(:immunity => [ entry('fire') ]), 12, 'cold')['amount']).to eq 12
        end
      end

      describe "weakness" do
        it "should add its value" do
          expect(IWR.apply(held(:weakness => [ entry('fire', 5) ]), 12, 'fire')['amount']).to eq 17
        end

        # The highest, once - not one addition per weakness.
        it "should add only the highest of several" do
          two = held(:weakness => [ entry('fire', 5), entry('fire', 10) ])

          expect(IWR.apply(two, 12, 'fire')['amount']).to eq 22
        end
      end

      describe "resistance" do
        it "should subtract its value" do
          expect(IWR.apply(held(:resistance => [ entry('fire', 5) ]), 12, 'fire')['amount']).to eq 7
        end

        it "should subtract only the highest of several" do
          two = held(:resistance => [ entry('fire', 5), entry('fire', 10) ])

          expect(IWR.apply(two, 12, 'fire')['amount']).to eq 2
        end

        # Resistance reduces damage; it does not heal.
        it "should not take damage below nothing" do
          expect(IWR.apply(held(:resistance => [ entry('fire', 20) ]), 12, 'fire')['amount']).to eq 0
        end

        it "should say how much it actually took" do
          result = IWR.apply(held(:resistance => [ entry('fire', 20) ]), 12, 'fire')

          expect(result['applied'].first['adjustment']).to eq(-12)
        end
      end

      # Weakness before resistance, which is their order and not the same as the other way round: 12 fire
      # with weakness 5 and resistance 10 is 7, where resisting first would give 7 too - so the case that
      # distinguishes them is one where resisting first would floor at nothing.
      describe "all three together" do
        it "should weaken before resisting" do
          both = held(:weakness => [ entry('fire', 10) ], :resistance => [ entry('fire', 15) ])

          expect(IWR.apply(both, 8, 'fire')['amount']).to eq 3
        end

        it "should let immunity end it before either" do
          all = held(:immunity => [ entry('fire') ], :weakness => [ entry('fire', 10) ],
                     :resistance => [ entry('fire', 5) ])

          expect(IWR.apply(all, 8, 'fire')['amount']).to eq 0
          expect(IWR.apply(all, 8, 'fire')['applied'].size).to eq 1
        end

        it "should report each thing that applied" do
          both = held(:weakness => [ entry('fire', 5) ], :resistance => [ entry('fire', 2) ])

          expect(IWR.apply(both, 8, 'fire')['applied'].map { |one| one['category'] })
            .to eq [ 'weakness', 'resistance' ]
        end
      end

      # A category is matched as readily as the kind, which is how resistance to persistent damage works.
      describe "matching" do
        it "should match a category the damage carries" do
          result = IWR.apply(held(:resistance => [ entry('persistent-damage', 3) ]), 8, 'fire',
                             [ 'persistent-damage' ])

          expect(result['amount']).to eq 5
        end

        it "should not care how the kind was capitalised" do
          expect(IWR.apply(held(:resistance => [ entry('Fire', 5) ]), 12, 'fire')['amount']).to eq 7
        end

        it "should do nothing at all when the character has none" do
          expect(IWR.apply(held, 12, 'fire')['amount']).to eq 12
        end

        # Unstoppable Juggernaut grants resistance to all damage, which is a type of its own.
        it "should match everything when the type says all damage" do
          held_all = held(:resistance => [ entry('all-damage', 5) ])

          expect(IWR.apply(held_all, 12, 'fire')['amount']).to eq 7
          expect(IWR.apply(held_all, 12, 'S')['amount']).to eq 7
        end

        # Some declare a list, meaning any of them.
        it "should match any of a list of kinds" do
          either = held(:immunity => [ entry([ 'vitality', 'void' ]) ])

          expect(IWR.apply(either, 12, 'void')['amount']).to eq 0
          expect(IWR.apply(either, 12, 'fire')['amount']).to eq 12
        end

        it "should do nothing when the damage has no kind" do
          expect(IWR.apply(held(:resistance => [ entry('fire', 5) ]), 12, nil)['amount']).to eq 12
        end

        it "should read a weapon's letter as its kind of damage" do
          expect(IWR.apply(held(:resistance => [ entry('slashing', 5) ]), 12, 'S')['amount']).to eq 7
        end
      end

      # A type may be a whole category of damage: bludgeoning, piercing and slashing are physical.
      describe "a category of damage" do
        it "should take physical for bludgeoning, piercing and slashing" do
          swarm = held(:resistance => [ entry('physical', 6) ])

          %w{bludgeoning piercing slashing}.each { |kind| expect(IWR.apply(swarm, 10, kind)['amount']).to eq 4 }
          expect(IWR.apply(swarm, 10, 'fire')['amount']).to eq 10
        end

        it "should take energy for fire, cold and the rest, and not for poison or mental" do
          warded = held(:resistance => [ entry('energy', 5) ])

          %w{acid cold electricity fire force sonic vitality void}.each { |kind| expect(IWR.apply(warded, 10, kind)['amount']).to eq 5 }
          %w{poison mental slashing spirit}.each { |kind| expect(IWR.apply(warded, 10, kind)['amount']).to eq 10 }
        end
      end

      # What the damage is made of and how it came, beyond its kind: silver, magical, from a spell, in an area.
      describe "what else is so of the damage" do
        it "should weaken by a material the weapon is made of" do
          fey = held(:weakness => [ entry('cold-iron', 5) ])

          expect(IWR.apply(fey, 10, 'slashing', [ 'cold iron' ])['amount']).to eq 15
          expect(IWR.apply(fey, 10, 'slashing')['amount']).to eq 10
        end

        it "should weaken by a trait the attack has" do
          fiend = held(:weakness => [ entry('holy', 5) ])

          expect(IWR.apply(fiend, 10, 'slashing', [ 'holy' ])['amount']).to eq 15
          expect(IWR.apply(fiend, 10, 'slashing', [ 'magical' ])['amount']).to eq 10
        end

        it "should weaken a swarm by damage dealt to an area, and by a splash" do
          swarm = held(:weakness => [ entry('area-damage', 3), entry('splash-damage', 3) ])

          expect(IWR.apply(swarm, 6, 'fire', [ 'area' ])['amount']).to eq 9
          expect(IWR.apply(swarm, 2, 'fire', [ 'splash' ])['amount']).to eq 5
          expect(IWR.apply(swarm, 6, 'fire')['amount']).to eq 6
        end

        it "should resist what comes from a spell" do
          golem = held(:resistance => [ entry('spells', 20) ])

          expect(IWR.apply(golem, 30, 'fire', [ 'spell' ])['amount']).to eq 10
          expect(IWR.apply(golem, 30, 'fire')['amount']).to eq 30
        end

        it "should take a fact spelled as the rules spell it" do
          fey = held(:weakness => [ entry('cold-iron', 5) ])

          expect(IWR.apply(fey, 10, 'slashing', [ 'damage:material:cold-iron' ])['amount']).to eq 15
        end
      end

      describe "an exception" do
        def devil
          held(:resistance => [ entry('physical', 10).merge('exceptions' => [ 'silver' ]) ])
        end

        it "should let through what it names" do
          expect(IWR.apply(devil, 12, 'slashing', [ 'silver' ])['amount']).to eq 12
        end

        it "should leave the rest resisted" do
          expect(IWR.apply(devil, 12, 'slashing')['amount']).to eq 2
        end

        it "should say what it excepts where it applied" do
          expect(IWR.apply(devil, 12, 'slashing')['applied'].first['type']).to eq 'physical (except silver)'
        end

        it "should let through a kind of damage it names" do
          ghost = held(:resistance => [ entry('all-damage', 5).merge('exceptions' => %w{force ghost-touch spirit vitality}) ])

          expect(IWR.apply(ghost, 12, 'force')['amount']).to eq 12
          expect(IWR.apply(ghost, 12, 'slashing', [ 'ghost touch' ])['amount']).to eq 12
          expect(IWR.apply(ghost, 12, 'slashing', [ 'magical' ])['amount']).to eq 7
        end

        it "should be read where it is a description of its own" do
          entry = entry('physical', 5).merge('exceptions' => [ { 'definition' => [ 'item:category:unarmed' ] } ])

          expect(IWR.apply(held(:resistance => [ entry ]), 12, 'bludgeoning', [ 'unarmed' ])['amount']).to eq 12
          expect(IWR.apply(held(:resistance => [ entry ]), 12, 'bludgeoning')['amount']).to eq 7
        end
      end

      describe "a resistance doubled against something" do
        def ghost
          held(:resistance => [ entry('all-damage', 5).merge('exceptions' => [ 'force' ], 'doubleVs' => [ 'non-magical' ]) ])
        end

        it "should be doubled against it" do
          expect(IWR.apply(ghost, 12, 'slashing')['amount']).to eq 2
        end

        it "should say what it is doubled against where it is named" do
          expect(IWR.label(ghost['resistance'].first)).to eq 'all-damage (except force; double against non-magical)'
        end

        it "should be itself against anything else" do
          expect(IWR.apply(ghost, 12, 'slashing', [ 'magical' ])['amount']).to eq 7
        end

        it "should win over a plain resistance it then exceeds" do
          both = held(:resistance => ghost['resistance'] + [ entry('slashing', 7) ])

          expect(IWR.apply(both, 12, 'slashing')['amount']).to eq 2
          expect(IWR.apply(both, 12, 'slashing', [ 'magical' ])['amount']).to eq 5
        end
      end

      # A weakness to something that is not itself a kind of damage - holy, water - is felt once in a hit,
      # however many kinds of damage the hit deals.
      describe "a weakness felt once in a hit" do
        it "should apply to the first of the hit's damage and not the rest" do
          fiend = held(:weakness => [ entry('holy', 5) ])
          felt = []

          first = IWR.apply(fiend, 10, 'slashing', [ 'holy' ], :once => felt)
          second = IWR.apply(fiend, 4, 'fire', [ 'holy' ], :once => felt)

          expect([ first['amount'], second['amount'] ]).to eq [ 15, 4 ]
        end

        it "should apply to each kind of damage where it is a weakness to damage itself" do
          troll = held(:weakness => [ entry('fire', 10) ])
          felt = []

          first = IWR.apply(troll, 10, 'fire', [], :once => felt)
          second = IWR.apply(troll, 4, 'fire', [], :once => felt)

          expect([ first['amount'], second['amount'] ]).to eq [ 20, 14 ]
        end
      end

      # Immunity to a condition or to a kind of effect is not about damage: it is asked of what would land.
      describe "immunity to a condition or an effect" do
        def undead
          held(:immunity => %w{paralyzed fear-effects death-effects poison mental sleep}.map { |type| entry(type) })
        end

        it "should hold against the condition it names" do
          expect(IWR.immune_to_condition?(undead, 'Paralyzed')).to be true
          expect(IWR.immune_to_condition?(undead, 'Frightened')).to be false
        end

        it "should hold against an effect with the trait it names" do
          expect(IWR.immune_to_effect?(undead, %w{emotion fear mental})).to eq 'fear-effects'
          expect(IWR.immune_to_effect?(undead, %w{death void})).to eq 'death-effects'
          expect(IWR.immune_to_effect?(undead, %w{poison})).to eq 'poison'
          expect(IWR.immune_to_effect?(undead, %w{incapacitation sleep})).to eq 'sleep'
        end

        it "should not hold against an effect without it" do
          expect(IWR.immune_to_effect?(undead, %w{fire attack})).to be_nil
        end

        it "should still take the damage of a kind it is not immune to" do
          expect(IWR.apply(undead, 10, 'fire')['amount']).to eq 10
          expect(IWR.apply(undead, 10, 'poison')['amount']).to eq 0
          expect(IWR.apply(undead, 10, 'mental')['amount']).to eq 0
        end

        it "should not be taken for immunity to damage" do
          expect(IWR.apply(held(:immunity => [ entry('paralyzed'), entry('fear-effects') ]), 10, 'slashing')['amount']).to eq 10
        end
      end

      # A will-o'-wisp is immune to all spells but a few it names.
      describe "immunity to magic" do
        def wisp
          excepted = { 'definition' => [ 'item:type:spell', { 'or' => %w{item:slug:force-barrage item:slug:quandary} } ],
                       'label' => 'PF2E.IWR.Custom.WispVulnerabilities' }

          held(:immunity => [ entry('magic').merge('exceptions' => [ excepted ]) ])
        end

        it "should keep out a spell and all it does" do
          expect(IWR.immune_to_effect?(wisp, %w{mental nonlethal}, DamageAbout.spell('Daze'))).to eq 'magic (except WispVulnerabilities)'
        end

        it "should let in a spell it excepts" do
          expect(IWR.immune_to_effect?(wisp, %w{force}, DamageAbout.spell('Force Barrage'))).to be_nil
          expect(IWR.apply(wisp, 10, 'force', DamageAbout.spell('Force Barrage'))['amount']).to eq 10
        end

        it "should not keep out what is no spell" do
          expect(IWR.immune_to_effect?(wisp, %w{mental emotion fear})).to be_nil
        end
      end

      describe "what a construct or an object keeps out" do
        it "should not keep out what a nonlethal spell does besides its damage" do
          construct = held(:immunity => [ entry('nonlethal-attacks') ])

          expect(IWR.immune_to_effect?(construct, %w{mental nonlethal}, DamageAbout.spell('Daze'))).to be_nil
        end

        it "should take nothing from an attack that is nonlethal" do
          construct = held(:immunity => [ entry('nonlethal-attacks') ])

          expect(IWR.apply(construct, 10, 'bludgeoning', [ 'item:trait:nonlethal' ])['amount']).to eq 0
          expect(IWR.apply(construct, 10, 'bludgeoning')['amount']).to eq 10
        end

        it "should take none of the damage an object is immune to, nor its conditions" do
          object = held(:immunity => [ entry('object-immunities') ])

          expect(%w{bleed mental poison spirit vitality void}.map { |kind| IWR.apply(object, 10, kind)['amount'] }).to eq [ 0 ] * 6
          expect(IWR.apply(object, 10, 'fire')['amount']).to eq 10
          expect(IWR.immune_to_condition?(object, 'Sickened')).to be true
          expect(IWR.immune_to_condition?(object, 'Prone')).to be false
        end
      end

      describe "a material that counts as another" do
        it "should have a resistance let keep stone through where it lets adamantine" do
          golem = held(:resistance => [ entry('physical', 10).merge('exceptions' => [ 'adamantine' ]) ])

          expect(IWR.apply(golem, 12, 'slashing', [ 'damage:material:keep-stone' ])['amount']).to eq 12
          expect(IWR.apply(golem, 12, 'slashing')['amount']).to eq 2
        end
      end

      describe "immunity to critical hits" do
        it "should be asked of a critical hit" do
          ooze = held(:immunity => [ entry('critical-hits'), entry('precision') ])

          expect(IWR.immune?(ooze, [ 'critical' ])).to be true
          expect(IWR.immune?(ooze, [ 'precision' ])).to be true
          expect(IWR.immune?(held(:immunity => [ entry('precision') ]), [ 'critical' ])).to be false
        end

        it "should not take ordinary damage" do
          expect(IWR.apply(held(:immunity => [ entry('critical-hits') ]), 10, 'slashing')['amount']).to eq 10
        end
      end
    end
  end
end
