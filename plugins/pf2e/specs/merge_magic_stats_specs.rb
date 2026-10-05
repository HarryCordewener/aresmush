require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Two sources staging magic for the same class in one level-up.
    describe "merge_magic_stats" do

      it "should keep the focus spells of two sources" do
        merged = Pf2e.merge_magic_stats({ 'focus_spell' => { 'domain' => [ 'Unity' ] } },
                                        { 'focus_spell' => { 'revelation' => [ 'Thunderburst' ] } })

        expect(merged['focus_spell']).to eq('domain' => [ 'Unity' ], 'revelation' => [ 'Thunderburst' ])
      end

      it "should keep a key only one source has" do
        merged = Pf2e.merge_magic_stats({ 'spell_abil' => 'Wisdom' }, { 'focus_spell' => { 'domain' => [ 'Unity' ] } })

        expect(merged).to eq('spell_abil' => 'Wisdom', 'focus_spell' => { 'domain' => [ 'Unity' ] })
      end

      it "should merge hashes and join lists" do
        merged = Pf2e.merge_magic_stats(
          { 'spells_per_day' => { '1' => 3 }, 'list' => [ 'a' ] },
          { 'spells_per_day' => { '2' => 1 }, 'list' => [ 'b' ] })

        expect(merged).to eq('spells_per_day' => { '1' => 3, '2' => 1 }, 'list' => [ 'a', 'b' ])
      end

      it "should let the later value win for any other key" do
        merged = Pf2e.merge_magic_stats({ 'spell_abil' => 'Wisdom' }, { 'spell_abil' => 'Charisma' })

        expect(merged['spell_abil']).to eq 'Charisma'
      end
    end
  end
end
