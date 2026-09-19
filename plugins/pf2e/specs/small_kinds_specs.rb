require "plugin_test_loader"

module AresMUSH

  # The last five kinds of rule on what we stock, and the fact a great many of the rest ask about.
  describe "the small kinds", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Small#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' },
                                  :weapon_prof => { 'martial' => 'trained', 'simple' => 'trained' },
                                  :perception => 'trained')
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @char.update(:combat => @combat, :hp => @hp, :pf2_level => 5, :pf2_conditions => {},
                   :pf2_traits => [ 'human', 'humanoid' ], :pf2_derived => {}, :pf2_feats => {},
                   :pf2_roll_aliases => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => name == 'Dexterity' ? 18 : 12)
      }
      @skills = %w{Arcana}.map { |name| Pf2eSkills.create_skill_for_char(name, @char) }
      @skills.each { |skill| skill.update(:prof_level => 'trained') }
      @items = []
    end

    after(:each) do
      Pf2e::ActiveEffects.on(Character[@char.id]).each(&:delete)
      (@items + @skills + @abilities).each(&:delete)
      [ @hp, @combat, @char ].each { |one| one&.delete }
    end

    def reread
      Character[@char.id]
    end

    def apply(name, options = [])
      Pf2e::ActiveEffects.apply(reread, name, :options => options).state
    end

    def feats(*names)
      @char.update(:pf2_feats => { 'class' => names })
    end

    def damage
      Pf2eHP[@hp.id].damage
    end

    # An effect is a fact as Foundry names it: Effect: Rage is `self:effect:rage`. A hundred and forty
    # predicates in config ask about one, and nothing answered.
    describe "what a character is under, as a fact" do
      it "should name an effect without the prefix it is filed under" do
        apply('rage')

        expect(Pf2e::Effects.facts(reread)).to include 'self:effect:rage'
      end

      it "should give its counter too, where it has one" do
        apply('Effect: Drakeheart Mutagen (Lesser)')

        expect(Pf2e::Effects.facts(reread).grep(/self:effect:drakeheart/)).to_not be_empty
      end

      # Animal Skin caps Dexterity at 3 while the barbarian rages.
      it "should let a rule about raging apply while raging" do
        feats('Animal Skin')
        plain = Pf2e::Stat.total(reread, 'ac')

        apply('rage')

        expect(Pf2e::Stat.total(reread, 'ac')).to eq plain - 1
      end
    end

    describe "traits an effect gives or takes away" do
      it "should give a trait, and the mode of being it implies" do
        apply('Soul Thief')

        expect(Pf2e::Effects.facts(reread)).to include 'self:trait:undead', 'self:mode:undead'
        expect(Pf2e::Effects.facts(reread)).to_not include 'self:mode:living'
      end

      it "should be living without one" do
        expect(Pf2e::Effects.facts(reread)).to include 'self:mode:living'
      end

      it "should take a trait away" do
        @char.update(:pf2_traits => [ 'human', 'humanoid', 'incorporeal' ])
        apply('Calcification (Failure)')

        expect(Pf2e::Effects.facts(reread)).to_not include 'self:trait:incorporeal'
      end
    end

    # Dexterity 18 is +4 to AC, unless something caps it lower. Both of these give AC of their own too,
    # so it is the Dexterity row itself that is held against the cap.
    describe "a cap on Dexterity" do
      def dexterity
        Pf2e::Stat.of(reread, 'ac')['modifiers'].find { |row| row['slug'] == 'dex' }['value']
      end

      it "should be the whole modifier with nothing capping it" do
        expect(dexterity).to eq 4
      end

      it "should hold it to the effect's cap" do
        apply('Drakeheart Mutagen (Lesser)')

        expect(dexterity).to eq 2
      end

      it "should take the lowest of two caps" do
        apply('Drakeheart Mutagen (Lesser)')
        apply('Mountain Stance')

        expect(dexterity).to eq 0
      end
    end

    describe "hit points an effect takes" do
      # Quicksilver Mutagen costs twice your level, and they cannot be healed while it lasts.
      it "should take them as the effect begins" do
        apply('Quicksilver Mutagen (Lesser)')

        expect(damage).to eq 10
      end

      it "should not let them be healed while it lasts" do
        apply('Quicksilver Mutagen (Lesser)')
        Pf2eHP.modify_damage(reread, 50, true)

        expect(damage).to eq 10
      end

      it "should let them be healed once it ends" do
        apply('Quicksilver Mutagen (Lesser)')
        Pf2e::ActiveEffects.remove_named(reread, 'Quicksilver Mutagen (Lesser)')
        Pf2eHP.modify_damage(reread, 50, true)

        expect(damage).to eq 0
      end

      # Drained lowers the maximum and takes the same from the current. With damage kept rather than
      # current hit points, lowering the maximum is already the loss - it is not taken twice.
      it "should cost a drained character their level in hit points, once" do
        before = Pf2eHP.get_max_hp(reread) - damage

        Pf2e.set_condition(reread, 'Drained', 1)

        expect(Pf2eHP.get_max_hp(reread) - Pf2eHP[@hp.id].damage).to eq before - 5
      end
    end

    # Assured Knowledge: 10 in place of the d20 for Recall Knowledge, and only proficiency added.
    describe "a number in place of the d20" do
      before(:each) { feats('Assured Knowledge') }

      def arcana(words)
        Pf2e.parse_roll_string(reread, [ 'arcana' ], Pf2e.circumstances(words))
      end

      it "should stand in for the die when the roller asks for it" do
        rolled = arcana([ 'recall-knowledge', 'substitute:assured-knowledge' ])

        # Trained at 5th level is +7, and nothing but proficiency is added: the feat suppresses the rest.
        expect(rolled['total']).to eq 10 + 7
        expect(rolled['list'].first).to eq '10'
      end

      it "should take a Foundry option as it is spelled" do
        expect(Pf2e.circumstances([ 'Substitute:Assured Knowledge' ])).to eq [ 'substitute:assured-knowledge' ]
      end

      it "should leave the die alone when nobody asks" do
        expect(arcana([ 'recall-knowledge' ])['list'].first).to eq '1d20'
      end

      it "should not stand in for a roll it is not about" do
        expect(arcana([ 'substitute:assured-knowledge' ])['list'].first).to eq '1d20'
      end
    end

    # The second attack in a turn is at -5, or -4 with an agile weapon; Agile Grace makes it -3.
    describe "the penalty for another attack" do
      def attack(name, which)
        info = Global.read_config('pf2e_weapons', name)
        item = Pf2egear.create_item(@char, 'weapons', name, 1, info)
        item.update(:equipped => true)
        @items << item

        options = which > 1 ? [ "map:increases:#{which - 1}" ] : []
        Pf2e::Stat.total(reread, 'attack', Pf2eCombat.attack_descriptor(reread, item), options)
      end

      it "should be nothing on the first attack" do
        expect(attack('Longsword', 1) - attack('Longsword', 1)).to eq 0
      end

      it "should be -5 on the second, and -10 on the third" do
        first = attack('Longsword', 1)

        expect(attack('Longsword', 2)).to eq first - 5
        expect(attack('Longsword', 3)).to eq first - 10
      end

      it "should be -4 and -8 with an agile weapon" do
        first = attack('Shortsword', 1)

        expect(attack('Shortsword', 2)).to eq first - 4
        expect(attack('Shortsword', 3)).to eq first - 8
      end

      it "should be the least severe a feat offers" do
        feats('Agile Grace')
        first = attack('Shortsword', 1)

        expect(attack('Shortsword', 2)).to eq first - 3
        expect(attack('Shortsword', 3)).to eq first - 6
      end
    end
  end
end
