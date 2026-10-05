require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Focus spells ride the level ladder like spells known, so a rollback takes back the ones a
    # level granted and a redo gives them back. A focus spell the ledger never recorded is left
    # alone: the materialiser manages what it has history for.
    describe "focus spells in the ledger" do

      def grant(seq, payload, level: 2, reverted: nil)
        { 'seq' => seq, 'txn' => "t#{seq}", 'kind' => 'focus_spell', 'payload' => payload,
          'source_type' => 'level_up', 'effective_level' => level, 'reverted_by' => reverted }
      end

      def record(spell, type: 'domain', kind: 'spell', granted_by: 'Domain Family')
        { 'type' => type, 'kind' => kind, 'spell' => spell, 'granted_by' => granted_by }
      end

      describe :fold do
        it "should hold each focus spell granted" do
          sheet = Ledger.fold([ grant(1, record('Soothing Words')), grant(2, record('Unity'), level: 8) ], at_level: 8)

          expect(sheet['focus']).to eq [ record('Soothing Words'), record('Unity') ]
        end

        it "should leave out a reverted grant, and one above the level" do
          grants = [ grant(1, record('Soothing Words')), grant(2, record('Unity'), level: 8),
                     grant(3, record("Healer's Blessing"), reverted: 'rollback') ]

          expect(Ledger.fold(grants, at_level: 4)['focus']).to eq [ record('Soothing Words') ]
        end
      end

      describe "planning a materialise" do
        def ops(sheet_focus, held, recorded)
          sheet = Ledger.empty_sheet(4).merge('focus' => sheet_focus)

          Ledger.plan(sheet, { 'focus' => held, 'focus_recorded' => recorded }).select { |op| op['op'] == 'set_focus' }
        end

        it "should put back a recorded spell the character lacks" do
          planned = ops([ record('Unity') ], [], [ record('Unity') ])

          expect(planned).to eq [ { 'op' => 'set_focus', 'add' => [ record('Unity') ], 'remove' => [] } ]
        end

        it "should take away a spell whose grant was reverted" do
          planned = ops([], [ record('Unity') ], [ record('Unity') ])

          expect(planned).to eq [ { 'op' => 'set_focus', 'add' => [], 'remove' => [ record('Unity') ] } ]
        end

        it "should leave alone a spell the ledger never recorded" do
          expect(ops([], [ record('Unity') ], [])).to eq []
        end

        it "should plan nothing when the character matches the fold" do
          expect(ops([ record('Unity') ], [ record('Unity') ], [ record('Unity') ])).to eq []
        end

        it "should plan nothing while a draft is open" do
          sheet = Ledger.empty_sheet(4).merge('focus' => [ record('Unity') ])

          expect(Ledger.plan(sheet, { 'focus' => [], 'focus_recorded' => [ record('Unity') ] }, :draft => true)).to eq []
        end
      end

      # What a level-up commit records: the difference between the character and the fold.
      describe :sync_plan do
        it "should record a focus spell the level added" do
          sheet = Ledger.empty_sheet(1).merge('focus' => [ record('Soothing Words') ])
          plan = Ledger.sync_plan(sheet, 'focus' => [ record('Soothing Words'), record('Unity') ])

          expect(plan['grants']).to eq [ { 'kind' => 'focus_spell', 'payload' => record('Unity') } ]
          expect(plan['revocations']).to eq []
        end

        it "should revoke one the level took away" do
          sheet = Ledger.empty_sheet(1).merge('focus' => [ record('Soothing Words') ])
          plan = Ledger.sync_plan(sheet, 'focus' => [])

          expect(plan['revocations']).to eq [ { 'kind' => 'focus_spell', 'match' => record('Soothing Words'), 'limit' => 1 } ]
        end
      end
    end
  end
end
