require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # How well a check went, as a value rather than a coloured string.
    #
    # The outcome used to be decided and formatted in one breath, which is fine for printing a roll and
    # no use to anything that has to change the outcome - and a hundred and fifty rule elements in
    # Foundry's data do exactly that.
    describe Degree do

      describe "the outcome of a roll" do
        it "should succeed on meeting the DC" do
          expect(Degree.of(20, 20)).to eq Degree::SUCCESS
        end

        it "should fail on falling short" do
          expect(Degree.of(19, 20)).to eq Degree::FAILURE
        end

        it "should be critical ten over" do
          expect(Degree.of(30, 20)).to eq Degree::CRITICAL_SUCCESS
        end

        it "should be a critical failure ten under" do
          expect(Degree.of(10, 20)).to eq Degree::CRITICAL_FAILURE
        end
      end

      # A natural twenty shifts the outcome one better rather than being a critical success outright,
      # which is why a twenty that still falls ten short is only a failure.
      describe "the die's own face" do
        it "should shift a success to a critical success on a twenty" do
          expect(Degree.of(20, 20, 20)).to eq Degree::CRITICAL_SUCCESS
        end

        it "should shift a critical failure only to a failure on a twenty" do
          expect(Degree.of(10, 20, 20)).to eq Degree::FAILURE
        end

        it "should shift a success down to a failure on a one" do
          expect(Degree.of(20, 20, 1)).to eq Degree::FAILURE
        end

        it "should leave a roll alone on any other face" do
          expect(Degree.of(20, 20, 11)).to eq Degree::SUCCESS
        end
      end

      describe "an adjustment" do
        it "should shift by a degree" do
          expect(Degree.adjusted(Degree::FAILURE, [ { 'failure' => 'one-degree-better' } ]))
            .to eq Degree::SUCCESS
        end

        it "should shift by two" do
          expect(Degree.adjusted(Degree::CRITICAL_FAILURE,
                                 [ { 'criticalFailure' => 'two-degrees-better' } ])).to eq Degree::SUCCESS
        end

        it "should set an outcome outright" do
          expect(Degree.adjusted(Degree::CRITICAL_FAILURE, [ { 'criticalFailure' => 'to-success' } ]))
            .to eq Degree::SUCCESS
        end

        it "should apply one written against every outcome" do
          expect(Degree.adjusted(Degree::FAILURE, [ { 'all' => 'one-degree-better' } ]))
            .to eq Degree::SUCCESS
        end

        it "should not apply to an outcome it does not name" do
          expect(Degree.adjusted(Degree::SUCCESS, [ { 'failure' => 'one-degree-better' } ]))
            .to eq Degree::SUCCESS
        end

        # Skipped rather than clamped, which matters because a later adjustment then gets its turn.
        it "should skip an improvement to a check that already went as well as it can" do
          expect(Degree.adjusted(Degree::CRITICAL_SUCCESS, [ { 'all' => 'one-degree-better' } ]))
            .to eq Degree::CRITICAL_SUCCESS
        end

        it "should skip a worsening of a check that already went as badly as it can" do
          expect(Degree.adjusted(Degree::CRITICAL_FAILURE, [ { 'all' => 'one-degree-worse' } ]))
            .to eq Degree::CRITICAL_FAILURE
        end

        it "should let a later adjustment apply when an earlier one was skipped" do
          adjustments = [ { 'all' => 'one-degree-better' }, { 'criticalSuccess' => 'to-failure' } ]

          expect(Degree.adjusted(Degree::CRITICAL_SUCCESS, adjustments)).to eq Degree::FAILURE
        end

        it "should take the first that matches rather than all of them" do
          adjustments = [ { 'failure' => 'one-degree-better' }, { 'failure' => 'to-critical-success' } ]

          expect(Degree.adjusted(Degree::FAILURE, adjustments)).to eq Degree::SUCCESS
        end

        it "should ignore an adjustment it does not know" do
          expect(Degree.adjusted(Degree::FAILURE, [ { 'failure' => 'somewhat-better' } ]))
            .to eq Degree::FAILURE
        end

        it "should read every adjustment their data uses" do
          Degree::ADJUSTMENTS.each_key do |named|
            expect(Degree.adjusted(Degree::FAILURE, [ { 'all' => named } ])).to be_between(0, 3), named
          end
        end
      end

      describe "naming one" do
        it "should give the name an adjustment is keyed by" do
          expect(Degree.name(Degree::CRITICAL_SUCCESS)).to eq 'criticalSuccess'
        end

        it "should give the slug a roll option is written with" do
          expect(Degree.slug(Degree::CRITICAL_FAILURE)).to eq 'critical-failure'
        end

        it "should say whether it went well" do
          expect(Degree.success?(Degree::SUCCESS)).to be true
          expect(Degree.success?(Degree::FAILURE)).to be false
        end
      end
    end
  end
end
