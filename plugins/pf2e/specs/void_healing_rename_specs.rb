require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The Dar heritage grants Void Healing, the remaster's name for what it called Negative Healing, and
    # the engine reads that special to treat a Dar as the undead are treated by vitality and void.
    # `VoidHealingRename.migrate!` brings a Dar who took the heritage under the old name onto the new one.
    describe "renaming a Dar's Negative Healing to Void Healing", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @made = []
      end

      after(:each) do
        @made.each do |made|
          live = Character[made.id]
          next unless live

          live.grants.each(&:delete)
          live.magic&.delete
          live.delete
        end
      end

      def built(heritage = 'Dar')
        char = Character.create(:name => "Dar#{rand(1000000)}")
        @made << char

        AutoBuilder.new(char).build_level_one('Fighter', :ancestry => 'Human', :heritage => heritage)
        Character[char.id]
      end

      def approved(char)
        Roles.add_role(char, 'approved')
        Pf2e::Ledger.commit_chargen!(Character[char.id])
        Character[char.id]
      end

      def specials(char)
        Array(Character[char.id].pf2_special)
      end

      it "should give a Dar Void Healing in chargen" do
        expect(specials(built)).to include 'Void Healing'
        expect(specials(built)).to_not include 'Negative Healing'
      end

      describe "a Dar who took the heritage under the old name" do

        # The shape the old heritage left: a "Negative Healing" special in the ledger.
        def old_shape(char)
          Pf2e::Ledger.revert_matching!(char, 'add_special', { 'special' => 'Void Healing' }, :by => 'spec')
          Pf2e::Ledger.write(char, :source_type => 'chargen', :source_ref => 'old Dar', :effective_level => 1) do |txn|
            txn.grant('add_special', 'special' => 'Negative Healing')
          end

          Character[char.id]
        end

        before(:each) do
          @char = old_shape(approved(built))
        end

        it "should start in the old shape" do
          expect(specials(@char)).to include 'Negative Healing'
          expect(specials(@char)).to_not include 'Void Healing'
        end

        it "should rename the special, and keep it renamed through the next fold" do
          VoidHealingRename.migrate!(@char)
          Pf2e::Ledger.invalidate!(Character[@char.id])
          Pf2e::Ledger.materialize!(Character[@char.id])

          expect(specials(@char)).to include 'Void Healing'
          expect(specials(@char)).to_not include 'Negative Healing'
          expect(Pf2e::Ledger.explain_for(Character[@char.id], :kind => 'add_special', :key => 'Negative Healing')).to eq []
        end

        it "should keep the source and level the grant had" do
          VoidHealingRename.migrate!(@char)
          grant = Pf2e::Ledger.explain_for(Character[@char.id], :kind => 'add_special', :key => 'Void Healing').first

          expect(grant.slice('source_type', 'source_ref', 'effective_level'))
            .to eq('source_type' => 'chargen', 'source_ref' => 'old Dar', 'effective_level' => 1)
        end

        it "should give them void healing" do
          VoidHealingRename.migrate!(@char)

          expect(Effects.facts(Character[@char.id])).to include Effects::VOID_HEALING
        end

        it "should change nothing the second time" do
          VoidHealingRename.migrate!(@char)

          expect(VoidHealingRename.migrate!(Character[@char.id])).to eq 0
        end

        it "should report each character it changed from migrate_all!" do
          result = VoidHealingRename.migrate_all!(:characters => [ Character[@char.id] ])

          expect(result['changed']).to eq(@char.name => 1)
          expect(result['refused']).to eq({})
        end
      end

      it "should rename the special on a character still in chargen" do
        draft = built
        draft.update(:pf2_special => specials(draft).map { |one| one == 'Void Healing' ? 'Negative Healing' : one })

        VoidHealingRename.migrate!(Character[draft.id])

        expect(specials(draft)).to include 'Void Healing'
        expect(specials(draft)).to_not include 'Negative Healing'
      end

      it "should leave a character with another heritage alone" do
        expect(VoidHealingRename.migrate!(approved(built('Skilled')))).to eq 0
      end
    end
  end
end
