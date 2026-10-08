require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A creature's Strikes as a stat block prints them: `Ranged Javelin +6 (thrown-30), 1d6+4 piercing`.
    describe StatBlock do

      def strike_line(strike)
        block = { 'level' => 1, 'traits' => [], 'ac' => 15, 'hp' => 20, 'perception' => 5, 'saves' => {},
                  'strikes' => [ strike ] }

        StatBlock.lines('Boggard', block).find { |line| line.include?(strike['name']) }
      end

      it "should leave out the parentheses of a Strike with no traits" do
        line = strike_line('name' => 'Club', 'bonus' => 10, 'traits' => [], 'damage' => [ [ '1d6+6', 'bludgeoning' ] ])

        expect(line).to eq 'Melee Club +10, 1d6+6 bludgeoning'
      end

      it "should call a thrown Strike ranged" do
        line = strike_line('name' => 'Javelin', 'bonus' => 6, 'traits' => [ 'thrown-30' ], 'damage' => [ [ '1d6+4', 'piercing' ] ])

        expect(line).to eq 'Ranged Javelin +6 (thrown-30), 1d6+4 piercing'
      end

      it "should read a thrown Strike's range increment from its trait" do
        expect(Npcs.range_of('traits' => [ 'agile', 'thrown-30' ])).to eq 30
        expect(Npcs.range_of('traits' => [ 'range-increment-60' ])).to eq 60
        expect(Npcs.range_of('range' => 100, 'traits' => [])).to eq 100
        expect(Npcs.range_of('traits' => [ 'reach-10' ])).to eq 0
      end

      it "should give a Strike that deals no damage only what it does" do
        line = strike_line('name' => 'Tongue', 'bonus' => 10, 'traits' => [ 'reach-10' ], 'damage' => [],
                           'effects' => [ 'Tongue Grab' ])

        expect(line).to eq 'Melee Tongue +10 (reach-10), Tongue Grab'
      end
    end
  end
end
