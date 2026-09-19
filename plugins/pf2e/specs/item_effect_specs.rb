require "plugin_test_loader"

module AresMUSH

  # What an item does to a figure, from Foundry's own data.
  #
  # Our catalogue used to carry a hand-written `bonus:` hash, and ten of its fifty-one entries granted
  # a conditional bonus unconditionally: Skeleton Key (Greater) gave its +2 to Thievery generally
  # rather than to picking a lock, and Boots of Bounding (Greater) gave +3 Athletics rather than +3 to
  # jumping. The rules are now imported from the pf2e system's equipment packs in their own vocabulary,
  # predicates intact, and there is one vocabulary instead of two.
  describe "item effects", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Item#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [])
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
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

    # Through the real shop path, so the catalogue's own keys are what land on the item.
    def give(name, invested: true)
      info = Global.read_config('pf2e_magicitem', name)

      raise "no such magic item: #{name}" unless info

      item = Pf2egear.create_item(@char, 'magicitem', name, 1, info)
      item.update(:invested => invested)
      @items << item

      item
    end

    it "should have the catalogue rules the import wrote" do
      expect(Global.read_config('pf2e_magicitem', 'Skeleton Key', 'rules')).to_not be_nil
    end

    it "should make an item without raising, now that the catalogue carries keys the model has not" do
      expect { give('Third Eye') }.to_not raise_error
    end

    describe "an unconditional bonus" do
      it "should reach the figure it names" do
        before = Pf2eSkills.get_skill_bonus(reread, 'Deception')

        give('Ring of Lies')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception')).to eq before + 2
      end

      it "should not reach a figure it does not name" do
        before = Pf2eSkills.get_skill_bonus(reread, 'Thievery')

        give('Ring of Lies')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Thievery')).to eq before
      end

      it "should do nothing while the item is uninvested" do
        before = Pf2eSkills.get_skill_bonus(reread, 'Deception')

        give('Ring of Lies', :invested => false)

        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception')).to eq before
      end

      it "should reach a figure named through a group rather than by name" do
        before = Pf2eCombat.get_perception(reread)

        give('Third Eye')

        expect(Pf2eCombat.get_perception(reread)).to eq before + 3
      end
    end

    # The whole reason for reading Foundry's predicates: this bonus is for picking a lock.
    describe "a bonus with circumstances" do
      it "should not apply when the player has not said what they are doing" do
        before = Pf2eSkills.get_skill_bonus(reread, 'Thievery')

        give('Skeleton Key (Greater)')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Thievery')).to eq before
      end

      it "should apply when they have" do
        before = Pf2eSkills.get_skill_bonus(reread, 'Thievery')

        give('Skeleton Key (Greater)')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Thievery', [ 'action:pick-a-lock' ]))
          .to eq before + 2
      end

      it "should be listed as conditional rather than hidden" do
        give('Skeleton Key (Greater)')

        conditional = Pf2eSkills.skill_breakdown(reread, 'Thievery')['conditional']

        expect(conditional.map { |row| row['source'] }).to include 'Skeleton Key (Greater)'
        expect(conditional.first['when']).to eq [ 'action:pick-a-lock' ]
      end

      it "should be kept out of the stacking, so it cannot override one that applies" do
        give('Skeleton Key (Greater)')
        give("Charlatan's Gloves")

        counted = Pf2eSkills.skill_breakdown(reread, 'Thievery')['modifiers']
                            .select { |row| row['enabled'] && row['type'] == 'item' }

        expect(counted.map { |row| row['source'] }).to eq [ "Charlatan's Gloves" ]
      end

      # `or` is the commonest compound in their data, so it is worth one real item.
      it "should read a predicate naming several circumstances" do
        give('Tracker\'s Goggles')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Survival', [ 'action:track' ]))
          .to eq Pf2eSkills.get_skill_bonus(reread, 'Survival') + 1
      end
    end

    # An item that declares its own circumstance establishes it by being worn. The player says nothing;
    # the cloak is the one doing something.
    describe "a circumstance the item declares itself" do
      it "should apply what the cloak gives without being asked" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Stealth')

        give('Clandestine Cloak (Greater)')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Stealth')).to eq plain + 2
      end

      # The cloak's trade: what it costs applies as automatically as what it gives.
      it "should apply what the cloak costs too" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')

        give('Clandestine Cloak (Greater)')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Diplomacy')).to eq plain - 1
      end

      # Its Deception bonus needs the cloak *and* an action, so the cloak alone is not enough.
      it "should leave a row that also needs an action conditional" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Deception')

        give('Clandestine Cloak (Greater)')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception')).to eq plain
        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception', Pf2e.circumstances([ 'impersonate' ])))
          .to eq plain + 2
      end

      it "should do none of it while the cloak is not invested" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Stealth')

        give('Clandestine Cloak (Greater)', :invested => false)

        expect(Pf2eSkills.get_skill_bonus(reread, 'Stealth')).to eq plain
      end
    end

    # Two item bonuses to the same figure are the better of the two, not their sum.
    describe "two items granting the same kind of bonus" do
      it "should count the better one only" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Deception')

        give('Ring of Lies')
        give('Whisper of the First Lie')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Deception')).to eq plain + 3
      end
    end

    # Damage has a kind now, so an item can say it shrugs some of it off.
    describe "an item that resists damage" do
      before(:each) do
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
      end

      after(:each) { @hp&.delete }

      it "should hold what the item declares" do
        give('Aeon Stone (Preserving)')
        held = Pf2e::IWR.of(reread)

        expect(held['resistance'].map { |one| one['type'] }).to include 'persistent-damage'
      end

      it "should take the resistance off damage of that kind" do
        give('Aeon Stone (Preserving)')
        Pf2eHP.modify_damage(reread, 8, false, true, 'persistent-damage')

        expect(Pf2eHP[@hp.id].damage).to eq 5
      end

      it "should leave damage of another kind alone" do
        give('Aeon Stone (Preserving)')
        Pf2eHP.modify_damage(reread, 8, false, true, 'fire')

        expect(Pf2eHP[@hp.id].damage).to eq 8
      end

      it "should leave damage of no kind alone, since nothing resists it" do
        give('Aeon Stone (Preserving)')
        Pf2eHP.modify_damage(reread, 8, false, true)

        expect(Pf2eHP[@hp.id].damage).to eq 8
      end

      it "should do nothing while the stone is not invested" do
        give('Aeon Stone (Preserving)', :invested => false)
        Pf2eHP.modify_damage(reread, 8, false, true, 'persistent-damage')

        expect(Pf2eHP[@hp.id].damage).to eq 8
      end
    end

    # A roll string says what the roller is doing, which is how a player claims one of these.
    describe "claiming one in a roll" do
      it "should count the bonus the action allows" do
        give('Skeleton Key (Greater)')

        without = Pf2e.parse_roll_string(reread, [ '0d1', 'thievery' ])['total']
        with = Pf2e.parse_roll_string(reread, [ '0d1', 'thievery' ],
                                      Pf2e.circumstances([ 'pick-a-lock' ]))['total']

        expect(with - without).to eq 2
      end

      # A player says what they are doing, not how Foundry spells it, so a named circumstance is
      # offered both as a bare word and as an action.
      it "should offer a named circumstance in both spellings" do
        expect(Pf2e.circumstances([ 'Pick a Lock' ])).to eq [ 'pick-a-lock', 'action:pick-a-lock' ]
      end

      it "should count a bonus that wants the bare spelling" do
        give('Obsidian Goggles')

        plain = Pf2eCombat.get_perception(reread)

        expect(Pf2eCombat.get_perception(reread, Pf2e.circumstances([ 'visual' ]))).to eq plain + 1
      end
    end
  end
end
