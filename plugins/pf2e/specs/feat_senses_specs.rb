require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A sense a feat grants for good, kept in pf2_special beside the ancestry's own.
    describe "senses from feats" do

      describe :with_senses do
        it "should add a sense the character does not have" do
          expect(Pf2e.with_senses([ 'Keen Eyes' ], [ 'Darkvision' ])).to eq [ 'Keen Eyes', 'Darkvision' ]
        end

        it "should not add a sense twice, whatever its case" do
          expect(Pf2e.with_senses([ 'darkvision' ], [ 'Darkvision' ])).to eq [ 'darkvision' ]
        end

        # As a heritage's darkvision does at chargen.
        it "should replace low-light vision with darkvision" do
          expect(Pf2e.with_senses([ 'Low-light Vision', 'Keen Eyes' ], [ 'Darkvision' ])).to eq [ 'Keen Eyes', 'Darkvision' ]
        end

        it "should leave low-light vision alone for any other sense" do
          expect(Pf2e.with_senses([ 'Low-Light Vision' ], [ 'Imprecise Scent' ])).to eq [ 'Low-Light Vision', 'Imprecise Scent' ]
        end

        it "should start from nothing" do
          expect(Pf2e.with_senses(nil, [ 'Darkvision' ])).to eq [ 'Darkvision' ]
        end
      end

      describe "the feats" do
        before(:all) do
          @feats = YAML.load_file("game/config/pf2e_feat_ancestry.yml")['pf2e_feats']
        end

        # Each says "You gain darkvision" with no condition attached.
        [ 'Eyes of Night', 'Gravesight', "Hag's Sight", 'Nephilim Eyes', 'Oruch Sight' ].each do |name|
          it "should grant #{name}'s darkvision" do
            feat = @feats.fetch(name)

            expect(feat['shortdesc']).to include('You gain darkvision')
            expect(feat['grants']['special']).to eq [ 'Darkvision' ]
          end
        end
      end

      describe "on a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Senses#{rand(1000000)}")
          @char.update(:pf2_level => 1, :pf2_special => [ 'Low-Light Vision' ])
        end

        after(:each) do
          Pf2e::Ledger.delete_all!(@char) if @char
          Pf2e::Audit.delete_all!(@char) if @char
          @char.delete if @char
        end

        def grant_darkvision
          grants = Global.read_config('pf2e_feats', 'Eyes of Night', 'grants')

          Pf2e.do_feat_grants(Character[@char.id], grants, 'Fighter', nil)
        end

        it "should write darkvision in place of low-light vision" do
          messages = grant_darkvision

          expect(Character[@char.id].pf2_special).to eq [ 'Darkvision' ]
          expect(messages).to eq [ t('pf2e.feat_grants_special', :special => 'Darkvision') ]
        end

        it "should reach the ledger when the sheet is synced" do
          Pf2e::Ledger.seed_from_sheet!(Character[@char.id])
          grant_darkvision

          Pf2e::Ledger.sync_sheet!(Character[@char.id], :source_type => 'chargen', :effective_level => 1)

          char = Character[@char.id]

          expect(Pf2e::Ledger.derived(char)['specials']).to eq [ 'Darkvision' ]
          expect(char.pf2_special).to eq [ 'Darkvision' ]
        end
      end
    end
  end
end
