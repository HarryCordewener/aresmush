require "plugin_test_loader"

module AresMUSH

  # Feats that change a number, from Foundry's own feat packs.
  #
  # Toughness adds hit points equal to your level, Fleet adds five feet of speed, Incredible Initiative
  # adds two to initiative. None of those is code here: each is a row of config the feat carries, and
  # the engine never learns their names.
  describe "feat rules", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Feat#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @combat = Pf2eCombat.create(:character => @char, :perception => 'expert')
      @char.update(:hp => @hp, :combat => @combat, :pf2_level => 10, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_base_info => {},
                   :pf2_movement => { 'base_speed' => 25 },
                   :pf2_feats => { 'general' => [] })
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    def score(ability, value)
      @abilities.find { |a| a.name == ability }.update(:base_val => value)
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

    def with_feat(name)
      @char.update(:pf2_feats => { 'general' => [ name ] })

      reread
    end

    it "should have rules on the feats that carry them" do
      expect(Global.read_config('pf2e_feats', 'Toughness', 'rules')).to_not be_nil
    end

    # Toughness is `hp` = `@actor.level`, verbatim from their data.
    it "should add hit points equal to level for Toughness" do
      before = Pf2eHP.get_max_hp(reread)

      expect(Pf2eHP.get_max_hp(with_feat('Toughness'))).to eq before + 10
    end

    it "should add five feet of speed for Fleet" do
      before = Pf2e::Stat.total(reread, 'speed')

      expect(Pf2e::Stat.total(with_feat('Fleet'), 'speed')).to eq before + 5
    end

    it "should name the feat in the breakdown rather than only in the total" do
      sources = Pf2e::Stat.of(with_feat('Toughness'), 'hp')['modifiers'].map { |row| row['source'] }

      expect(sources).to include 'Toughness'
    end

    # Some feats write a value rather than adding a modifier. Toughness is both: hit points equal to
    # level, and a lower DC to recover from dying - the second half of the feat, which nothing read
    # before the writable paths existed.
    describe "a feat that writes a value" do
      it "should lower the DC to recover from dying" do
        with_feat('Toughness')

        expect(Pf2e::Paths.apply_all!(reread)).to be > 0
        expect(Pf2e::Paths.held(reread, 'dying_recovery_dc')).to eq(-1)
      end

      it "should write nothing for a character without the feat" do
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'dying_recovery_dc')).to be_nil
      end

      # Hefty Hauler writes two paths, and both are additions.
      it "should add carrying capacity" do
        with_feat('Hefty Hauler')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'maxaddend')).to eq 2
        expect(Pf2e::Paths.held(reread, 'encumberedafteraddend')).to eq 2
      end

      # Applied again on every fold, because the fold would otherwise take it off - which is why these
      # are derived rather than written to the ledger. The store is emptied first, or an addition would
      # count twice.
      it "should come to the same thing applied twice" do
        with_feat('Hefty Hauler')
        Pf2e::Paths.apply_all!(reread)
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2e::Paths.held(reread, 'maxaddend')).to eq 2
      end

      # The write reached a figure. Toughness lowers the DC to recover from dying, and the dying path
      # reads it - which is the difference between a value being addressable and its being used.
      it "should lower the DC to recover from dying, where the dying rules read it" do
        plain = Pf2eHP.recovery_dc(reread)

        with_feat('Toughness')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2eHP.recovery_dc(reread)).to eq plain - 1
      end

      it "should rise with the dying value, as the rules say" do
        @char.update(:pf2_conditions => { 'Dying' => { 'value' => 2, 'status' => true } })

        expect(Pf2eHP.recovery_dc(reread)).to eq 12
      end

      # Hefty Hauler's two bulk reach what a character can carry, for the same reason.
      it "should raise what a character can carry" do
        plain = Pf2egear.max_bulk(reread)
        before = Pf2egear.encumbered_at(reread)

        with_feat('Hefty Hauler')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2egear.max_bulk(reread)).to eq plain + 2
        expect(Pf2egear.encumbered_at(reread)).to eq before + 2
      end

      it "should refuse a path the registry does not know" do
        expect(Pf2e::Paths.apply!(reread, 'system.attributes.hp.max', 'add', 10)).to be false
      end
    end

    # A speed of a kind the character would not otherwise have. Land is the ancestry's; any other kind
    # exists because something granted it, and the highest grant wins.
    describe "a feat that grants a speed" do
      it "should give a climb speed to a character with none" do
        expect(Pf2e::Stat.total(reread, 'speed', 'climb')).to eq 0

        expect(Pf2e::Stat.total(with_feat('Cave Climber'), 'speed', 'climb')).to eq 10
      end

      it "should leave the land speed alone" do
        before = Pf2e::Stat.total(reread, 'speed')

        expect(Pf2e::Stat.total(with_feat('Cave Climber'), 'speed')).to eq before
      end

      # Two grants of the same kind are the better of the two, not the sum.
      it "should take the better of two grants" do
        @char.update(:pf2_feats => { 'general' => [ 'Cave Climber' ], 'ancestry' => [ "Gecko's Grip" ] },
                     :pf2_base_info => { 'heritage' => 'Cliffscale Lizardfolk' })

        expect(Pf2e::Stat.total(reread, 'speed', 'climb')).to eq 15
      end

      # A grant whose circumstances are unmet grants nothing: Gecko's Grip wants the heritage.
      it "should not grant one whose circumstances are unmet" do
        @char.update(:pf2_feats => { 'ancestry' => [ "Gecko's Grip" ] })

        expect(Pf2e::Stat.total(reread, 'speed', 'climb')).to eq 0
      end

      # Encumbered is written against every speed, so it reaches a granted one too.
      it "should let a condition reach a granted speed" do
        with_feat('Cave Climber')
        @char.update(:pf2_conditions => { 'Encumbered' => { 'status' => true } })

        expect(Pf2e::Stat.total(reread, 'speed', 'climb')).to eq 0
      end
    end

    # A trait is not decoration: a weapon that gains `thrown` adds Strength to its damage, and one that
    # gains `finesse` may be attacked with Dexterity.
    describe "a feat that adds a trait to an attack" do
      def fist
        Pf2eCombat.damage_descriptor(reread, 'Fist')
      end

      it "should add the trait the feat names" do
        @char.update(:pf2_feats => { 'charclass' => [ 'Quietus Strikes' ] })

        expect(Pf2eCombat.damage_descriptor(reread, 'Fist')['traits']).to include 'magical'
      end

      it "should add nothing for a character without the feat" do
        expect(Array(fist['traits'])).to_not include 'magical'
      end

      # The point of reading traits at all: one of them changes the arithmetic.
      it "should change the damage attribute when the trait is finesse" do
        @char.update(:pf2_base_info => { 'specialize' => 'Thief' })
        score('Strength', 10)
        score('Dexterity', 18)

        plain = Pf2e::Damage.formula(reread, fist)
        finessed = Pf2e::Damage.formula(reread, fist.merge('traits' => [ 'finesse' ]))

        expect(finessed).to_not eq plain
      end
    end

    # An attack the character would not otherwise have. Described the same way a catalogue weapon is, so
    # everything that reads an attack reads this one without knowing it came from a rule.
    describe "a feat that grants an attack" do
      before(:each) do
        @combat.update(:weapon_prof => { 'unarmed' => 'expert' })
      end

      def granted
        Pf2eCombat.granted_strikes(reread)
      end

      it "should grant none to a character with no such feat" do
        expect(granted).to eq []
      end

      it "should grant the attack the feat describes" do
        @char.update(:pf2_feats => { 'ancestry' => [ 'Hag Claws' ] })

        expect(granted.map { |one| one['name'] }.size).to be > 0
      end

      # Nine of the fourteen granted attacks are gated on a choice the player made, which is a ChoiceSet
      # and not a kind we read - so those grant nothing rather than granting unconditionally.
      it "should grant nothing whose circumstances it cannot establish" do
        @char.update(:pf2_feats => { 'ancestry' => [ 'Bestial Manifestation' ] })

        expect(granted).to eq []
      end

      it "should say what granted it" do
        @char.update(:pf2_feats => { 'ancestry' => [ 'Hag Claws' ] })

        expect(granted.first['source']).to eq 'Hag Claws'
      end

      # It goes through the same arithmetic, so it takes the character's proficiency and attribute.
      it "should have an attack bonus and a damage formula of its own" do
        @char.update(:pf2_feats => { 'ancestry' => [ 'Hag Claws' ] })
        strike = granted.first

        expect(Pf2e::Stat.total(reread, 'attack', strike)).to be > 0
        expect(Pf2eCombat.damage_breakdown(reread, strike['name'], nil, false, [], strike)['formula'])
          .to match(/d\d/)
      end

      # Frightened is a penalty to every check, and a granted attack is a check like any other.
      it "should take a penalty written against every check" do
        @char.update(:pf2_feats => { 'ancestry' => [ 'Hag Claws' ] })
        strike = granted.first
        before = Pf2e::Stat.total(reread, 'attack', strike)

        @char.update(:pf2_conditions => { 'Frightened' => { 'value' => 2, 'status' => true } })

        expect(Pf2e::Stat.total(reread, 'attack', strike)).to eq before - 2
      end

      # Unholy Plate's horns roll two dice rather than one, which a catalogue weapon never does.
      it "should roll as many dice as the rule says" do
        strike = { 'name' => 'Horns', 'prof' => 'expert', 'traits' => [], 'ranged' => false,
                   'unarmed' => false, 'bomb' => false, 'die' => 'd8', 'dice' => 2,
                   'damage_type' => 'piercing', 'striking' => 0, 'rune' => 0 }

        expect(Pf2e::Damage.formula(reread, strike)).to match(/\A2d8/)
      end
    end

    # Initiative is a Perception check that also answers to `initiative`, so a feat written against
    # initiative reaches it without anything here knowing the feat exists.
    describe "initiative" do
      it "should be the perception bonus when nothing modifies it" do
        expect(Pf2e.initiative_bonus(reread, 'Perception')).to eq Pf2eCombat.get_perception(reread)
      end

      it "should take a bonus written against initiative" do
        before = Pf2e.initiative_bonus(reread, 'Perception')

        expect(Pf2e.initiative_bonus(with_feat('Incredible Initiative'), 'Perception')).to eq before + 2
      end

      # The same feat reaches initiative rolled off a skill, because the domain is the same.
      it "should take it when initiative is rolled off a skill" do
        before = Pf2e.initiative_bonus(reread, 'Stealth')

        expect(Pf2e.initiative_bonus(with_feat('Incredible Initiative'), 'Stealth')).to eq before + 2
      end

      # A Perception check that is not initiative does not get it.
      it "should not leak into an ordinary perception check" do
        before = Pf2eCombat.get_perception(reread)

        expect(Pf2eCombat.get_perception(with_feat('Incredible Initiative'))).to eq before
      end

      it "should read an attribute when the scene runner names one" do
        expect(Pf2e.initiative_bonus(reread, 'Dexterity')).to eq 2
      end
    end
  end
end
