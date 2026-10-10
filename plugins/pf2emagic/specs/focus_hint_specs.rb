require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # A spell someone tried to cast from a slot that is one of their focus spells is pointed at
    # cast/focus - where the name they typed is not a spell in its own right.
    describe "the hint that a spell is a focus spell" do
      before(:each) do
        @char = double(:magic => double)
        allow(Global).to receive(:read_config).with('pf2e_magic', 'focus_type_by_source', 'Druid').and_return('druid')
        allow(Global).to receive(:read_config).with('pf2e_spells').and_return('Heal' => {}, 'Heal Animal' => {}, 'Tempest Surge' => {})
        allow(Entries).to receive(:focus_spells).and_return([ 'Heal Animal', 'Tempest Surge' ])
        allow(Entries).to receive(:focus_cantrips).and_return([])
        stub_translate_for_testing
      end

      it "should point part of a focus spell's name at cast/focus" do
        expect(Pf2emagic.focus_casting_mismatch_msg(@char, 'Druid', 'tempest')).to eq 'pf2emagic.focus_spell_cast_cmd'
      end

      it "should say nothing of a name that is a spell of its own" do
        expect(Pf2emagic.focus_casting_mismatch_msg(@char, 'Druid', 'heal')).to be_nil
      end

      it "should point a focus spell named in full at cast/focus" do
        expect(Pf2emagic.focus_casting_mismatch_msg(@char, 'Druid', 'Heal Animal')).to eq 'pf2emagic.focus_spell_cast_cmd'
      end

      it "should read what was typed as words, whatever is in them" do
        expect(Pf2emagic.focus_casting_mismatch_msg(@char, 'Druid', 'heal (')).to be_nil
        expect(Pf2emagic.get_spells_by_name('heal (')).to eq []
      end
    end
  end
end
