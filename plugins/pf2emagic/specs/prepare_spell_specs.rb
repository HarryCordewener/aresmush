require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Preparing a spell reaches the tradition check for every prepared caster, so the check has to
    # read the class's tradition.
    describe "preparing a spell", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Prepare#{rand(1000000)}")
        @magic = PF2Magic.create(:character => @char,
                                 :tradition => { 'Cleric' => [ 'divine', 'trained' ] },
                                 :spell_abil => { 'Cleric' => 'Wisdom' },
                                 :spells_per_day => { 'Cleric' => { '1' => 2 } })
        @char.update(:magic => @magic, :pf2_base_info => { 'charclass' => 'Cleric' }, :pf2_level => 1)
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      it "should prepare a spell of the class's tradition" do
        result = Pf2emagic.prepare_spell('Fear', Character[@char.id], 'Cleric', '1')

        expect(result).to be_a Hash
        expect(PF2Magic[@magic.id].spells_prepared['Cleric']['1']).to eq [ 'Fear' ]
      end

      it "should refuse a spell off the class's tradition" do
        result = Pf2emagic.prepare_spell('Force Barrage', Character[@char.id], 'Cleric', '1')

        expect(result).to eq t('pf2emagic.cant_prepare_trad', :cc => 'Cleric')
      end

      # "Your deity grants you additional spells", which a Cleric prepares as if they were on the
      # divine list. A deity grants the spell, so an uncommon one needs nothing else.
      describe "a deity's cleric spells" do
        def worships(deity, ranks = { '1' => 2 })
          @char.update(:pf2_faith => { 'deity' => deity })
          @magic.update(:spells_per_day => { 'Cleric' => ranks })
        end

        it "should prepare one off the divine list" do
          worships('Animus')

          result = Pf2emagic.prepare_spell('Force Barrage', Character[@char.id], 'Cleric', '1')

          expect(result).to be_a Hash
          expect(PF2Magic[@magic.id].spells_prepared['Cleric']['1']).to eq [ 'Force Barrage' ]
        end

        it "should prepare an uncommon one with no spellbook" do
          worships('Thul', '1' => 2, '4' => 1)

          expect(Pf2emagic.prepare_spell('Rewrite Memory', Character[@char.id], 'Cleric', '4')).to be_a Hash
        end

        it "should not prepare one below its own rank" do
          worships('Althea', '1' => 2, '4' => 1)

          expect(Pf2emagic.prepare_spell('Containment', Character[@char.id], 'Cleric', '1'))
            .to eq t('pf2emagic.cant_prepare_level')
        end

        it "should not prepare another deity's" do
          worships('Althea')

          expect(Pf2emagic.prepare_spell('Force Barrage', Character[@char.id], 'Cleric', '1'))
            .to eq t('pf2emagic.cant_prepare_trad', :cc => 'Cleric')
        end

        # A Champion has a deity too, and no cleric spells.
        it "should give them only to a class that says so" do
          worships('Animus')

          expect(Pf2emagic.deity_list_spells(Character[@char.id], 'Champion')).to eq []
          expect(Pf2emagic.deity_list_spells(Character[@char.id], 'Cleric')).to eq [ 'Force Barrage', 'Telepathy', 'Spell Riposte' ]
        end

        it "should list them on the magic display" do
          worships('Animus')

          template = PF2MagicDisplayTemplate.new(Character[@char.id], PF2Magic[@magic.id], double)

          expect(template.format_deity_spells('Cleric')).to include('Force Barrage, Telepathy, Spell Riposte')
        end
      end
    end
  end
end
