require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The Breadth feats: one more slot at each rank below an archetype's two highest, and for a
    # repertoire caster one more spell in the repertoire there.
    describe "archetype breadth feats" do

      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @magic = YAML.load_file("game/config/pf2e_magic.yml")['pf2e_magic']
      end

      def breadths
        @feats.select { |_name, details| details.key?('archetype_breadth') }
      end

      it "should be one for every casting archetype" do
        casters = Array(@magic['prepared_archetypes']) + Array(@magic['spontaneous_archetypes'])
        covered = breadths.values.map { |details| Array(details['assoc_archetype']).first }

        expect(covered.sort).to eq casters.sort
      end

      it "should add a slot per rank, and a repertoire spell only for a repertoire caster" do
        breadths.each_pair do |name, details|
          archetype = Array(details['assoc_archetype']).first
          expected = { 'spells_per_day' => 1 }
          expected['repertoire'] = 1 if Array(@magic['spontaneous_archetypes']).include?(archetype)

          expect(details['archetype_breadth']).to eq(expected), name
        end
      end

      it "should cover the Breadth feats the file has" do
        names = @feats.keys.select { |name| name.end_with?(' Breadth') }

        expect(breadths.keys.sort).to eq names.sort
      end
    end

    describe "Advancement::ArchetypeBreadth.newly_owed" do
      def owed(before, after, held)
        Advancement::ArchetypeBreadth.newly_owed(before, after, held)
      end

      it "should reach nothing below a third rank" do
        expect(owed(nil, 2, false)).to eq []
      end

      it "should reach every rank below the two highest when first taken" do
        expect(owed(3, 3, false)).to eq [ 1 ]
        expect(owed(6, 6, false)).to eq [ 1, 2, 3, 4 ]
      end

      it "should reach only the ranks a new highest uncovers when already held" do
        expect(owed(3, 4, true)).to eq [ 2 ]
        expect(owed(3, 6, true)).to eq [ 2, 3, 4 ]
      end

      it "should reach nothing new when the highest rank has not moved" do
        expect(owed(4, 4, true)).to eq []
      end
    end

    describe "Advancement::ArchetypeBreadth", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Breadth#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })
      end

      after(:each) do
        @char.magic.delete if @char && @char.magic
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      # A character casting from an archetype with slots up to `highest`, as the spellcasting feats
      # left them, holding `feats`.
      def casting(archetype, tradition, highest, feats, bumped: [])
        slots = { 'cantrip' => 2 }
        (1..highest).each { |rank| slots[rank.to_s] = bumped.include?(rank) ? 2 : 1 }

        magic = PF2Magic.create(:character => @char,
                                :tradition => { archetype => [ tradition, 'trained' ] },
                                :spells_per_day => { archetype => slots })
        @char.update(:magic => magic, :pf2_archetypeinfo => { 'archetype1' => archetype },
                     :pf2_feats => { 'charclass' => feats })
      end

      def take(feat_name, level, to_assign: {}, advancement: {})
        @char.update(:pf2_level => level - 1, :advancing => true)

        found = Pf2e.get_feat_details(feat_name)

        Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)

        { :to_assign => to_assign, :advancement => advancement }
      end

      def advance_holding(level)
        @char.update(:pf2_level => level - 1, :pf2_xp => 1000, :advancing => false)

        Pf2e.assess_advancement(@char, {})

        char = Character[@char.id]

        { :to_assign => char.pf2_to_assign, :advancement => char.pf2_advancement }
      end

      def slots(out, archetype)
        (((out[:advancement]['magic_stats'] || {})[archetype] || {})['spells_per_day'] || {})
          .transform_keys(&:to_s)
      end

      def wizard
        [ 'Wizard Dedication', 'Basic Wizard Spellcasting' ]
      end

      def sorcerer
        [ 'Sorcerer Dedication', 'Basic Sorcerer Spellcasting' ]
      end

      describe "taking it" do
        it "should add a slot at each rank below the two highest" do
          casting('Wizard Archetype', 'arcane', 3, wizard)

          out = take('Arcane Breadth', 8)

          expect(slots(out, 'Wizard Archetype')).to eq({ '1' => 2 })
        end

        it "should open a repertoire pick at that rank for a repertoire caster" do
          casting('Sorcerer Archetype', 'divine', 3, sorcerer)

          out = take('Bloodline Breadth', 8)

          expect(slots(out, 'Sorcerer Archetype')).to eq({ '1' => 2 })
          expect(out[:to_assign]['repertoire']['Sorcerer Archetype']).to eq({ 1 => [ 'open' ] })
        end

        it "should cover every rank a late taker has passed" do
          casting('Wizard Archetype', 'arcane', 6, wizard + [ 'Expert Wizard Spellcasting' ])

          out = take('Arcane Breadth', 16)

          expect(slots(out, 'Wizard Archetype')).to eq({ '1' => 2, '2' => 2, '3' => 2, '4' => 2 })
        end
      end

      describe "held while the archetype gains a rank" do
        it "should reach the rank the new highest uncovers" do
          casting('Wizard Archetype', 'arcane', 3, wizard + [ 'Arcane Breadth' ], :bumped => [ 1 ])

          out = take('Expert Wizard Spellcasting', 12)

          expect(slots(out, 'Wizard Archetype')).to eq({ '4' => 1, '2' => 2 })
        end

        it "should reach it at a level-up the schedule brings" do
          casting('Wizard Archetype', 'arcane', 4,
            wizard + [ 'Arcane Breadth', 'Expert Wizard Spellcasting' ], :bumped => [ 1, 2 ])

          out = advance_holding(14)

          expect(slots(out, 'Wizard Archetype')).to eq({ '5' => 1, '3' => 2 })
        end

        it "should cover all three ranks when Expert comes late" do
          casting('Wizard Archetype', 'arcane', 3, wizard + [ 'Arcane Breadth' ], :bumped => [ 1 ])

          out = take('Expert Wizard Spellcasting', 16)

          expect(slots(out, 'Wizard Archetype')).to eq(
            { '2' => 2, '3' => 2, '4' => 2, '5' => 1, '6' => 1 })
        end
      end

      it "should come out the same whichever of Breadth and Expert is taken first" do
        casting('Sorcerer Archetype', 'divine', 3, sorcerer)

        breadth_first = take('Bloodline Breadth', 12)
        breadth_first = take('Expert Sorcerer Spellcasting', 12,
          :to_assign => breadth_first[:to_assign], :advancement => breadth_first[:advancement])

        expert_first = take('Expert Sorcerer Spellcasting', 12)
        expert_first = take('Bloodline Breadth', 12,
          :to_assign => expert_first[:to_assign], :advancement => expert_first[:advancement])

        expect(slots(breadth_first, 'Sorcerer Archetype')).to eq({ '1' => 2, '2' => 2, '4' => 1 })
        expect(slots(expert_first, 'Sorcerer Archetype')).to eq(slots(breadth_first, 'Sorcerer Archetype'))
        expect(breadth_first[:to_assign]['repertoire']).to eq(expert_first[:to_assign]['repertoire'])
      end

      it "should open nothing twice when staged again" do
        casting('Sorcerer Archetype', 'divine', 3, sorcerer)

        out = take('Bloodline Breadth', 8)
        Advancement::ArchetypeBreadth.stage(@char, 'Sorcerer Archetype', out[:to_assign], out[:advancement])

        expect(out[:to_assign]['repertoire']['Sorcerer Archetype']).to eq({ 1 => [ 'open' ] })
      end

      it "should add nothing without the feat" do
        casting('Wizard Archetype', 'arcane', 3, wizard)

        out = take('Expert Wizard Spellcasting', 12)

        expect(slots(out, 'Wizard Archetype')).to eq({ '4' => 1 })
      end
    end
  end
end
