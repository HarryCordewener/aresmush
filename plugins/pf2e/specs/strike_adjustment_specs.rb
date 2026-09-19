require "plugin_test_loader"

module AresMUSH

  # What an effect changes about an attack itself, rather than about the roll.
  #
  # `AdjustStrike` says a weapon counts as something it is not: made of silver, carrying a property
  # rune, throwing further, or having a trait. Only traits were read, so Far Shot doubled nothing and
  # Ghost Hunter's ghost touch went nowhere. A rule says which attacks it means with a `definition`
  # tested against the attack's own facts, so those facts are Foundry's vocabulary unchanged.
  describe "strike adjustments", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Strike#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'martial' => 'expert' })
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @items = []
    end

    after(:each) do
      @items.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def carry(name)
      info = Global.read_config('pf2e_weapons', name) || raise("no such weapon: #{name}")
      item = Pf2egear.create_item(@char, 'weapons', name, 1, info)
      item.update(:equipped => true)
      @items << item

      item
    end

    def strike(item)
      Pf2eCombat.attack_descriptor(reread, item)
    end

    def feats(*names)
      @char.update(:pf2_feats => { 'class' => names })
    end

    describe "a range increment" do
      it "should be the weapon's own without anything saying otherwise" do
        bow = carry('Shortbow')

        expect(strike(bow)['range']).to eq bow.range.to_i
      end

      # Far Shot doubles the range increment of a ranged weapon.
      it "should double for a feat that multiplies it" do
        bow = carry('Shortbow')
        plain = strike(bow)['range']

        feats('Far Shot')

        expect(strike(bow)['range']).to eq plain * 2
      end

      it "should not reach a melee weapon, which the feat is not about" do
        sword = carry('Longsword')

        feats('Far Shot')

        expect(strike(sword)['range']).to eq sword.range.to_i
      end

      # Strong Arm adds ten feet to a thrown weapon's.
      it "should gain ten feet for a thrown weapon" do
        javelin = carry('Javelin')
        plain = strike(javelin)['range']

        feats('Strong Arm')

        expect(strike(javelin)['range']).to eq plain + 10
      end
    end

    describe "a property rune the attack counts as having" do
      # Ghost Hunter: a magical weapon has the effects of ghost touch against something incorporeal.
      # Whether the thing in front of you is incorporeal is not something the sheet can know, so the
      # player says so - and until they do, the rune is not granted.
      def magical_sword
        sword = carry('Longsword')
        sword.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => { 'list' => [] } })
        @char.update(:pf2_feats => { 'ancestry' => [ 'Ghost Hunter' ] })

        sword
      end

      it "should be granted while the circumstance holds" do
        sword = magical_sword
        @char.update(:pf2_roll_options => { 'target:trait:incorporeal' => true })

        expect(strike(sword)['runes']).to include 'ghost-touch'
      end

      it "should not be granted until the player says the circumstance holds" do
        expect(strike(magical_sword)['runes']).to_not include 'ghost-touch'
      end

      it "should not be granted to a weapon that is not magical" do
        sword = carry('Longsword')
        @char.update(:pf2_feats => { 'ancestry' => [ 'Ghost Hunter' ] },
                     :pf2_roll_options => { 'target:trait:incorporeal' => true })

        expect(strike(sword)['runes']).to_not include 'ghost-touch'
      end

      it "should carry what was etched on it" do
        sword = carry('Longsword')
        sword.update(:runes => { 'fundamental' => {}, 'property' => { 'list' => [ 'Flaming' ] } })

        expect(strike(sword)['runes']).to eq [ 'flaming' ]
      end
    end

    # The facts a definition is tested against. Four of the shapes their data uses were not supplied by
    # anything, so a rule about a ranged weapon or a magical one could not tell.
    describe "what an attack answers to" do
      it "should say whether it is ranged or melee" do
        expect(Pf2eCombat.attack_options(strike(carry('Shortbow')))).to include 'item:ranged'
        expect(Pf2eCombat.attack_options(strike(carry('Longsword')))).to include 'item:melee'
      end

      it "should say a thrown weapon is thrown, and thrown in melee" do
        options = Pf2eCombat.attack_options(strike(carry('Javelin')))

        expect(options).to include 'item:thrown'
      end

      it "should say it is magical once a rune is etched on it" do
        sword = carry('Longsword')

        expect(Pf2eCombat.attack_options(strike(sword))).to_not include 'item:magical'

        sword.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => {} })

        expect(Pf2eCombat.attack_options(strike(sword))).to include 'item:magical'
      end

      it "should name the damage it does in full, and its category" do
        options = Pf2eCombat.attack_options(strike(carry('Longsword')))

        expect(options).to include 'item:damage:type:slashing', 'item:damage:category:physical'
      end

      it "should say how many hands it takes and how long it reloads" do
        options = Pf2eCombat.attack_options(strike(carry('Shortbow')))

        expect(options.grep(/item:hands-held:/).size).to eq 1
        expect(options.grep(/item:reload:/).size).to eq 1
      end

      it "should say what the character is proficient at with it" do
        expect(Pf2eCombat.attack_options(strike(carry('Longsword'))))
          .to include 'item:proficiency:rank:2'
      end
    end
  end
end
