require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Learning a spell and preparing from a book, on a real character: the money, the ledger, the
    # retry rule, the daily pick and its end at the next preparations.
    describe "learning spells and preparing from a book", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Books#{rand(1000000)}")
      end

      after(:each) do
        live = Character[@char.id]

        live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
        live.skills.to_a.each(&:delete)
        live.magic.delete if live.magic
        live.delete
      end

      def char
        Character[@char.id]
      end

      def magic
        char.magic
      end

      def caster(charclass, tradition, skill, feats:, known:, slots:)
        m = PF2Magic.create(:character => @char,
                            :tradition => { charclass => [ tradition, 'trained' ] },
                            :spell_abil => { charclass => 'Charisma' },
                            :spells_per_day => { charclass => slots },
                            (Pf2emagic.get_caster_type(charclass) == 'spontaneous' ? :repertoire : :spellbook) => { charclass => known })
        @char.update(:magic => m, :pf2_level => 6, :pf2_money => 5000,
                     :pf2_base_info => { 'charclass' => charclass },
                     :pf2_feats => { 'charclass' => feats })

        Pf2eSkills.create(:name => skill, :prof_level => 'trained', :character => @char)

        # A played character: the ledger holds their sheet, so a spell learned is history.
        Pf2e::Ledger.seed_from_sheet!(Character[@char.id])
      end

      def polymath
        caster('Bard', 'occult', 'Occultism', :feats => [ 'Esoteric Polymath' ],
               :known => { '1' => [ 'Fear' ] }, :slots => { '1' => 3, '2' => 3, '3' => 2 })
      end

      describe "Learn a Spell" do
        it "should write a spell into the book and charge half for a critical success" do
          polymath

          result = Pf2emagic.learn_spell(char, nil, 'Sleep', 20)

          expect(result.ok?).to be true
          expect(result.state['degree']).to eq 3
          expect(char.pf2_money).to eq 4900
          expect(magic.spellbook['Book of Occult Spells']['1']).to include 'Sleep'
          expect(Pf2e::Ledger.explain_for(char, :kind => 'spell_access', :key => 'Sleep').first['source_type']).to eq 'learned'
        end

        it "should write into a Wizard's spellbook" do
          caster('Wizard', 'arcane', 'Arcana', :feats => [], :known => { '1' => [ 'Force Barrage' ] },
                 :slots => { '1' => 3 })

          Pf2emagic.learn_spell(char, nil, 'Sleep', 20)

          expect(magic.spellbook['Wizard']['1']).to include 'Sleep'
        end

        # Spellbook Prodigy makes a critical failure a failure, so no materials are lost.
        it "should charge nothing for a critical failure with Spellbook Prodigy" do
          caster('Wizard', 'arcane', 'Arcana', :feats => [ 'Spellbook Prodigy', 'Magical Shorthand' ],
                 :known => { '1' => [ 'Force Barrage' ] }, :slots => { '1' => 3 })

          result = Pf2emagic.learn_spell(char, nil, 'Slow', 1)

          expect(result.state['degree']).to eq 0
          expect(result.state['learned']).to be false
          expect(char.pf2_money).to eq 5000
        end

        it "should block the spell after a failure until the character gains a level" do
          polymath

          failed = Pf2emagic.learn_spell(char, nil, 'Slow', 1)

          expect(failed.state['learned']).to be false
          expect(char.pf2_money).to eq 5000 - 800
          expect(Pf2emagic.learn_spell(char, nil, 'Slow', 20).code).to eq :retry_blocked

          @char.update(:pf2_level => 7)

          expect(Pf2emagic.learn_spell(char, nil, 'Slow', 20).ok?).to be true
        end

        it "should refuse a character with nowhere to write the spell" do
          caster('Bard', 'occult', 'Occultism', :feats => [], :known => { '1' => [ 'Fear' ] }, :slots => { '1' => 3 })

          expect(Pf2emagic.learn_spell(char, nil, 'Sleep', 20).code).to eq :no_target
        end
      end

      describe "the daily pick" do
        before(:each) do
          polymath
          Pf2emagic.learn_spell(char, nil, 'Slow', 20)
        end

        it "should make a repertoire spell a signature spell until the next preparations" do
          expect(Pf2emagic.pick_from_book(char, 'esotericpolymath', 'Fear', nil).ok?).to be true
          expect(Entries.signature_ranks(magic, 'Bard', 'Fear')).to eq [ '1' ]

          Pf2emagic.generate_spells_today(char)

          expect(Entries.signature_ranks(magic, 'Bard', 'Fear')).to eq []
        end

        it "should put a book spell in the repertoire at the rank asked for until the next preparations" do
          Pf2emagic.pick_from_book(char, 'esotericpolymath', 'Slow', '3')

          expect(Entries.known_at(magic, 'Bard', '3')).to include 'Slow'

          Pf2emagic.generate_spells_today(char)

          expect(Entries.known_at(magic, 'Bard', '3')).to_not include 'Slow'
        end

        it "should allow one pick between preparations" do
          Pf2emagic.pick_from_book(char, 'esotericpolymath', 'Fear', nil)

          expect(Pf2emagic.pick_from_book(char, 'esotericpolymath', 'Slow', '3').code).to eq :already_picked
        end

        it "should refuse a book the character does not keep" do
          expect(Pf2emagic.pick_from_book(char, 'arcaneevolution', 'Fear', nil).code).to eq :no_book
        end
      end

      # What a level-up commits: the repertoire copied into Esoteric Polymath's book, and never the
      # day's pick.
      describe "the lists a level-up records" do
        it "should copy the repertoire into a book that keeps it" do
          polymath

          expect(Entries.known_lists(char)['Book of Occult Spells']).to eq('1' => [ 'Fear' ])
        end

        it "should leave the day's pick out of the class's list" do
          polymath
          Pf2emagic.learn_spell(char, nil, 'Slow', 20)
          Pf2emagic.pick_from_book(char, 'esotericpolymath', 'Slow', '3')

          expect(Entries.known_lists(char)['Bard']).to eq('1' => [ 'Fear' ])
        end

        it "should not copy the repertoire into a book that does not keep it" do
          caster('Sorcerer', 'arcane', 'Arcana', :feats => [ 'Arcane Evolution' ],
                 :known => { '1' => [ 'Fear' ] }, :slots => { '1' => 3 })

          expect(Entries.known_lists(char)['Arcane Evolution List']).to be_nil
        end
      end
    end
  end
end
