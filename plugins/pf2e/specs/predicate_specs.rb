require "plugin_test_loader"
require "json"

module AresMUSH
  module Pf2e

    # "Only in these circumstances" - Foundry's predicate language, which we read rather than invent.
    #
    # Most item bonuses are conditional, and treating a conditional bonus as unconditional makes the
    # item strictly better than the rules allow. Our own hand-written item bonuses had ten of those:
    # Skeleton Key (Greater) gave its +2 to Thievery generally rather than to picking a lock.
    describe Predicate do

      describe "atoms" do
        it "should hold when the options carry it" do
          expect(Predicate.test([ 'action:pick-a-lock' ], [ 'action:pick-a-lock' ])).to be true
        end

        it "should not hold when they do not" do
          expect(Predicate.test([ 'action:pick-a-lock' ], [ 'action:swim' ])).to be false
        end

        it "should require every statement, not merely one" do
          expect(Predicate.test([ 'a', 'b' ], [ 'a' ])).to be false
          expect(Predicate.test([ 'a', 'b' ], [ 'a', 'b' ])).to be true
        end

        # An unconditional modifier and a conditional one are the same code path, which is what a
        # predicate that holds vacuously buys.
        it "should hold when there is no predicate at all" do
          expect(Predicate.test([], [])).to be true
          expect(Predicate.test(nil, [])).to be true
        end
      end

      describe "compounds" do
        it "should read or" do
          expect(Predicate.test([ { 'or' => [ 'a', 'b' ] } ], [ 'b' ])).to be true
          expect(Predicate.test([ { 'or' => [ 'a', 'b' ] } ], [ 'c' ])).to be false
        end

        it "should read and" do
          expect(Predicate.test([ { 'and' => [ 'a', 'b' ] } ], [ 'a', 'b' ])).to be true
          expect(Predicate.test([ { 'and' => [ 'a', 'b' ] } ], [ 'a' ])).to be false
        end

        # `not` takes one statement rather than a list, which is the one irregularity in the language.
        it "should read not" do
          expect(Predicate.test([ { 'not' => 'a' } ], [ 'b' ])).to be true
          expect(Predicate.test([ { 'not' => 'a' } ], [ 'a' ])).to be false
        end

        it "should read nor" do
          expect(Predicate.test([ { 'nor' => [ 'a', 'b' ] } ], [ 'c' ])).to be true
          expect(Predicate.test([ { 'nor' => [ 'a', 'b' ] } ], [ 'b' ])).to be false
        end

        it "should read nand" do
          expect(Predicate.test([ { 'nand' => [ 'a', 'b' ] } ], [ 'a' ])).to be true
          expect(Predicate.test([ { 'nand' => [ 'a', 'b' ] } ], [ 'a', 'b' ])).to be false
        end

        it "should read xor as exactly one" do
          expect(Predicate.test([ { 'xor' => [ 'a', 'b' ] } ], [ 'a' ])).to be true
          expect(Predicate.test([ { 'xor' => [ 'a', 'b' ] } ], [ 'a', 'b' ])).to be false
          expect(Predicate.test([ { 'xor' => [ 'a', 'b' ] } ], [ 'c' ])).to be false
        end

        it "should read iff as all or none" do
          expect(Predicate.test([ { 'iff' => [ 'a', 'b' ] } ], [ 'a', 'b' ])).to be true
          expect(Predicate.test([ { 'iff' => [ 'a', 'b' ] } ], [])).to be true
          expect(Predicate.test([ { 'iff' => [ 'a', 'b' ] } ], [ 'a' ])).to be false
        end

        # Material implication: false only when the antecedent holds and the consequent does not.
        it "should read if and then" do
          conditional = [ { 'if' => 'a', 'then' => 'b' } ]

          expect(Predicate.test(conditional, [ 'a', 'b' ])).to be true
          expect(Predicate.test(conditional, [ 'c' ])).to be true
          expect(Predicate.test(conditional, [ 'a' ])).to be false
        end

        it "should nest" do
          nested = [ { 'or' => [ 'a', { 'and' => [ 'b', { 'not' => 'c' } ] } ] } ]

          expect(Predicate.test(nested, [ 'b' ])).to be true
          expect(Predicate.test(nested, [ 'b', 'c' ])).to be false
          expect(Predicate.test(nested, [ 'a', 'c' ])).to be true
        end
      end

      # A comparison's operand may be a number or a prefix the options carry a number under, which is
      # how `{ gte: [ 'self:level', 5 ] }` reads a character's level out of `self:level:7`.
      describe "comparisons" do
        it "should compare a prefix against a number" do
          expect(Predicate.test([ { 'gte' => [ 'self:level', 5 ] } ], [ 'self:level:7' ])).to be true
          expect(Predicate.test([ { 'gte' => [ 'self:level', 5 ] } ], [ 'self:level:3' ])).to be false
        end

        it "should read every comparison the data uses" do
          options = [ 'self:level:5' ]

          expect(Predicate.test([ { 'gt' => [ 'self:level', 4 ] } ], options)).to be true
          expect(Predicate.test([ { 'gt' => [ 'self:level', 5 ] } ], options)).to be false
          expect(Predicate.test([ { 'lt' => [ 'self:level', 6 ] } ], options)).to be true
          expect(Predicate.test([ { 'lte' => [ 'self:level', 5 ] } ], options)).to be true
        end

        # A prefix the options say nothing about has no values, and a comparison over no values is
        # false - so an unknown fact refuses the bonus rather than granting it.
        it "should not hold when the options say nothing about the prefix" do
          expect(Predicate.test([ { 'gte' => [ 'self:level', 1 ] } ], [ 'something:else' ])).to be false
        end

        it "should ignore an option whose value is not a number" do
          expect(Predicate.test([ { 'gte' => [ 'self:level', 1 ] } ], [ 'self:level:many' ])).to be false
        end

        it "should compare two prefixes" do
          expect(Predicate.test([ { 'gte' => [ 'self:level', 'item:level' ] } ],
                                [ 'self:level:9', 'item:level:4' ])).to be true
        end

        # eq is not arithmetic: a string right operand is compared literally, and anything else is a
        # lookup of `left:right` in the options.
        it "should read eq against a literal string" do
          expect(Predicate.test([ { 'eq' => [ 'fire', 'fire' ] } ], [])).to be true
          expect(Predicate.test([ { 'eq' => [ 'fire', 'cold' ] } ], [])).to be false
        end

        it "should read eq against a number as a lookup" do
          expect(Predicate.test([ { 'eq' => [ 'self:level', 5 ] } ], [ 'self:level:5' ])).to be true
          expect(Predicate.test([ { 'eq' => [ 'self:level', 5 ] } ], [ 'self:level:4' ])).to be false
        end
      end

      # A malformed predicate is refused. The alternative is a circumstance nobody checked reading as
      # met, which is the failure this whole module exists to prevent.
      describe "something malformed" do
        it "should refuse it" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))

          expect(Predicate.test([ { 'perhaps' => [ 'a' ] } ], [ 'a' ])).to be false
          expect(Predicate.test([ 42 ], [])).to be false
          expect(Predicate.test([ '' ], [])).to be false
        end

        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/malformed/)

          Predicate.test([ { 'perhaps' => [ 'a' ] } ], [ 'a' ])
        end

        it "should refuse a comparison with the wrong number of operands" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))

          expect(Predicate.test([ { 'gte' => [ 'self:level' ] } ], [ 'self:level:9' ])).to be false
        end
      end

      # The point of checking the corpus in: a structure we have read wrongly fails here, loudly,
      # rather than handing a player a bonus they have not earned.
      describe "every predicate Foundry ships" do
        def corpus
          path = File.join(File.dirname(__FILE__), 'support', 'foundry_predicate_corpus.txt')

          File.readlines(path)
              .reject { |line| line.start_with?('#') || line.strip.empty? }
              .map { |line| JSON.parse(line.split("\t", 2).last.to_s.strip) }
        end

        it "should have a corpus to check against" do
          expect(corpus.size).to be > 7000
        end

        it "should find every one of them structurally valid" do
          failed = corpus.reject { |predicate| Predicate.valid?(predicate) }

          expect(failed.first(5)).to eq []
          expect(failed).to eq []
        end

        # Testing one against no options at all must answer true or false and never raise: a sheet
        # render asks this of every modifier a character carries.
        it "should test every one of them without raising" do
          expect { corpus.each { |predicate| Predicate.test(predicate, []) } }.to_not raise_error
        end
      end
    end
  end
end
