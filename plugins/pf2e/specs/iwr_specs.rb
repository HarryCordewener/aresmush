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
      end
    end
  end
end
