require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Casting an innate spell: each grant carries its own tradition, rank and the ability it is cast with,
    # so a character with no casting class casts one as readily as a wizard does.
    # A cantrip is cast at will however it was granted, so a grant that gives one a rank would make it
    # one use a day.
    describe "the innate cantrips the data grants" do
      it "should grant each at will" do
        spells = {}
        Dir.glob("game/config/pf2e_spells_*.yml").each { |file| spells.merge!(YAML.load_file(file)['pf2e_spells']) }
        feats = YAML.load_file("game/config/pf2e_feat_skill.yml")['pf2e_feats']
                    .merge(YAML.load_file("game/config/pf2e_feat_general.yml")['pf2e_feats'])
                    .merge(YAML.load_file("game/config/pf2e_feat_ancestry.yml")['pf2e_feats'])
                    .merge(YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats'])

        ranked = feats.flat_map do |feat, details|
          grants = (details['magic_stats'] || {})['innate_spell']
          (grants.is_a?(Array) ? grants : [ grants ]).compact.flat_map do |grant|
            Array(grant['name']).select { |spell| Array((spells[spell] || {})['traits']).include?('cantrip') }
                                .reject { |_spell| grant['level'].to_s == 'cantrip' }
                                .map { |spell| "#{feat}: #{spell}" }
          end
        end

        expect(ranked).to eq []
      end
    end

    describe "casting an innate spell", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Innate#{rand(1000000)}", :pf2_level => 6)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
        @magic = PF2Magic.create(:character => @char,
                                 :innate_spells => [
                                   { 'name' => 'Detect Magic', 'level' => 'cantrip', 'tradition' => 'arcane', 'cast_stat' => 'Charisma' },
                                   { 'name' => 'Fear', 'level' => 1, 'tradition' => 'primal', 'cast_stat' => 'Wisdom' }
                                 ])
        @char.update(:magic => @magic)
        Pf2emagic.generate_spells_today(Character[@char.id])
      end

      after(:each) do
        @abilities.each(&:delete)
        @magic.delete
        @char.delete
      end

      def cast(spell)
        Pf2emagic.cast_spell(Character[@char.id], 'Innate', spell, [], nil, 'innate')
      end

      it "should cast an innate cantrip for a character with no casting class" do
        cast = cast('Detect Magic')

        expect(cast).to be_a Hash
        expect(cast['tradition']).to eq 'arcane'
        expect(cast['spell_abil']).to eq 'Charisma'
        expect(cast['spell type']).to eq 'innate'
      end

      it "should cast an innate cantrip again and again" do
        3.times { cast('Detect Magic') }

        expect(cast('Detect Magic')).to be_a Hash
      end

      it "should spend a ranked innate spell's use for the day" do
        expect(cast('Fear')).to be_a Hash
        expect(cast('Fear')).to eq t('pf2emagic.no_available_slots')
      end

      it "should cast with the ability the grant names" do
        expect(cast('Fear')['spell_abil']).to eq 'Wisdom'
      end
    end
  end
end
