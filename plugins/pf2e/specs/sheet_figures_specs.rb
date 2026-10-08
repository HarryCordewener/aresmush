require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the sheet's stats and magic show: the AC a fight is about, and an innate spell's attack and
    # DC worked out from its grant rather than a row of noughts.
    describe "a sheet's figures", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Figures#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => {},
                                 :pf2_features => {})
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @magic = PF2Magic.create(:character => @char)
        @char.update(:combat => @combat, :magic => @magic)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
      end

      after(:each) do
        (@abilities + [ @magic, @combat, @char ]).each(&:delete)
      end

      def sheet
        template = Pf2eSheetTemplate.allocate
        template.instance_variable_set(:@char, Character[@char.id])
        template
      end

      it "should show the AC" do
        expect(sheet.ac).to eq Pf2eCombat.calculate_ac(Character[@char.id])
        expect(File.read(File.join(Pf2e.plugin_dir, 'templates', 'sheet_template.erb'))).to include('AC%xn: #{ac}')
      end

      it "should show no innate row for someone with no innate spells" do
        expect(sheet.spell_dcs.join).to_not include('nnate')
      end

      # With nothing to cast, the Magic section says so rather than showing an empty table.
      it "should say a character with nothing to cast is no caster" do
        expect(sheet.spell_dcs).to eq []
        expect(File.read(File.join(Pf2e.plugin_dir, 'templates', 'sheet_template.erb'))).to include('if magic_stats && spell_dcs.any?')
      end

      # Trained at level 3 is +5, and Charisma 16 is +3: an attack of +8 and a DC of 18.
      it "should work out an innate spell's attack and DC from its grant" do
        @magic.update(:innate_spells => [ { 'name' => 'Detect Magic', 'level' => 'cantrip', 'tradition' => 'arcane',
                                            'cast_stat' => 'Charisma' } ])

        row = sheet.spell_dcs.join

        expect(row).to include('Arcane', '8', '18')
        expect(row).to_not match(/\b0\s+0\b/)
      end
    end
  end
end
