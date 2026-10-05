require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Player Core pg. 215, Spellcasting Archetypes: Basic, Expert and Master Spellcasting each grant one
    # slot per rank on a schedule of levels, and a repertoire caster a signature spell at the first level
    # of each tier.
    describe "archetype spellcasting feats" do

      def schedule
        { 'Basic' => [ 4, 6, 8 ], 'Expert' => [ 12, 14, 16 ], 'Master' => [ 18, 20 ] }
      end

      # The rank each level's slot is at.
      def rank_at(level)
        { 4 => 1, 6 => 2, 8 => 3, 12 => 4, 14 => 5, 16 => 6, 18 => 7, 20 => 8 }[level.to_i]
      end

      def archetype_magic_keys
        PF2Magic::STAT_KEYS + [ 'proficiency' ]
      end

      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @archetypes = YAML.load_file("game/config/pf2e_archetypes.yml")['pf2e_archetype']
        @magic = YAML.load_file("game/config/pf2e_magic.yml")['pf2e_magic']
      end

      def casters
        Array(@magic['prepared_archetypes']) + Array(@magic['spontaneous_archetypes'])
      end

      def feat_for(tier, archetype)
        "#{tier} #{archetype.sub(/ Archetype\z/, '')} Spellcasting"
      end

      def spontaneous?(archetype)
        Array(@magic['spontaneous_archetypes']).include?(archetype)
      end

      it "should cover every casting archetype at every tier" do
        casters.each do |archetype|
          schedule.each_key do |tier|
            expect(@feats).to have_key(feat_for(tier, archetype))
          end
        end
      end

      it "should grant one slot at each level of the tier's schedule and nowhere else" do
        casters.each do |archetype|
          schedule.each_pair do |tier, levels|
            name = feat_for(tier, archetype)
            at_level = @feats[name]['at_level'] || {}

            expect(at_level.keys.map(&:to_i).sort).to eq(levels), name

            levels.each do |level|
              slots = at_level[level]['archetype_magic']['spells_per_day']

              expect(slots).to eq({ rank_at(level) => 1 }), "#{name} at #{level}"
            end
          end
        end
      end

      it "should use only keys the staging understands" do
        casters.each do |archetype|
          schedule.each_key do |tier|
            (@feats[feat_for(tier, archetype)]['at_level'] || {}).each_value do |entry|
              expect(entry.keys).to eq [ 'archetype_magic' ]
              expect(entry['archetype_magic'].keys - archetype_magic_keys).to eq []
            end
          end
        end
      end

      # The list a new rank adds to is the one the dedication opened: a spellbook, a repertoire, or
      # nothing for a caster preparing from its whole tradition.
      it "should grow the list the dedication keeps, and only that one" do
        casters.each do |archetype|
          dedication = @archetypes[archetype]['initial_dedication']['magic_stats']
          list = %w(spellbook repertoire).find { |key| dedication.key?(key) }

          schedule.each_key do |tier|
            @feats[feat_for(tier, archetype)]['at_level'].each_pair do |level, entry|
              magic = entry['archetype_magic']
              rank = rank_at(level)

              expect(magic.keys & %w(spellbook repertoire)).to eq(list ? [ list ] : []), "#{archetype} #{level}"
              expect(magic[list]).to eq({ rank => list == 'spellbook' ? 2 : 1 }) if list
            end
          end
        end
      end

      it "should raise proficiency at the first level of Expert and Master only" do
        casters.each do |archetype|
          schedule.each_pair do |tier, levels|
            at_level = @feats[feat_for(tier, archetype)]['at_level']

            levels.each do |level|
              expected = level == levels.first && tier != 'Basic' ? tier.downcase : nil

              expect(at_level[level]['archetype_magic']['proficiency']).to eq(expected), "#{archetype} #{level}"
            end
          end
        end
      end

      # A `feat` prereq is a list of feats the character must hold, so anything else written there
      # makes the feat impossible to take.
      it "should name only real feats as feat prerequisites" do
        casters.each do |archetype|
          schedule.each_key do |tier|
            name = feat_for(tier, archetype)

            Array(@feats[name]['prereq']['feat']).each do |required|
              expect(@feats).to have_key(required), "#{name} requires #{required.inspect}"
            end
          end
        end
      end

      # A Sorcerer's tradition comes from the bloodline and a Witch's from the patron, so the skill
      # their Expert and Master feats ask for follows it.
      it "should ask for the tradition's skill where the archetype's tradition varies" do
        { 'Sorcerer Archetype' => 'Sorcerer', 'Witch Archetype' => 'Witch' }.each_pair do |archetype, cls|
          { 'Expert' => 'master', 'Master' => 'legendary' }.each_pair do |tier, prof|
            prereq = @feats["#{tier} #{cls} Spellcasting"]['prereq']

            expect(prereq['tradition_skill']).to eq([ "#{archetype}/#{prof}" ])
            expect(prereq).to_not have_key('skill')
          end
        end
      end

      it "should give a repertoire caster a signature at the first level of each tier" do
        casters.each do |archetype|
          schedule.each_pair do |tier, levels|
            at_level = @feats[feat_for(tier, archetype)]['at_level']
            signature_at = tier == 'Basic' ? 6 : levels.first

            levels.each do |level|
              expected = spontaneous?(archetype) && level == signature_at ? { 'any' => 1 } : nil

              expect(at_level[level]['archetype_magic']['signature_spells']).to eq(expected), "#{archetype} #{level}"
            end
          end
        end
      end
    end

    # The two routes a feat's level clauses take - on taking it, and at each later level-up - and what
    # they stage for the archetype.
    describe "Advancement::LevelClauses", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "ArchCast#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })
        @char.update(:pf2_archetypeinfo => { 'archetype1' => 'Wizard Archetype' })
        @char.update(:pf2_feats => { 'charclass' => [ 'Wizard Dedication' ] })
      end

      after(:each) do
        @char.magic.delete if @char && @char.magic
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def casting_as(source, tradition, proficiency = 'trained')
        magic = PF2Magic.create(:character => @char, :tradition => { source => [ tradition, proficiency ] })
        @char.update(:magic => magic)
      end

      # Taking the feat during a level-up to `level`.
      def take(feat_name, level)
        @char.update(:pf2_level => level - 1, :advancing => true)

        found = Pf2e.get_feat_details(feat_name)
        to_assign = {}
        advancement = {}

        result = Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)

        { :to_assign => to_assign, :advancement => advancement, :messages => result[:messages] }
      end

      # Advancing into `level` while already holding the feat.
      def advance_holding(feat_name, level)
        @char.update(:pf2_feats => { 'charclass' => [ 'Wizard Dedication', feat_name ] },
                     :pf2_level => level - 1, :pf2_xp => 1000, :advancing => false)

        Pf2e.assess_advancement(@char, {})

        char = Character[@char.id]

        { :to_assign => char.pf2_to_assign, :advancement => char.pf2_advancement }
      end

      def staged(out, archetype = 'Wizard Archetype')
        (out[:advancement]['magic_stats'] || {})[archetype] || {}
      end

      describe "taking the feat" do
        it "should stage its slot under the archetype" do
          out = take('Basic Wizard Spellcasting', 4)

          expect(staged(out)['spells_per_day']).to eq({ 1 => 1 })
          expect(out[:to_assign]['spellbook']['Wizard Archetype']).to eq({ 1 => [ 'open', 'open' ] })
        end

        it "should leave nothing for advance/done to misapply" do
          out = take('Basic Wizard Spellcasting', 4)

          expect(out[:advancement]['grants']).to be_nil
        end

        it "should leave the base class's spellcasting alone" do
          out = take('Basic Wizard Spellcasting', 4)

          expect((out[:advancement]['magic_stats'] || {}).keys).to eq [ 'Wizard Archetype' ]
        end

        it "should owe every level already passed when taken late" do
          out = take('Basic Wizard Spellcasting', 8)

          expect(staged(out)['spells_per_day']).to eq({ 1 => 1, 2 => 1, 3 => 1 })
          expect(out[:to_assign]['spellbook']['Wizard Archetype']).to eq(
            { 1 => [ 'open', 'open' ], 2 => [ 'open', 'open' ], 3 => [ 'open', 'open' ] })
        end

        it "should raise the tradition the archetype already casts from" do
          @char.update(:pf2_archetypeinfo => { 'archetype1' => 'Sorcerer Archetype' },
                       :pf2_feats => { 'charclass' => [ 'Sorcerer Dedication', 'Basic Sorcerer Spellcasting' ] })
          casting_as('Sorcerer Archetype', 'divine')

          out = take('Expert Sorcerer Spellcasting', 12)

          expect(staged(out, 'Sorcerer Archetype')['tradition']).to eq({ 'divine' => 'expert' })
        end

        it "should open a signature pick at any rank for a repertoire caster" do
          @char.update(:pf2_archetypeinfo => { 'archetype1' => 'Sorcerer Archetype' },
                       :pf2_feats => { 'charclass' => [ 'Sorcerer Dedication', 'Basic Sorcerer Spellcasting' ] })
          casting_as('Sorcerer Archetype', 'divine')

          out = take('Expert Sorcerer Spellcasting', 12)

          expect(out[:to_assign]['signature']['Sorcerer Archetype']).to eq({ 'any' => [ 'open' ] })
          expect(out[:to_assign]['repertoire']['Sorcerer Archetype']).to eq({ 4 => [ 'open' ] })
        end
      end

      describe "advancing while holding it" do
        it "should stage the slot that comes due" do
          out = advance_holding('Basic Wizard Spellcasting', 6)

          # Read back from Redis, so the ranks are strings.
          expect(staged(out)['spells_per_day']).to eq({ '2' => 1 })
          expect(out[:to_assign]['spellbook']['Wizard Archetype']).to eq({ '2' => [ 'open', 'open' ] })
          expect(out[:advancement]['grants']).to be_nil
        end

        it "should stage nothing at a level the schedule skips" do
          out = advance_holding('Basic Wizard Spellcasting', 7)

          expect(staged(out)).to eq({})
          expect(out[:to_assign]['spellbook']).to be_nil
        end
      end

      # What the level opened, filled through the command a player types.
      describe "filling the picks" do
        # An 11th-level character with an archetype's basic spellcasting has its slots to 2nd rank.
        def ready(archetype, tradition, to_assign, repertoire: {})
          magic = PF2Magic.create(:character => @char,
                                  :tradition => { archetype => [ tradition, 'trained' ] },
                                  :spell_abil => { archetype => 'Charisma' },
                                  :spells_per_day => { archetype => { '1' => 1, '2' => 1 } },
                                  :repertoire => { archetype => repertoire })
          @char.update(:magic => magic, :pf2_level => 11, :advancing => true, :pf2_to_assign => to_assign)

          AutoBuilder.new(Character[@char.id])
        end

        it "should designate a signature at the rank the player names" do
          builder = ready('Sorcerer Archetype', 'occult',
            { 'signature' => { 'Sorcerer Archetype' => { 'any' => [ 'open' ] } } },
            :repertoire => { '2' => [ 'Darkness' ] })

          char = builder.run 'advance/spell signature/sorcerer archetype/2=Darkness'

          expect(builder.failures).to be_empty
          expect(char.pf2_to_assign['signature']['Sorcerer Archetype']['2']).to eq [ 'Darkness' ]
          expect(char.pf2_to_assign['signature']['Sorcerer Archetype']['any']).to_not include('open')
        end

        it "should refuse a signature the archetype does not know" do
          builder = ready('Sorcerer Archetype', 'occult',
            { 'signature' => { 'Sorcerer Archetype' => { 'any' => [ 'open' ] } } },
            :repertoire => { '2' => [ 'Darkness' ] })

          char = builder.run 'advance/spell signature/sorcerer archetype/1=Fear'

          expect(builder.failures).to_not be_empty
          expect(char.pf2_to_assign['signature']['Sorcerer Archetype']['any']).to eq [ 'open' ]
        end

        it "should add a spell to the archetype's spellbook" do
          builder = ready('Wizard Archetype', 'arcane',
            { 'spellbook' => { 'Wizard Archetype' => { '1' => [ 'open', 'open' ] } } })

          char = builder.run 'advance/spell spellbook/wizard archetype/1=Force Barrage'

          expect(builder.failures).to be_empty
          expect(char.pf2_to_assign['spellbook']['Wizard Archetype']['1']).to eq [ 'Force Barrage', 'open' ]
        end
      end

      # The draft's class-keyed block reaching the magic object, which is Apply's half.
      it "should add the slot to the archetype's, keeping its cantrips" do
        casting_as('Wizard Archetype', 'arcane')
        @char.magic.update(:spells_per_day => { 'Wizard Archetype' => { 'cantrip' => 2 } })

        Advancement::Apply.all(@char, { 'magic_stats' => { 'Wizard Archetype' => { 'spells_per_day' => { 1 => 1 } } } },
          :charclass => 'Fighter', :client => nil)

        expect(Character[@char.id].magic.spells_per_day).to eq({ 'Wizard Archetype' => { 'cantrip' => 2, '1' => 1 } })
      end
    end
  end
end
