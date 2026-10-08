require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A hit's damage of one type is added together before a resistance or weakness to it applies: a
    # rapier's piercing and a swashbuckler's precise strike are one piercing amount, and a bomb's splash
    # joins its fire.
    describe "a hit's damage by type" do
      it "should add the rows of a type together" do
        rows = [ { 'amount' => 14, 'type' => 'piercing', 'category' => nil },
                 { 'amount' => 5, 'type' => 'piercing', 'category' => 'precision' },
                 { 'amount' => 3, 'type' => 'fire', 'category' => nil } ]

        expect(DamageRoll.by_type(rows)).to eq [
          { 'amount' => 19, 'type' => 'piercing', 'categories' => [ 'precision' ], 'splash' => 0, 'formula' => nil },
          { 'amount' => 3, 'type' => 'fire', 'categories' => [], 'splash' => 0, 'formula' => nil } ]
      end

      it "should fold splash into the damage of its type" do
        rows = [ { 'amount' => 6, 'type' => 'fire', 'category' => nil },
                 { 'amount' => 2, 'type' => 'fire', 'category' => 'splash' } ]

        expect(DamageRoll.by_type(rows).map { |row| [ row['amount'], row['splash'] ] }).to eq [ [ 8, 2 ] ]
      end

      it "should keep splash of a type nothing else deals as splash" do
        rows = [ { 'amount' => 2, 'type' => 'fire', 'category' => 'splash' } ]

        expect(DamageRoll.by_type(rows).first['categories']).to eq [ 'splash' ]
      end
    end
  end
end
