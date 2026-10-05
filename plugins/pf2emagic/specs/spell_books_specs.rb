require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Learn a Spell, the books Esoteric Polymath and Arcane Evolution keep, and the pick each makes
    # from its book during daily preparations. Player Core p. 230 (Learn a Spell), p. 101 (Esoteric
    # Polymath), Player Core 2 (Arcane Evolution), p. 258 (Magical Shorthand).
    describe "spell books" do

      describe "a degree of success" do
        it "should read a total against a DC" do
          expect(Pf2e.degree_index(10, 25, 15)).to eq 3
          expect(Pf2e.degree_index(10, 15, 15)).to eq 2
          expect(Pf2e.degree_index(10, 14, 15)).to eq 1
          expect(Pf2e.degree_index(10, 5, 15)).to eq 0
        end

        it "should move a natural 20 up a degree and a natural 1 down" do
          expect(Pf2e.degree_index(20, 14, 15)).to eq 2
          expect(Pf2e.degree_index(1, 15, 15)).to eq 1
          expect(Pf2e.degree_index(20, 30, 15)).to eq 3
          expect(Pf2e.degree_index(1, 5, 15)).to eq 0
        end
      end

      describe "the books a character keeps" do
        def feats
          {
            'Esoteric Polymath' => { 'spell_book' => { 'name' => 'Book of Occult Spells', 'tradition' => 'occult',
                                                       'supplements' => 'Bard', 'keeps_repertoire' => true,
                                                       'switch' => 'esotericpolymath' } },
            'Arcane Evolution' => { 'spell_book' => { 'name' => 'Arcane Evolution List', 'tradition' => 'arcane',
                                                      'supplements' => 'Sorcerer', 'switch' => 'arcaneevolution' } },
            'Fleet' => {}
          }
        end

        it "should find a book on each feat held that keeps one" do
          books = SpellBooks.books_from([ 'ESOTERIC POLYMATH', 'FLEET' ], feats)

          expect(books.map { |b| b['name'] }).to eq [ 'Book of Occult Spells' ]
          expect(books.first['feat']).to eq 'Esoteric Polymath'
        end

        # A player prepares from a book by the feat's name, so the switch is the book's own.
        it "should find a held book by its switch, whatever its case" do
          books = SpellBooks.books_from([ 'ESOTERIC POLYMATH', 'ARCANE EVOLUTION' ], feats)

          expect(SpellBooks.for_switch(books, 'ArcaneEvolution')['name']).to eq 'Arcane Evolution List'
          expect(SpellBooks.for_switch(books, 'evo')).to be_nil
        end

        # Shown when the feat is gained, built from the same data the commands read.
        it "should tell the player how to learn into the book and prepare from it" do
          book = SpellBooks.books_from([ 'ESOTERIC POLYMATH' ], feats).first
          text = SpellBooks.instructions(book)

          expect(text).to include('Book of Occult Spells', 'spell/learn', 'prepare/esotericpolymath', 'help prepare')
        end

        # The book is the spells learned into it and the class's repertoire.
        it "should hold what was learned into it and the repertoire it supplements" do
          held = SpellBooks.contents({ '1' => [ 'Sleep' ] }, { '1' => [ 'Fear' ], '2' => [ 'Blur' ] })

          expect(held).to eq('1' => [ 'Sleep', 'Fear' ], '2' => [ 'Blur' ])
        end
      end

      describe "Learn a Spell" do
        def table
          { 'cantrip' => [ 2, 15 ], '1' => [ 2, 15 ], '3' => [ 16, 20 ], '10' => [ 7000, 41 ] }
        end

        it "should read the price in copper and the DC for a rank" do
          expect(LearnSpell.terms('3', table)).to eq('price' => 1600, 'dc' => 20)
          expect(LearnSpell.terms('cantrip', table)).to eq('price' => 200, 'dc' => 15)
        end

        it "should pay for and teach the spell by degree" do
          expect(LearnSpell.outcome(3)).to eq('learned' => true, 'paid' => 'half')
          expect(LearnSpell.outcome(2)).to eq('learned' => true, 'paid' => 'full')
          expect(LearnSpell.outcome(1)).to eq('learned' => false, 'paid' => 'none')
          expect(LearnSpell.outcome(0)).to eq('learned' => false, 'paid' => 'half')
        end

        it "should make a success a critical success with Magical Shorthand" do
          expect(LearnSpell.outcome(2, :upgrade_success => true)).to eq('learned' => true, 'paid' => 'half')
          expect(LearnSpell.outcome(1, :upgrade_success => true)).to eq('learned' => false, 'paid' => 'none')
        end

        # Spellbook Prodigy: "when you roll a critical failure on your check to Learn a Spell, you
        # get a failure instead."
        it "should make a critical failure a failure with Spellbook Prodigy" do
          expect(LearnSpell.outcome(0, :soften_critical_failure => true)).to eq('learned' => false, 'paid' => 'none')
          expect(LearnSpell.outcome(0)).to eq('learned' => false, 'paid' => 'half')
        end

        it "should charge what the outcome says" do
          expect(LearnSpell.charge(1600, 'full')).to eq 1600
          expect(LearnSpell.charge(1600, 'half')).to eq 800
          expect(LearnSpell.charge(1600, 'none')).to eq 0
        end

        describe "trying again after a failure" do
          def failed
            { 'level' => 5, 'at' => Time.utc(2026, 9, 1).to_i }
          end

          it "should wait for a level" do
            expect(LearnSpell.retry_blocked?(failed, :level => 5, :now => Time.utc(2026, 12, 1).to_i)).to be true
            expect(LearnSpell.retry_blocked?(failed, :level => 6, :now => Time.utc(2026, 9, 2).to_i)).to be false
          end

          it "should wait for a level or the days a feat names, whichever comes first" do
            expect(LearnSpell.retry_blocked?(failed, :level => 5, :now => Time.utc(2026, 9, 5).to_i, :retry_after_days => 7)).to be true
            expect(LearnSpell.retry_blocked?(failed, :level => 5, :now => Time.utc(2026, 9, 8).to_i, :retry_after_days => 7)).to be false
          end

          it "should not block a spell never failed" do
            expect(LearnSpell.retry_blocked?(nil, :level => 1, :now => 0)).to be false
          end
        end

        describe "whether the attempt may be made" do
          def ctx(overrides = {})
            {
              'target' => { 'name' => 'Book of Occult Spells', 'tradition' => 'occult' },
              'spell' => 'Sleep',
              'details' => { 'tradition' => [ 'arcane', 'occult' ], 'traits' => [ 'mental' ], 'base_level' => 1 },
              'known' => { '1' => [ 'Fear' ] },
              'blocked' => false,
              'money' => 1000,
              'price' => 200
            }.merge(overrides)
          end

          it "should allow a common spell of the book's tradition they can pay for" do
            expect(LearnSpell.check(ctx).ok?).to be true
          end

          it "should refuse a spell off the tradition's list" do
            expect(LearnSpell.check(ctx('details' => { 'tradition' => [ 'primal' ], 'traits' => [] })).code).to eq :wrong_tradition
          end

          # An uncommon spell needs access only the GM can give, so staff add it.
          it "should refuse an uncommon spell" do
            expect(LearnSpell.check(ctx('details' => { 'tradition' => [ 'occult' ], 'traits' => [ 'uncommon' ] })).code).to eq :not_common
          end

          it "should refuse a spell already in the book" do
            expect(LearnSpell.check(ctx('spell' => 'Fear')).code).to eq :already_known
          end

          it "should refuse a spell whose retry is not due" do
            expect(LearnSpell.check(ctx('blocked' => true)).code).to eq :retry_blocked
          end

          # The materials are needed to make the attempt at all.
          it "should refuse a character who cannot pay the full price" do
            expect(LearnSpell.check(ctx('money' => 199)).code).to eq :cannot_afford
          end
        end
      end

      describe "the daily pick" do
        def plan(spell, base, rank = nil, max_rank: 5)
          DailyPick.plan('spell' => spell, 'base' => base, 'rank' => rank,
                         'book' => { '1' => [ 'Fear', 'Sleep' ], '3' => [ 'Slow' ] },
                         'repertoire' => { '1' => [ 'Fear' ] }, 'max_rank' => max_rank)
        end

        it "should make a spell already in the repertoire a signature spell" do
          result = plan('Fear', 1)

          expect(result.state).to eq('as' => 'signature', 'spell' => 'Fear', 'rank' => '1')
        end

        it "should add a spell outside the repertoire at the rank asked for" do
          expect(plan('Slow', 3, '4').state).to eq('as' => 'repertoire', 'spell' => 'Slow', 'rank' => '4')
        end

        it "should add it at its own rank when none is asked for" do
          expect(plan('Sleep', 1).state['rank']).to eq '1'
        end

        it "should refuse a spell not in the book" do
          expect(plan('Blur', 2).code).to eq :not_in_book
        end

        it "should refuse a rank below the spell's own" do
          expect(plan('Slow', 3, '2').code).to eq :rank_too_low
        end

        it "should refuse a rank the character has no slots for" do
          expect(plan('Slow', 3, '6').code).to eq :rank_too_high
        end
      end

      # The pick shows wherever the class's spells are read, and is gone at the next preparations.
      describe "an entry with a daily pick" do
        def entry(pick)
          magic = {
            'tradition' => { 'Bard' => [ 'occult', 'trained' ] },
            'repertoire' => { 'Bard' => { '1' => [ 'Fear' ] } },
            'signature_spells' => { 'Bard' => { '1' => [ 'Fear' ] } },
            'daily_pick' => { 'Bard' => pick }
          }

          Entries.derive(magic, :caster_types => { 'Bard' => 'spontaneous' }).first
        end

        it "should add a spell picked into the repertoire" do
          known = entry('as' => 'repertoire', 'spell' => 'Slow', 'rank' => '4')['known']

          expect(known).to eq('1' => [ 'Fear' ], '4' => [ 'Slow' ])
        end

        it "should add a signature spell picked" do
          signature = entry('as' => 'signature', 'spell' => 'Sleep', 'rank' => '1')['signature']

          expect(signature).to eq('1' => [ 'Fear', 'Sleep' ])
        end
      end
    end
  end
end
