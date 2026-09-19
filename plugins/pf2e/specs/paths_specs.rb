require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The modes an effect writes a value with, which are Foundry's (`ae-like.ts:152`) and not all
    # obvious: upgrade and downgrade take the better and the worse rather than setting, so two feats that
    # both train you in a skill do not make you an expert.
    describe Paths do

      describe "the modes" do
        def mode(name, current, change)
          Paths::MODES[name].call(current, change)
        end

        it "should override outright" do
          expect(mode('override', 4, 2)).to eq 2
        end

        it "should add and subtract" do
          expect(mode('add', 4, 2)).to eq 6
          expect(mode('subtract', 4, 2)).to eq 2
        end

        # `remove` is `subtract` under another name for a number, which is how their data uses it.
        it "should read remove as subtract" do
          expect(mode('remove', 4, 2)).to eq 2
        end

        it "should truncate a multiply rather than round it" do
          expect(mode('multiply', 5, 1.5)).to eq 7
        end

        # The reason a rank is written with upgrade: it takes the better of the two.
        it "should take the better on upgrade and the worse on downgrade" do
          expect(mode('upgrade', 3, 1)).to eq 3
          expect(mode('upgrade', 1, 3)).to eq 3
          expect(mode('downgrade', 3, 1)).to eq 1
        end

        it "should read a missing value as nothing" do
          expect(mode('add', nil, 2)).to eq 2
          expect(mode('upgrade', nil, 2)).to eq 2
        end

        it "should read a flag as one and nothing" do
          expect(mode('override', 0, true)).to eq true
          expect(mode('add', true, 1)).to eq 2
        end

        it "should have every mode their data uses" do
          expect(Paths::MODES.keys)
            .to include 'override', 'add', 'subtract', 'remove', 'multiply', 'upgrade', 'downgrade'
        end
      end

      describe "which paths may be written" do
        it "should recognise a skill rank" do
          row, name = Paths.for('system.skills.nature.rank')

          expect(row['name']).to eq 'skill rank'
          expect(name).to eq 'nature'
        end

        it "should recognise the dying recovery DC" do
          expect(Paths.for('system.attributes.dying.recoveryDC').first['name'])
            .to eq 'dying recovery DC'
        end

        it "should recognise carrying capacity" do
          expect(Paths.for('inventory.bulk.maxAddend').first['name']).to eq 'carrying capacity'
        end

        # These exist so another rule's predicate can ask about them, which is why they have to be
        # written somewhere a predicate can see rather than nowhere.
        it "should recognise a counter a predicate reads" do
          expect(Paths.for('flags.system.monkDedicationCount').first['name']).to eq 'counter'
        end

        it "should recognise an armour proficiency, which AC reads" do
          row, category = Paths.for('system.proficiencies.defenses.heavy.rank')

          expect(row['name']).to eq 'armour proficiency'
          expect(category).to eq 'heavy'
        end

        # A path we cannot write is refused, because an effect that silently writes nothing is a sheet
        # that is quietly wrong and one that writes to the wrong place is worse.
        it "should refuse a path it cannot write" do
          expect(Paths.for('system.details.level.value')).to be_nil
          expect(Paths.writable?('system.details.level.value')).to be false
        end

        # Hit points are assembled from the ledger and from effects that name the `hp` domain, so an
        # effect writing the total directly would be overwritten by the next fold - which is why the
        # registry does not offer it and a rule naming it is refused at import.
        it "should refuse a path a figure already owns" do
          expect(Paths.writable?('system.attributes.hp.max')).to be false
        end
      end

      # Their data overrides a path with a list as readily as with a count, so reading one as a number on
      # the way out would raise the next time the same path was written.
      describe "a value that is not a number" do
        it "should read a stored list back as it stands" do
          char = double(:pf2_derived => { 'flags.system.wildShapeForms' => [ 'pest-form' ] })

          expect(Paths.for('flags.system.wildShapeForms').first['read']
                      .call(char, 'wildShapeForms')).to eq [ 'pest-form' ]
        end

        it "should let a list override a count without raising" do
          expect(Paths::MODES['override'].call(0, [ 'pest-form' ])).to eq [ 'pest-form' ]
        end

        it "should count a list as nothing when a mode wants a number" do
          expect(Paths::MODES['upgrade'].call([ 'pest-form' ], 2)).to eq 2
        end
      end

      describe "ranks, which are written as numbers and read as words" do
        it "should number them in order" do
          expect(Paths.rank_number('untrained')).to eq 0
          expect(Paths.rank_number('expert')).to eq 2
          expect(Paths.rank_number('legendary')).to eq 4
        end

        it "should name a number back" do
          expect(Paths.rank_name(1)).to eq 'trained'
          expect(Paths.rank_name(4)).to eq 'legendary'
        end

        it "should read a rank it does not know as untrained" do
          expect(Paths.rank_number('dabbling')).to eq 0
        end

        it "should stay inside the ranks that exist" do
          expect(Paths.rank_name(9)).to eq 'legendary'
          expect(Paths.rank_name(-1)).to eq 'untrained'
        end
      end
    end
  end
end
