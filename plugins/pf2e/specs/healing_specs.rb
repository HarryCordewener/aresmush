require "plugin_test_loader"

module AresMUSH

  # Healing a character receives, and a night's rest.
  #
  # Both are figures effects reach in Foundry's data and neither was read here: Robust Health recovers
  # your level in extra hit points from Treat Wounds, and Fast Recovery doubles what a night's rest
  # gives. A rule nothing reads is a feat that does nothing, so each is read where it lands.
  describe "healing", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Heal#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @char.update(:combat => @combat, :hp => @hp, :pf2_level => 5, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      @abilities.each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def hurt(amount)
      Pf2eHP.modify_damage(reread, amount, false, true)
    end

    def damage_now
      Pf2eHP[@hp.id].damage
    end

    describe "a bonus to healing received" do
      before(:each) { @char.update(:pf2_feats => { 'general' => [ 'Robust Health' ] }) }

      # The bonus is the character's own, so it applies whoever did the treating.
      it "should recover more from the action it names" do
        hurt(20)
        Pf2eHP.modify_damage(reread, 5, true, false, nil, Pf2e.circumstances([ 'treat-wounds' ]))

        expect(damage_now).to eq 20 - 5 - @char.pf2_level.to_i
      end

      it "should recover only what was given from anything else" do
        hurt(20)
        Pf2eHP.modify_damage(reread, 5, true, false, nil, Pf2e.circumstances([ 'drink-a-potion' ]))

        expect(damage_now).to eq 15
      end

      it "should recover only what was given when nobody said what they were doing" do
        hurt(20)
        Pf2eHP.modify_damage(reread, 5, true)

        expect(damage_now).to eq 15
      end
    end

    it "should recover only what was given without the feat" do
      hurt(20)
      Pf2eHP.modify_damage(reread, 5, true, false, nil, Pf2e.circumstances([ 'treat-wounds' ]))

      expect(damage_now).to eq 15
    end

    # Healing cannot take a character below no damage at all, and a bonus does not change that.
    it "should not overheal past whole" do
      hurt(3)
      @char.update(:pf2_feats => { 'general' => [ 'Robust Health' ] })
      Pf2eHP.modify_damage(reread, 5, true, false, nil, Pf2e.circumstances([ 'treat-wounds' ]))

      expect(damage_now).to eq 0
    end

    describe "a night's rest" do
      def rest
        Pf2e.get_daily_healing(reread)
      end

      it "should recover the character's Constitution modifier for each level" do
        expect(rest).to eq 2 * 5
      end

      it "should recover twice as much with a feat that says so" do
        @char.update(:pf2_feats => { 'general' => [ 'Fast Recovery' ] })
        Pf2e::Paths.apply_all!(reread)

        expect(rest).to eq 2 * (2 * 5)
      end

      it "should be back to once as much when the feat goes" do
        @char.update(:pf2_feats => { 'general' => [ 'Fast Recovery' ] })
        Pf2e::Paths.apply_all!(reread)
        @char.update(:pf2_feats => {})
        Pf2e::Paths.apply_all!(reread)

        expect(rest).to eq 2 * 5
      end
    end
  end
end
