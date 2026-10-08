require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A character who learned a spell by a name the remaster changed - an Enigma bard's True Strike - holds
    # a name the catalogue no longer has, and cannot cast it. `SpellRenames.migrate!` moves them onto the
    # new name everywhere the name is kept: the ledger, and what their magic holds.
    describe SpellRenames, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Bard#{rand(1000000)}", :pf2_level => 3,
                                 :pf2_base_info => { 'charclass' => 'Bard' })
        @magic = PF2Magic.create(:character => @char,
                                 :tradition => { 'Bard' => [ 'occult', 'trained' ] },
                                 :spell_abil => { 'Bard' => 'Charisma' },
                                 :spells_per_day => { 'Bard' => { '1' => 3 } },
                                 :repertoire => { 'Bard' => { '1' => [ 'True Strike', 'Fear' ] } },
                                 :signature_spells => { 'Bard' => { '1' => [ 'True Strike' ] } },
                                 :innate_spells => [ { 'name' => 'Unseen Servant', 'level' => 1, 'tradition' => 'occult',
                                                       'cast_stat' => 'Charisma' } ])
        @char.update(:magic => @magic)
        Ledger.seed_from_sheet!(Character[@char.id])
      end

      after(:each) do
        live = Character[@char.id]
        live.grants.each(&:delete)
        live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
        live.magic&.delete
        live.delete
      end

      def char
        Character[@char.id]
      end

      def known
        Pf2emagic::Entries.known_lists(char)['Bard']['1']
      end

      it "should hold the legacy names it is given" do
        expect(known).to include('True Strike')
      end

      it "should put the spell under its new name in what they know" do
        SpellRenames.migrate!(char)

        expect(known).to contain_exactly('Sure Strike', 'Fear')
      end

      it "should rename it in the ledger, where the next fold reads it" do
        SpellRenames.migrate!(char)
        Ledger.invalidate!(char)
        Ledger.materialize!(char)

        expect(known).to contain_exactly('Sure Strike', 'Fear')
        expect(Ledger.explain_for(char, :kind => 'spell_access', :key => 'True Strike')).to eq []
      end

      it "should rename it everywhere their magic holds it" do
        SpellRenames.migrate!(char)

        expect(char.magic.signature_spells).to eq('Bard' => { '1' => [ 'Sure Strike' ] })
        expect(char.magic.innate_spells.first['name']).to eq 'Phantasmal Minion'
      end

      it "should let them cast it" do
        SpellRenames.migrate!(char)
        Pf2emagic.generate_spells_today(char)

        expect(Pf2emagic.cast_spell(char, 'Bard', 'Sure Strike', [], '1')).to be_a Hash
      end

      it "should change nothing the second time" do
        SpellRenames.migrate!(char)

        expect(SpellRenames.migrate!(char)).to eq 0
      end
    end
  end
end
