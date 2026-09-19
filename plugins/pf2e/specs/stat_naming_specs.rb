require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a player means when they ask why a figure is what it is. `sheet/why reflex` has to reach the
    # save and `sheet/why athletics` the skill, and a name the catalogue does not hold is a lore -
    # which is what a lore is.
    describe "naming a figure", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config
      end

      it "should reach the figures with fixed names" do
        expect(Stat.identify('hp')).to eq [ 'hp', nil ]
        expect(Stat.identify('AC')).to eq [ 'ac', nil ]
        expect(Stat.identify('speed')).to eq [ 'speed', nil ]
        expect(Stat.identify('perception')).to eq [ 'perception', nil ]
        expect(Stat.identify('class dc')).to eq [ 'class_dc', nil ]
      end

      it "should reach a save by the shorthand a player types" do
        expect(Stat.identify('fort')).to eq [ 'save', 'fort' ]
        expect(Stat.identify('reflex')).to eq [ 'save', 'reflex' ]
      end

      # The shorthand and the full name are the same statistic, and the reader canonicalises the name
      # before deciding what the save answers to.
      it "should canonicalise a save's name" do
        expect(Pf2e.canonical_save('fort')).to eq 'fortitude'
        expect(Pf2e.canonical_save('ref')).to eq 'reflex'
        expect(Pf2e.canonical_save('will')).to eq 'will'
      end

      it "should reach a skill by its catalogue name, whatever the case" do
        expect(Stat.identify('athletics')).to eq [ 'skill', 'Athletics' ]
      end

      it "should treat a name the catalogue does not hold as a lore" do
        expect(Stat.identify('dragon lore')).to eq [ 'lore', 'Dragon Lore' ]
      end

      it "should answer nothing for a word that names no figure" do
        expect(Stat.identify('vibes')).to be_nil
      end

      # Every kind the naming table can produce has to be a kind the reader can assemble.
      it "should only name kinds the reader knows" do
        kinds = [ 'hp', 'ac', 'speed', 'perception', 'class dc', 'fort', 'reflex', 'will',
                  'athletics', 'dragon lore' ].map { |term| Stat.identify(term).first }

        expect(kinds.uniq - Stat::BY_KIND.keys).to eq []
      end
    end
  end
end
