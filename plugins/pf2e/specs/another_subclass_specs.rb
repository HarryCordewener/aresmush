require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Choosing another subclass: Order Explorer and Multifarious Muse join one, Order Magic takes an
    # explored order's spell, and Crossblooded Evolution and its greater feat borrow another
    # bloodline's blood magic and gift spells. Player Core pp. 101, 129, 131; Player Core 2 pp. 154,
    # 157. And the gift spells a bloodline's own 1st-level choice decides.
    describe "another subclass", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Subclass#{rand(1000000)}")
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

      def block(feat)
        Pf2e.feat_choice_def(Global.read_config('pf2e_feats', feat))
      end

      # A choice already resolved, as the ledger's fold records it.
      def chosen(choices)
        @char.update(:pf2_level_tracker => { '2' => { 'feat_choices' => choices } })
      end

      def sorcerer(bloodline, option: nil, slots: (1..9))
        per_day = slots.each_with_object({}) { |rank, out| out[rank.to_s] = 3 }
        magic = PF2Magic.create(:character => @char,
                                :tradition => { 'Sorcerer' => [ 'divine', 'trained' ] },
                                :spell_abil => { 'Sorcerer' => 'Charisma' },
                                :spells_per_day => { 'Sorcerer' => per_day },
                                :repertoire => { 'Sorcerer' => { '1' => [ 'Heal' ] } })

        @char.update(:magic => magic, :pf2_level => 18,
                     :pf2_base_info => { 'charclass' => 'Sorcerer', 'specialize' => bloodline, 'specialize_info' => option })
      end

      describe "Order Explorer" do
        before(:each) do
          @char.update(:pf2_level => 4, :pf2_base_info => { 'charclass' => 'Druid', 'specialize' => 'Storm' })
        end

        it "should offer the orders other than the druid's own" do
          expect(Pf2e.choice_options(char, 'Order Explorer', block('Order Explorer'))).to eq %w(Animal Leaf Untamed)
        end

        it "should not offer an order already explored" do
          chosen('Order Explorer' => [ 'Leaf' ])

          expect(Pf2e.choice_options(char, 'Order Explorer', block('Order Explorer'))).to eq %w(Animal Untamed)
        end

        it "should grant the order's 1st-level feat, prerequisites waived" do
          grants = Pf2e.choice_grants(char, block('Order Explorer'), 'Leaf', 'Order Explorer')

          expect(grants).to eq('feat' => [ { 'name' => 'Leshy Familiar', 'prereqs' => 'ignore' } ])
        end

        it "should make the druid a member of the order for prerequisites" do
          chosen('Order Explorer' => [ 'Leaf' ])

          expect(Pf2e.held_specialties(char)).to include('LEAF', 'STORM')
        end
      end

      it "should let Multifarious Muse grant another muse's 1st-level feat" do
        @char.update(:pf2_level => 2, :pf2_base_info => { 'charclass' => 'Bard', 'specialize' => 'Enigma' })

        expect(Pf2e.choice_options(char, 'Multifarious Muse', block('Multifarious Muse'))).to eq %w(Maestro Polymath Warrior)
        expect(Pf2e.choice_grants(char, block('Multifarious Muse'), 'Warrior', 'Multifarious Muse'))
          .to eq('feat' => [ { 'name' => 'Martial Performance', 'prereqs' => 'ignore' } ])
      end

      describe "Order Magic" do
        before(:each) do
          @char.update(:pf2_level => 4, :pf2_base_info => { 'charclass' => 'Druid', 'specialize' => 'Storm' })
          chosen('Order Explorer' => [ 'Leaf', 'Animal' ])
        end

        it "should offer the orders explored" do
          expect(Pf2e.choice_options(char, 'Order Magic', block('Order Magic'))).to eq %w(Animal Leaf)
        end

        it "should grant the order's initial order spell" do
          expect(Pf2e.choice_grants(char, block('Order Magic'), 'Leaf', 'Order Magic'))
            .to eq('magic_stats' => { 'focus_spell' => { 'order' => [ 'Cornucopia' ] } })
        end
      end

      describe "Crossblooded Evolution" do
        it "should offer the bloodlines other than the sorcerer's own" do
          sorcerer('Angelic')

          options = Pf2e.choice_options(char, 'Crossblooded Evolution', block('Crossblooded Evolution'))

          expect(options).to include('Elemental', 'Fey')
          expect(options).to_not include('Angelic')
        end

        it "should then ask the chosen bloodline's own 1st-level choice" do
          sorcerer('Angelic')
          chosen('Crossblooded Evolution' => [ 'Elemental' ])

          step = block('Crossblooded Evolution')['then_choose']

          expect(Pf2e.choice_options(char, 'Crossblooded Evolution', step)).to eq %w(Air Earth Fire Metal Water Wood)
        end

        it "should not open that step for a bloodline with no such choice" do
          sorcerer('Angelic')
          chosen('Crossblooded Evolution' => [ 'Fey' ])

          expect(Pf2e.open_chained_choice(char, 'Crossblooded Evolution', block('Crossblooded Evolution'))).to eq []
          expect((char.pf2_to_assign || {})['feat choice']).to be_blank
        end

        it "should show both bloodlines' blood magic, with the secondary's damage type" do
          sorcerer('Angelic')
          chosen('Crossblooded Evolution' => [ 'Elemental', 'Water' ])

          shown = Pf2emagic.blood_magic(char)

          expect(shown.map { |b| [ b['bloodline'], b['name'], b['damage'] ] })
            .to eq [ [ 'Angelic', 'Divine Aura', nil ], [ 'Elemental', 'Elemental Fury', 'bludgeoning' ] ]
        end
      end

      describe "Greater Crossblooded Evolution" do
        before(:each) do
          sorcerer('Angelic')
        end

        def pick(spells)
          chosen('Crossblooded Evolution' => [ 'Elemental', 'Water' ], 'Greater Crossblooded Evolution' => spells)
        end

        it "should offer the secondary bloodline's gift spells, its own choice's included" do
          pick([])

          options = Pf2e.choice_options(char, 'Greater Crossblooded Evolution', block('Greater Crossblooded Evolution'))

          expect(options).to include('Frostbite', 'Aqueous Orb', 'Resist Energy', 'Earthquake')
          expect(options).to_not include('Tailwind', 'Heal')
        end

        it "should know the spells at the highest rank the sorcerer casts, a cantrip as a cantrip" do
          pick([ 'Frostbite', 'Aqueous Orb', 'Earthquake' ])

          magic = char.magic

          expect(Pf2emagic::Entries.known_at(magic, 'Sorcerer', '9')).to include('Aqueous Orb', 'Earthquake')
          expect(Pf2emagic::Entries.known_at(magic, 'Sorcerer', 'cantrip')).to include('Frostbite')
        end

        it "should move them up when the sorcerer gains a rank" do
          pick([ 'Aqueous Orb' ])
          char.magic.update(:spells_per_day => { 'Sorcerer' => char.magic.spells_per_day['Sorcerer'].merge('10' => 1) })

          magic = char.magic

          expect(Pf2emagic::Entries.known_at(magic, 'Sorcerer', '10')).to include('Aqueous Orb')
          expect(Pf2emagic::Entries.known_at(magic, 'Sorcerer', '9')).to_not include('Aqueous Orb')
        end

        # Borrowed through a feat choice rather than learned, so a level-up never records them.
        it "should leave them out of the lists a level-up records" do
          pick([ 'Aqueous Orb' ])

          expect(Pf2emagic::Entries.known_lists(char)['Sorcerer']).to eq('1' => [ 'Heal' ])
        end
      end

      describe "a bloodline's gifts that follow its 1st-level choice" do
        it "should give an air elemental sorcerer the air cantrip and 1st-rank spell" do
          sorcerer('Elemental', :option => 'Air')

          PF2Magic.update_magic(char, 'Sorcerer', { 'choice_repertoire' => [ 'cantrip', '1' ] }, nil)

          repertoire = char.magic.repertoire['Sorcerer']

          expect(repertoire['cantrip']).to include 'Gale Blast'
          expect(repertoire['1']).to include 'Tailwind'
        end

        it "should give a brine dragon sorcerer the brine exemplar's 2nd-rank spell" do
          sorcerer('Draconic', :option => 'Brine')

          PF2Magic.update_magic(char, 'Sorcerer', { 'choice_repertoire' => [ '2' ] }, nil)

          expect(char.magic.repertoire['Sorcerer']['2']).to include 'Water Breathing'
        end
      end
    end
  end
end
