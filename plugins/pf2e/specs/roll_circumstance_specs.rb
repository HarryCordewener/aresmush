require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `roll thievery/pick-a-lock` - what the roller says they are doing, which decides whether a
    # conditional bonus counts. A number after the slash is still the DC.
    describe "naming a circumstance in a roll" do

      it "should slug what the player typed" do
        expect(Pf2e.circumstances([ 'Pick A Lock' ])).to eq [ 'pick-a-lock', 'action:pick-a-lock' ]
      end

      # Foundry spells an action `action:<slug>` and a circumstance that is not an action as a bare
      # word. A player should not have to know which, so both are offered.
      it "should offer each circumstance in both of Foundry's spellings" do
        expect(Pf2e.circumstances([ 'visual' ])).to include 'visual', 'action:visual'
      end

      it "should take several" do
        expect(Pf2e.circumstances([ 'swim', 'track' ]))
          .to eq [ 'swim', 'action:swim', 'track', 'action:track' ]
      end

      it "should ignore an empty one" do
        expect(Pf2e.circumstances([ '', '  ' ])).to eq []
      end

      it "should have nothing to say when nothing was named" do
        expect(Pf2e.circumstances(nil)).to eq []
      end

      # A hyphen in a roll string ordinarily starts a negative term, which is why a circumstance is
      # named after a slash rather than as one of the terms.
      describe "the terms either side of it" do
        it "should still read a negative term" do
          expect(Pf2e.roll_terms('athletics-2')).to eq [ 'athletics', '-2' ]
        end

        it "should still read a sum" do
          expect(Pf2e.roll_terms('1d20+stealth+3')).to eq [ '1d20', 'stealth', '3' ]
        end
      end
    end
  end
end
