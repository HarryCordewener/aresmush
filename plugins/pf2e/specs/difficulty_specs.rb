require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter's threat and PF2e's recommended rewards, against GM Core's own tables.
    describe Difficulty do

      let(:table) { YAML.load_file(File.join(AresMUSH.game_path, 'config', 'pf2e_rewards.yml'))['pf2e_rewards'] }

      def rated(creatures, characters, level: nil)
        Difficulty.of(creatures, characters, :level => level, :table => table)
      end

      # A threat is measured against a party, so before anyone joins there is nothing to measure.
      it "should say there is no threat to read before any character joins" do
        expect(Difficulty.line(rated([ 2, -1 ], []), false)).to eq t('pf2e.difficulty_no_party')
        expect(Difficulty.line(rated([ 2 ], [ 1 ]), false)).to include('for a party of 1 at level 1')
      end

      it "should price a creature by its level against the party's" do
        expect(Difficulty.creature_xp(2, 5, table)).to eq 15
        expect(Difficulty.creature_xp(5, 5, table)).to eq 40
        expect(Difficulty.creature_xp(9, 5, table)).to eq 160
        expect(Difficulty.creature_xp(0, 5, table)).to eq 0
      end

      # GM Core's example: 5th-level PCs, and creatures totalling a moderate 80.
      it "should rate an encounter against the budget for four" do
        result = rated([ 7, 5 ], [ 5, 5, 5, 5 ])

        expect(result).to include('xp' => 120, 'threat' => 'severe', 'award' => 120, 'party_level' => 5)
        expect(rated([ 5, 5 ], [ 5, 5, 5, 5 ])).to include('xp' => 80, 'threat' => 'moderate')
      end

      it "should widen the budget for a larger party, and award as for four" do
        result = rated([ 5, 5, 4 ], [ 5, 5, 5, 5, 5 ])

        expect(result).to include('xp' => 110, 'threat' => 'severe', 'budget' => 150, 'award' => 80)
      end

      it "should narrow it for a smaller party" do
        expect(rated([ 5 ], [ 5, 5, 5 ])).to include('xp' => 40, 'threat' => 'low', 'budget' => 40, 'award' => 60)
      end

      it "should use the level the GM set over the characters' average" do
        expect(rated([ 3 ], [ 2, 3, 4, 5 ])).to include('party_level' => 3)
        expect(rated([ 3 ], [ 2, 3, 4, 5 ], :level => 6)).to include('party_level' => 6, 'xp' => 15)
      end

      it "should say when an encounter is past extreme, or a creature past the table" do
        result = rated([ 10, 5 ], [ 5, 5, 5, 5 ])

        expect(result).to include('threat' => 'beyond extreme', 'past_the_table' => true)
      end

      it "should recommend GM Core's treasure for the threat, and currency for each extra character" do
        expect(Difficulty.treasure(rated([ 5, 5 ], [ 5, 5, 5, 5 ]), table)).to eq('gp' => 135, 'per_additional_pc' => 0)
        expect(Difficulty.treasure(rated([ 5, 5, 4 ], [ 5, 5, 5, 5, 5 ]), table)).to eq('gp' => 200, 'per_additional_pc' => 80)
      end
    end
  end
end
