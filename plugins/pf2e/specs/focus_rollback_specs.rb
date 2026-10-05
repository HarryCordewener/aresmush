require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Focus spells on the level ladder: a rollback takes back the ones a level granted, a redo gives
    # them back, and what staff grant is staff history that a rollback leaves alone.
    describe "focus spells and rollback", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Focus#{rand(1000000)}")
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        Roles.add_role(@staff, 'admin')
        @client = AutoBuilder::CaptureClient.new

        # A Cloistered Cleric of Althea, whose Domain Initiate gives her Soothing Words.
        AutoBuilder.new(@char).build_level_one('Cleric')
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Ledger.commit_chargen!(@char)
        @char = Character[@char.id]
      end

      after(:each) do
        @char.delete if @char
        @staff.delete if @staff
      end

      def spells
        Pf2emagic::Entries.focus_spells(Character[@char.id].magic, 'domain').sort
      end

      def recorded
        Character[@char.id].grants.to_a.select { |g| g.kind == 'focus_spell' && g.reverted_by.blank? }
      end

      # What a level's feat does to the sheet, then the commit that ends the level.
      def level_up_granting(spell)
        char = Character[@char.id]
        Pf2emagic::Entries.grant_focus!(char, 'domain', [ spell ], :kind => 'spell', :granted_by => 'Domain Family', :granted_at => 2)
        char.update(:pf2_level => 2)
        Ledger.commit_level_up!(Character[@char.id], 2, :cost => 0)
        @char = Character[@char.id]
      end

      def staff_set(value)
        cmd = Command.new("admin/set #{@char.name}/focus=#{value}")
        PF2AdminSetCmd.new(@client, cmd, Character[@staff.id]).on_command
        @char = Character[@char.id]
      end

      it "should record the focus spells chargen gave" do
        expect(recorded.map { |g| g.payload['spell'] }).to eq [ 'Soothing Words' ]
      end

      it "should record the focus spell a level added, at that level" do
        level_up_granting('Unity')

        unity = recorded.find { |g| g.payload['spell'] == 'Unity' }

        expect(unity.effective_level).to eq 2
        expect(unity.source_type).to eq 'level_up'
      end

      it "should take a level's focus spell back on a rollback, and give it back on a redo" do
        level_up_granting('Unity')

        expect(Pf2e.rollback_to_level(Character[@char.id], 2)).to be_nil
        expect(spells).to eq [ 'Soothing Words' ]
        expect(Pf2emagic.focus_pool_max(Character[@char.id].magic)).to eq 1

        expect(Pf2e.redo_rollback(Character[@char.id])).to be_nil
        expect(spells).to eq [ 'Soothing Words', 'Unity' ]
      end

      it "should keep a focus spell staff granted through a rollback" do
        level_up_granting('Unity')
        staff_set('add Cleric spell Rebuke Death')

        Pf2e.rollback_to_level(Character[@char.id], 2)

        expect(spells).to eq [ 'Rebuke Death', 'Soothing Words' ]
      end

      it "should keep a focus spell staff took away gone through the next fold" do
        staff_set('delete Cleric spell Soothing Words')

        Ledger.invalidate!(@char)
        Ledger.materialize!(Character[@char.id])

        expect(spells).to eq []
      end

      it "should leave alone a focus spell the ledger never recorded" do
        Pf2emagic::Entries.grant_focus!(Character[@char.id], 'domain', [ 'Unity' ], :kind => 'spell', :granted_by => 'Old')

        Ledger.invalidate!(@char)
        Ledger.materialize!(Character[@char.id])

        expect(spells).to eq [ 'Soothing Words', 'Unity' ]
      end

      # The one-off migration, run through tinker over every character.
      describe :seed_focus! do
        before(:each) do
          # A character from before focus spells were recorded, holding a composition cantrip filed
          # among the spells, with no points left.
          recorded.each(&:delete)
          Ledger.invalidate!(@char)
          Pf2emagic::Entries.grant_focus!(Character[@char.id], 'composition', [ 'Rallying Anthem' ], :kind => 'spell', :granted_by => 'Bard')
          Character[@char.id].magic.update(:focus_pool => { 'max' => 0, 'current' => 0 })
        end

        it "should record the focus spells held as an import" do
          Ledger.seed_focus!(Character[@char.id])

          expect(recorded.map { |g| g.payload['spell'] }.sort).to eq [ 'Rallying Anthem', 'Soothing Words' ]
          expect(recorded.map(&:source_type).uniq).to eq [ 'imported' ]
        end

        it "should refile a composition cantrip as a cantrip" do
          Ledger.seed_focus!(Character[@char.id])
          magic = Character[@char.id].magic

          expect(Pf2emagic::Entries.focus_cantrips(magic, 'composition')).to eq [ 'Rallying Anthem' ]
          expect(Pf2emagic::Entries.focus_spells(magic, 'composition')).to eq []
        end

        it "should fill the pool" do
          Ledger.seed_focus!(Character[@char.id])

          expect(Character[@char.id].magic.focus_pool['current']).to eq 1
        end

        it "should record nothing the second time" do
          Ledger.seed_focus!(Character[@char.id])

          expect { Ledger.seed_focus!(Character[@char.id]) }.not_to change { recorded.size }
        end

        # Chargen's commit records a draft's focus spells, so the migration only tidies them.
        it "should refile a draft's cantrip and fill its pool without recording anything" do
          draft = Character.create(:name => "Draft#{rand(1000000)}")
          AutoBuilder.new(draft).build_level_one('Cleric')
          Pf2emagic::Entries.grant_focus!(Character[draft.id], 'composition', [ 'Rallying Anthem' ], :kind => 'spell', :granted_by => 'Bard')
          Character[draft.id].magic.update(:focus_pool => { 'current' => 0 })

          expect(Ledger.seed_focus!(Character[draft.id])).to eq 0

          magic = Character[draft.id].magic
          expect(Pf2emagic::Entries.focus_cantrips(magic, 'composition')).to eq [ 'Rallying Anthem' ]
          expect(magic.focus_pool['current']).to eq 1
          expect(Character[draft.id].grants.count).to eq 0

          draft.delete
        end
      end
    end
  end
end
