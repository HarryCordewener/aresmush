require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Persistent damage an outcome scales: doubled, halved, or none.
    describe "a scaled persistent formula" do
      it "should double each term" do
        expect(Pf2e.scaled_formula('2d6+3', 2)).to eq '4d6+6'
      end

      it "should halve each term where that comes out whole" do
        expect(Pf2e.scaled_formula('2d6', 0.5)).to eq '1d6'
      end

      it "should halve the whole as it is rolled where it does not" do
        expect(Pf2e.scaled_formula('1d6', 0.5)).to eq '1d6/2'
      end

      it "should leave a scale of 1 alone, and give nothing for 0" do
        expect(Pf2e.scaled_formula('1d6', 1)).to eq '1d6'
        expect(Pf2e.scaled_formula('1d6', 0)).to be_nil
      end

      it "should roll a halved formula as half the roll, rounded down" do
        allow(Pf2e).to receive(:roll_dice).and_return([ 5 ])

        expect(Pf2e.roll_formula('1d6/2')).to eq 2
        expect(Pf2e.average('1d6/2')).to eq 1.75
      end
    end
  end
end
