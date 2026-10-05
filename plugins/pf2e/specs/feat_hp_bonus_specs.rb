require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Hit Points a feat adds to a character's maximum: Toughness adds their level, and each Resiliency
    # feat 3 for every class feat of its archetype they hold. Both come from the feat's own rules in
    # config - a FlatModifier on `hp`, over a counter the archetype's feats raise - so they follow the
    # character's level and their later archetype feats with nothing written down.
    describe "Pf2eHP.get_max_hp", :dbtest => true do
      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Hardy#{rand(1000000)}", :pf2_level => 6)
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 6)
        @char.update(:hp => @hp)
      end

      after(:each) do
        @hp.delete if @hp
        @char.delete if @char
      end

      # (6 class + 0 Constitution) x 6 levels + 8 ancestry, before any feat.
      def base
        44
      end

      # Resiliency is worth 3 for each feat of its archetype, counted by a value the archetype's feats
      # keep. Taking a feat writes those; a spec that puts feats on the sheet itself writes them here.
      def held(feats)
        @char.update(:pf2_feats => feats)
        Pf2e::Paths.apply_all!(Character[@char.id])
      end

      it "should add Toughness and Resiliency to the maximum" do
        held('general' => [ 'Toughness' ],
             'charclass' => [ 'Fighter Dedication', 'Fighter Resiliency', 'Basic Maneuver' ])

        expect(Pf2eHP.get_max_hp(Character[@char.id])).to eq base + 6 + 9
      end

      it "should raise current Hit Points with it" do
        held('general' => [ 'Toughness' ])
        @hp.update(:damage => 10)

        expect(Pf2eHP.get_current_hp(Character[@char.id])).to eq base + 6 - 10
      end
    end
  end
end
