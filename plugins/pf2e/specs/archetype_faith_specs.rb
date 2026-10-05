require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The edicts and anathema an archetype binds a character to: the archetype's own (the Druid's),
    # its specialty's (a Champion's cause, a Superstition barbarian's instinct), or those inside a
    # specialty's dedication block (a Druid's order). Chargen writes a base class's straight to the
    # sheet; an archetype's are staged in the level's draft and join the sheet at advance/done, so
    # they bind only a character who takes the Dedication, and advance/reset takes them back.
    describe "archetype edicts and anathema", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Faith#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' },
                     :pf2_faith => { 'alignment' => 'OL', 'deity' => '', 'anathema' => [ 'Betray a friend.' ] },
                     :pf2_level => 1, :advancing => true)
      end

      after(:each) do
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def specialty(archetype, name)
        Global.read_config('pf2e_archetype_specialty', archetype, name) || {}
      end

      def draft
        Character[@char.id].pf2_advancement
      end

      # The archetype this advancement joined, waiting for its specialty.
      def joining(archetype)
        @char.update(:pf2_archetypeinfo => { 'archetype1' => archetype },
                     :pf2_to_assign => { 'archetype' => archetype, 'archetype_specialty' => 'open' },
                     :pf2_advancement => {})

        AutoBuilder.new(Character[@char.id])
      end

      it "should stage the druid's anathema with Druid Dedication" do
        found = Pf2e.get_feat_details('Druid Dedication')
        to_assign = {}
        advancement = {}

        Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)

        expect(advancement['archetype_anathema']).to eq Global.read_config('pf2e_archetype', 'Druid Archetype', 'anathema')
      end

      it "should stage a champion's cause" do
        builder = joining('Champion Archetype')
        builder.run 'advance/archetype specialty=Redeemer'

        expect(builder.failures).to be_empty
        expect(draft['archetype_edicts']).to eq specialty('Champion Archetype', 'Redeemer')['edicts']
        expect(draft['archetype_anathema']).to eq specialty('Champion Archetype', 'Redeemer')['anathema']
      end

      it "should stage a druid's order" do
        order = specialty('Druid Archetype', 'Storm')['initial_dedication']

        builder = joining('Druid Archetype')
        builder.run 'advance/archetype specialty=Storm'

        expect(builder.failures).to be_empty
        expect(draft['archetype_edicts']).to eq order['edicts']
        expect(draft['archetype_anathema']).to eq order['anathema']
      end

      it "should stage a superstition barbarian's anathema" do
        builder = joining('Barbarian Archetype')
        builder.run 'advance/archetype specialty=Superstition'

        expect(builder.failures).to be_empty
        expect(draft['archetype_anathema']).to eq specialty('Barbarian Archetype', 'Superstition')['anathema']
      end

      it "should stage nothing for an instinct with no anathema" do
        builder = joining('Barbarian Archetype')
        builder.run 'advance/archetype specialty=Fury'

        expect(builder.failures).to be_empty
        expect(draft['archetype_anathema']).to be_nil
        expect(draft['archetype_edicts']).to be_nil
      end

      it "should add them to what the character already holds once the level is done" do
        # Apply writes the attributes and leaves saving to do_advancement, which saves once.
        Advancement::Apply.all(@char,
          { 'archetype_anathema' => [ 'Betray a friend.', 'Lie.' ], 'archetype_edicts' => [ 'Keep your word.' ] },
          :charclass => 'Fighter', :client => nil)
        @char.save

        faith = Character[@char.id].pf2_faith

        expect(faith['anathema']).to eq [ 'Betray a friend.', 'Lie.' ]
        expect(faith['edicts']).to eq [ 'Keep your word.' ]
      end
    end

    # Druid Dedication: "you are bound by the druid's anathema" - the class's own, word for word.
    describe "druid archetype anathema" do
      it "should be the druid class's anathema" do
        archetype = YAML.load_file("game/config/pf2e_archetypes.yml")['pf2e_archetype']['Druid Archetype']
        druid = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']['Druid']

        expect(archetype['anathema']).to eq druid['anathema']
      end

      # "Choose a druidic order... and are also bound by its specific anathema." Player Core pp.
      # 125-126, each with the clarification the book gives it. No order has edicts.
      def order_anathema
        {
          'Animal' => "Commit wanton cruelty to animals or kill animals unnecessarily. (This doesn't prevent you from defending yourself against animals or killing them cleanly for food.)",
          'Leaf' => "Commit wanton cruelty to plants or fungi or kill them unnecessarily. (This doesn't prevent you from defending yourself or harvesting them for survival.)",
          'Storm' => "Pollute the air, allow those who cause major air pollution or climate shifts to go unpunished. (This doesn't force you to take action against merely potential environmental harm or to sacrifice yourself against an obviously superior foe.)",
          'Untamed' => "Become fully domesticated by the temptations of civilization. (This doesn't prevent you from buying and using processed goods or staying in a city for an adventure, but you can never come to rely on these conveniences or truly call such a place your permanent home.)"
        }
      end

      it "should bind a druid of each order to the same anathema, whichever way they came to it" do
        base = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']['Druid']
        archetype = YAML.load_file("game/config/pf2e_archetype_specialty.yml")['pf2e_archetype_specialty']['Druid Archetype']

        order_anathema.each_pair do |order, text|
          # Chargen reads a specialty's anathema from the top of its entry.
          expect(base[order]['anathema']).to eq([ text ]), order
          expect(base[order]['chargen']).to_not have_key('anathema')
          expect(archetype[order]['initial_dedication']['anathema']).to eq([ text ]), order

          expect(base[order]).to_not have_key('edicts')
          expect(archetype[order]['initial_dedication']).to_not have_key('edicts')
        end
      end
    end

    # Player Core 2's instincts, which dropped the older anathema from every instinct but
    # Superstition, and the keys each one carries.
    describe "barbarian instinct data" do
      before(:all) do
        @base = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']['Barbarian']
        @archetype = YAML.load_file("game/config/pf2e_archetype_specialty.yml")['pf2e_archetype_specialty']['Barbarian Archetype']
      end

      def superstition_anathema
        [ "Your deep superstition means it's anathema for you to learn or Cast a Spell, or to wield or use an item that can be activated to Cast a Spell." ]
      end

      it "should have the same six instincts on both sides" do
        expect(@base.keys.sort).to eq %w(Animal Dragon Fury Giant Spirit Superstition)
        expect(@archetype.keys.sort).to eq @base.keys.sort
      end

      it "should give anathema only to Superstition" do
        [ @base, @archetype ].each do |side|
          side.each_pair do |instinct, info|
            expected = instinct == 'Superstition' ? superstition_anathema : nil

            expect(info['anathema']).to eq(expected), instinct
          end
        end
      end

      it "should name each instinct ability" do
        abilities = @base.transform_values { |info| info['instinct_ability'] }

        expect(abilities).to eq(
          'Animal' => 'Bestial Rage', 'Dragon' => 'Draconic Rage', 'Fury' => 'Unstoppable Frenzy',
          'Giant' => 'Titan Mauler', 'Spirit' => 'Spirit Rage', 'Superstition' => 'Superstitious Resilience')
      end

      it "should carry nothing nobody reads" do
        @base.each_pair do |instinct, info|
          expect(info.keys & %w(rage_ability rage_resistance)).to eq([]), instinct
        end
      end
    end
  end
end
