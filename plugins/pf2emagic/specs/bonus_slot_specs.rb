require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # A spell slot a feat adds at the highest rank for certain spells: Divine Evolution and Primal
    # Evolution (Sorcerer 4), Gifted Power (Oracle 6), whose Special line adds the spells of Divine
    # Access and Mysterious Repertoire.
    describe "a slot for certain spells" do

      describe "the data" do
        before(:all) do
          @feats = YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats']

          @spells = {}
          Dir.glob("game/config/pf2e_spells_*.yml").each { |file| @spells.merge!(YAML.load_file(file)['pf2e_spells']) }
        end

        def slotted
          @feats.select { |_name, details| details['bonus_slot'] }
        end

        it "should give the three feats a slot" do
          expect(slotted.keys.sort).to eq [ 'Divine Evolution', 'Gifted Power', 'Primal Evolution' ]
        end

        it "should name only real spells" do
          named = slotted.values.flat_map { |details| Array(details['bonus_slot']['spells']) }

          expect(named.reject { |spell| @spells.key?(spell) }).to eq []
        end

        it "should draw only from sources it knows" do
          sources = slotted.values.flat_map { |details| Array(details['bonus_slot']['spells_from']) }

          expect(sources - BonusSlots::SOURCES.keys).to eq []
        end
      end

      describe "on a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Slot#{rand(1000000)}")
        end

        after(:each) do
          live = Character[@char.id]

          live.spellcasting_entries.each(&:delete) if live.respond_to?(:spellcasting_entries)
          live.magic.delete if live.magic
          live.delete
        end

        def char
          Character[@char.id]
        end

        def caster(charclass, specialty, feats, repertoire, level: 9, top: 5)
          per_day = (1..top).each_with_object({ 'cantrip' => 5 }) { |rank, out| out[rank.to_s] = 3 }
          magic = PF2Magic.create(:character => @char,
                                  :tradition => { charclass => [ 'divine', 'trained' ] },
                                  :spell_abil => { charclass => 'Charisma' },
                                  :spells_per_day => { charclass => per_day },
                                  :repertoire => { charclass => repertoire })

          @char.update(:magic => magic, :pf2_level => level, :pf2_feats => { 'charclass' => feats },
                       :pf2_base_info => { 'charclass' => charclass, 'specialize' => specialty })

          Pf2emagic.generate_spells_today(char)
        end

        def slots_left(charclass = 'Sorcerer')
          char.magic.spells_today[charclass]
        end

        def bonus_left
          char.magic.spells_today[BonusSlots::TODAY]
        end

        describe "Divine Evolution" do
          before(:each) do
            caster('Sorcerer', 'Angelic', [ 'Divine Evolution' ], { '1' => [ 'Fear' ] })
          end

          it "should give a use a day" do
            expect(bonus_left).to eq('Divine Evolution' => 1)
          end

          it "should cast heal at the highest rank without it in the repertoire" do
            cast = Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [])

            expect(cast['spell level']).to eq '5'
            expect(cast['spell type']).to eq 'Divine Evolution slot'
            expect(bonus_left).to eq('Divine Evolution' => 0)
            expect(slots_left['5']).to eq 3
          end

          it "should cast it once a day" do
            Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [])

            expect(Pf2emagic.cast_spell(char, 'Sorcerer', 'Harm', [])).to eq t('pf2emagic.not_in_list')
          end

          it "should not cast it below the highest rank" do
            expect(Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [], 3)).to eq t('pf2emagic.not_in_list')
            expect(bonus_left).to eq('Divine Evolution' => 1)
          end

          it "should leave other spells to the ordinary slots" do
            cast = Pf2emagic.cast_spell(char, 'Sorcerer', 'Fear', [])

            expect(cast['spell level']).to eq '1'
            expect(bonus_left).to eq('Divine Evolution' => 1)
          end

          it "should come back with a rest" do
            Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [])
            Pf2emagic.generate_spells_today(char)

            expect(bonus_left).to eq('Divine Evolution' => 1)
          end
        end

        describe "with the spell in the repertoire too" do
          before(:each) do
            caster('Sorcerer', 'Angelic', [ 'Divine Evolution' ], { '1' => [ 'Heal' ] })
          end

          it "should cast at its own rank from an ordinary slot when no rank is asked for" do
            cast = Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [])

            expect(cast['spell level']).to eq '1'
            expect(bonus_left).to eq('Divine Evolution' => 1)
          end

          it "should spend the feat's slot first at the highest rank" do
            cast = Pf2emagic.cast_spell(char, 'Sorcerer', 'Heal', [], 5)

            expect(cast['spell type']).to eq 'Divine Evolution slot'
            expect(slots_left['5']).to eq 3
          end
        end

        describe "Primal Evolution" do
          it "should cast a summons" do
            caster('Sorcerer', 'Fey', [ 'Primal Evolution' ], { '1' => [ 'Fear' ] })

            expect(Pf2emagic.cast_spell(char, 'Sorcerer', 'Summon Animal', [])['spell level']).to eq '5'
          end
        end

        # A sorcerer casting through another class's archetype does not spend the sorcerer's slot.
        it "should keep the slot to its own class" do
          caster('Sorcerer', 'Angelic', [ 'Divine Evolution' ], { '1' => [ 'Fear' ] })

          expect(BonusSlots.usable(char, 'Oracle Archetype', 'Heal')).to eq []
        end

        describe "Gifted Power" do
          # Flames grants ignition, breathe fire, blazing bolt at 3rd and fireball at 5th.
          it "should cast the mystery's granted spells, not its cantrip" do
            caster('Oracle', 'Flames', [ 'Gifted Power' ], { '1' => [ 'Bless' ] }, :level => 6, :top => 3)

            spells = BonusSlots.summary(char, 'Oracle').first[2]

            expect(spells).to include('Breathe Fire', 'Blazing Bolt', 'Fireball')
            expect(spells).to_not include('Ignition')
          end

          it "should heighten one to the highest rank" do
            caster('Oracle', 'Flames', [ 'Gifted Power' ], { '1' => [ 'Bless' ] }, :level => 6, :top => 3)

            cast = Pf2emagic.cast_spell(char, 'Oracle', 'Breathe Fire', [], 3)

            expect(cast['spell type']).to eq 'Gifted Power slot'
            expect(slots_left('Oracle')['3']).to eq 3
          end

          it "should not cast a spell above the highest rank" do
            caster('Oracle', 'Ancestors', [ 'Gifted Power' ], { '1' => [ 'Bless' ] }, :level => 9, :top => 4)

            expect(Pf2emagic.cast_spell(char, 'Oracle', 'Dreaming Potential', [])).to eq t('pf2emagic.not_in_list')
          end

          # Its Special line.
          it "should cast Divine Access's and Mysterious Repertoire's spells" do
            caster('Oracle', 'Ancestors', [ 'Gifted Power', 'Mysterious Repertoire' ],
                   { '1' => [ 'Bless', 'Force Barrage' ] }, :level => 14, :top => 7)
            @char.update(:pf2_level_tracker => { '11' => { 'feat_choices' => { 'Divine Access' => [ 'Althea', 'Containment' ] } } })

            spells = BonusSlots.summary(char, 'Oracle').first[2]

            expect(spells).to include('Containment', 'Force Barrage', 'Ill Omen')
            expect(spells).to_not include('Soothe', 'Bless')
          end
        end

        it "should show the slot on the magic display" do
          caster('Sorcerer', 'Angelic', [ 'Divine Evolution' ], { '1' => [ 'Fear' ] })

          template = PF2MagicDisplayTemplate.new(char, char.magic, double)

          expect(template.format_bonus_slots(char, 'Sorcerer')).to include('Divine Evolution', '1 (Heal, Harm)')
        end
      end
    end
  end
end
