require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Foundry's formula language, which we read rather than invent.
    #
    # An effect says what it is worth as an expression - `@actor.level`, `max(1,floor(@actor.level/2))`
    # - and this reads it. Adopting their grammar rather than inventing a shape means a converted feat
    # carries its formula across as data; inventing one means hand-translating two thousand of them,
    # where a wrong sign or a missing floor is a number that looks right and is not.
    #
    # The grammar is closed. Four operators, twelve functions, dotted references and interpolations.
    # No property access on arbitrary objects and no function this does not name, so there is nothing
    # to sandbox.
    #
    # Dentaku is taught that grammar rather than handed a rewritten copy of it, so a formula reaches
    # the parser as the data wrote it and an identifier is the verbatim path. The specs below hold that
    # to the constructs which would break a parser that only reads arithmetic: mixed case, hyphens in a
    # path segment, and a brace where a path segment belongs.
    describe Formula do

      def ctx(paths = {})
        { 'actor' => { 'level' => 5, 'abilities' => { 'con' => { 'mod' => 3 } } } }.merge(paths)
      end

      describe "arithmetic" do
        it "should read a number" do
          expect(Formula.value('7', ctx)).to eq 7
        end

        it "should add and subtract left to right" do
          expect(Formula.value('10 - 3 + 1', ctx)).to eq 8
        end

        it "should multiply before adding" do
          expect(Formula.value('2 + 3 * 4', ctx)).to eq 14
        end

        it "should divide before subtracting" do
          expect(Formula.value('10 - 6 / 2', ctx)).to eq 7
        end

        it "should respect brackets" do
          expect(Formula.value('(2 + 3) * 4', ctx)).to eq 20
        end

        it "should read a leading minus" do
          expect(Formula.value('-4', ctx)).to eq(-4)
        end

        it "should divide without rounding, so an explicit floor is what rounds" do
          expect(Formula.value('7 / 2', ctx)).to eq 3.5
        end

        # A zero divisor only arises from a reference that resolved to nothing, which `unresolved`
        # reports. Raising would take a sheet render down over one bad path.
        it "should yield nothing rather than raise when the divisor resolved to nothing" do
          expect(Formula.value('@actor.level / @actor.nonsense', ctx)).to eq 0
        end

        it "should still name the path that made it zero" do
          expect(Formula.unresolved('@actor.level / @actor.nonsense', ctx)).to eq [ 'actor.nonsense' ]
        end
      end

      describe "references" do
        it "should read a dotted path off the context" do
          expect(Formula.value('@actor.level', ctx)).to eq 5
        end

        it "should read a deep path" do
          expect(Formula.value('@actor.abilities.con.mod', ctx)).to eq 3
        end

        it "should read a choice answered as a number in text" do
          chosen = { 'item' => { 'flags' => { 'system' => { 'rulesSelections' => { 'aidBonus' => '-1' } } } } }

          expect(Formula.value('@item.flags.system.rulesSelections.aidBonus', chosen)).to eq(-1)
        end

        it "should do arithmetic on a reference" do
          expect(Formula.value('18 + @actor.level', ctx)).to eq 23
        end

        it "should negate a reference" do
          expect(Formula.value('-@actor.level', ctx)).to eq(-5)
        end

        # A path segment may hold hyphens: Foundry has
        # @actor.system.proficiencies.attacks.advanced-firearms-crossbows.rank.
        it "should read a path segment containing hyphens" do
          context = { 'actor' => { 'attacks' => { 'advanced-firearms-crossbows' => 2 } } }

          expect(Formula.value('@actor.attacks.advanced-firearms-crossbows', context)).to eq 2
        end

        # A reference that resolves to nothing is zero, which is what Foundry does - but it is also
        # how a mistyped path hides, so it is reported.
        it "should treat an unknown path as zero" do
          expect(Formula.value('@actor.nonsense', ctx)).to eq 0
        end

        it "should say which paths it could not resolve" do
          expect(Formula.unresolved('@actor.nonsense + @actor.level', ctx)).to eq [ 'actor.nonsense' ]
        end
      end

      describe "reading the data's own spelling" do
        it "should keep a reference's case, so two paths differing by case are two paths" do
          context = { 'actor' => { 'flags' => { 'sneakAttackDamage' => 7, 'sneakattackdamage' => 2 } } }

          expect(Formula.value('@actor.flags.sneakAttackDamage', context)).to eq 7
          expect(Formula.value('@actor.flags.sneakattackdamage', context)).to eq 2
        end

        # A hyphen is subtraction to any arithmetic parser, and Foundry has path segments holding one.
        it "should read a hyphenated segment as one path rather than a subtraction" do
          context = { 'actor' => { 'proficiencies' => { 'advanced-firearms-crossbows' => 4 } } }

          expect(Formula.value('@actor.proficiencies.advanced-firearms-crossbows', context)).to eq 4
        end

        it "should not edit the formula it was given" do
          formula = '@actor.flags.sneakAttackDamage'.freeze

          expect { Formula.value(formula, {}) }.to_not raise_error
        end

        # `{source|path}` where a value belongs: the value at that path, from somewhere other than the
        # actor.
        it "should read an interpolation standing on its own as a value" do
          context = { 'item' => { 'flags' => { 'pf2e' => { 'rulesSelections' =>
                      { 'pistolerosChallengeSkill' => 5 } } } } }

          expect(Formula.value('max({item|flags.pf2e.rulesSelections.pistolerosChallengeSkill},2)',
                               context)).to eq 5
        end

        # The same braces where a path segment belongs: the inner value names the segment, so it
        # resolves in two stages.
        it "should resolve an interpolation inside a path into a segment of that path" do
          context = { 'item' => { 'flags' => { 'pf2e' => { 'rulesSelections' => { 'skill' => 'stealth' } } } },
                      'actor' => { 'skills' => { 'stealth' => { 'rank' => 3 } } } }

          expect(Formula.value('@actor.skills.{item|flags.pf2e.rulesSelections.skill}.rank', context))
            .to eq 3
        end

        it "should name the interpolation it could not resolve" do
          context = { 'actor' => { 'skills' => { 'stealth' => { 'rank' => 3 } } } }

          expect(Formula.unresolved('@actor.skills.{item|flags.pf2e.rulesSelections.skill}.rank', context))
            .to include 'item.flags.pf2e.rulesSelections.skill'
        end
      end

      # Dentaku's scanner registry is global to the gem, and the `math` command shares it. The two
      # Foundry scanners are gated on a flag this reader raises, so `math` keeps the grammar it had.
      describe "the math command, which shares the gem" do
        before(:each) { Formula.value('1', {}) }

        it "should still read the arithmetic a player types" do
          expect(Dentaku('(2 + 3) * 4')).to eq 20
          expect(Dentaku('2 ^ 8')).to eq 256
          expect(Dentaku('max(3, 7)')).to eq 7
          expect(Dentaku('10 - 6 / 2')).to eq 7
        end

        # The interpolation scanner would take this brace if it were unconditional.
        it "should keep dentaku's own array literal" do
          expect(Dentaku('{1,2}')).to eq [ 1, 2 ]
        end

        it "should keep a hyphen as subtraction" do
          expect(Dentaku('a-b', 'a' => 5, 'b' => 2)).to eq 3
        end

        it "should keep folding identifier case" do
          expect(Dentaku('Foo', 'foo' => 3)).to eq 3
        end

        it "should not read a foundry reference" do
          expect { Dentaku!('@actor.level') }.to raise_error(Dentaku::TokenizerError)
        end
      end

      describe "isolation between the two grammars" do
        it "should leave the flag down once a formula has been read" do
          Formula.value('@actor.level', ctx)

          expect(Thread.current[Formula::GRAMMAR]).to be_nil
        end

        it "should leave it down when a formula is refused" do
          expect { Formula.value('1 ; 2', ctx) }.to raise_error(Formula::Invalid)
          expect(Thread.current[Formula::GRAMMAR]).to be_nil
        end
      end

      describe "functions" do
        it "should floor" do
          expect(Formula.value('floor(@actor.level/2)', ctx)).to eq 2
        end

        it "should ceil" do
          expect(Formula.value('ceil(@actor.level/2)', ctx)).to eq 3
        end

        it "should round" do
          expect(Formula.value('round(5/2)', ctx)).to eq 3
        end

        it "should take the larger of two" do
          expect(Formula.value('max(1,floor(@actor.level/2))', ctx)).to eq 2
        end

        it "should take the smaller of two" do
          expect(Formula.value('min(3,@actor.level)', ctx)).to eq 3
        end

        it "should take max of more than two, which is variadic in the data" do
          expect(Formula.value('max(1,2,9,3)', ctx)).to eq 9
        end

        it "should clamp between bounds" do
          expect(Formula.value('clamp(@actor.level,1,4)', ctx)).to eq 4
        end

        it "should choose with ternary on a true test" do
          expect(Formula.value('ternary(gte(@actor.level,5),10,20)', ctx)).to eq 10
        end

        it "should choose with ternary on a false test" do
          expect(Formula.value('ternary(gte(@actor.level,17),3,2)', ctx)).to eq 2
        end

        it "should compare with each comparison the data uses" do
          expect(Formula.value('gte(2,2)', ctx)).to eq 1
          expect(Formula.value('gt(2,2)', ctx)).to eq 0
          expect(Formula.value('lte(2,2)', ctx)).to eq 1
          expect(Formula.value('lt(1,2)', ctx)).to eq 1
          expect(Formula.value('eq(2,2)', ctx)).to eq 1
          expect(Formula.value('ne(2,2)', ctx)).to eq 0
        end

        # One shipped formula says `clamped(...)`, which is a typo for clamp. Accepting it costs
        # nothing and refusing it would fail an import over someone else's slip.
        it "should accept the data's one misspelling of clamp" do
          expect(Formula.value('clamped(9,1,4)', ctx)).to eq 4
        end

        it "should say whether a value falls between two others" do
          expect(Formula.value('btwn(@actor.level,4,6)', ctx)).to eq 1
          expect(Formula.value('btwn(@actor.level,6,8)', ctx)).to eq 0
        end

        # `when` answers nothing when its test fails and `match` takes the first answer that is not
        # nothing, which together are how the data writes a value that steps up with level.
        describe "a value that steps with level" do
          def steps
            'match(when(lte(@actor.level,10),2), when(btwn(@actor.level,11,14),6), ' \
              'when(gte(@actor.level,15),8))'
          end

          it "should take the step the level falls in" do
            expect(Formula.value(steps, 'actor' => { 'level' => 3 })).to eq 2
            expect(Formula.value(steps, 'actor' => { 'level' => 12 })).to eq 6
            expect(Formula.value(steps, 'actor' => { 'level' => 20 })).to eq 8
          end

          it "should take the first step that matches, not the last" do
            overlapping = 'match(when(gte(@actor.level,1),1), when(gte(@actor.level,2),2))'

            expect(Formula.value(overlapping, 'actor' => { 'level' => 9 })).to eq 1
          end

          # Their `match` answers zero when nothing matched, rather than failing.
          it "should answer nothing as zero when no step matches" do
            expect(Formula.value('match(when(gte(@actor.level,99),5))', ctx)).to eq 0
          end

          # `when` is one of Dentaku's own `case ... when ... end` keywords, so the word would never
          # reach the function scanner without being claimed as a function first.
          it "should read when as a function rather than as a case keyword" do
            expect(Formula.parses?('when(gte(@actor.level,1),4)')).to be true
          end
        end
      end

      describe "refusals" do
        it "should refuse a function it does not know rather than guess" do
          expect { Formula.value('system("rm -rf /")', ctx) }.to raise_error(Formula::Invalid, /system/)
        end

        it "should refuse an unbalanced bracket" do
          expect { Formula.value('max(1,2', ctx) }.to raise_error(Formula::Invalid)
        end

        it "should refuse a character outside the grammar" do
          expect { Formula.value('1 ; 2', ctx) }.to raise_error(Formula::Invalid)
        end

        it "should refuse a wrong arity on a fixed-arity function" do
          expect { Formula.value('floor(1,2)', ctx) }.to raise_error(Formula::Invalid, /floor/)
        end

        it "should refuse rather than evaluate ruby" do
          expect { Formula.value('`ls`', ctx) }.to raise_error(Formula::Invalid)
        end
      end

      # The point of checking the corpus in: a construct we have read wrongly fails here, loudly,
      # rather than resolving to zero in front of a player.
      describe "every formula Foundry ships" do
        def corpus
          path = File.join(File.dirname(__FILE__), 'support', 'foundry_formula_corpus.txt')

          File.readlines(path)
              .reject { |line| line.start_with?('#') || line.strip.empty? }
              .map { |line| line.split("\t", 2).last.to_s.strip }
              .reject(&:empty?)
        end

        it "should have a corpus to check against" do
          expect(corpus.size).to be > 750
        end

        it "should parse every one of them" do
          failed = corpus.reject { |formula| Formula.parses?(formula) }

          expect(failed).to eq []
        end
      end
    end
  end
end
