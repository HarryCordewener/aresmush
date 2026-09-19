require "plugin_test_loader"

module AresMUSH

  # The four kinds that finish the reading: a proficiency a feat grants over a kind of weapon, the
  # critical specialisation effect, a sense, and an alteration to a damage roll after it is built.
  describe "granted proficiencies, senses, crit spec and damage alterations", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Last#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char,
                                  :weapon_prof => { 'simple' => 'expert', 'martial' => 'trained',
                                                    'advanced' => 'untrained', 'unarmed' => 'master' })
      @char.update(:combat => @combat, :pf2_level => 10, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => {}, :pf2_feats => {}, :pf2_features => {},
                   :pf2_roll_options => {}, :pf2_derived => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      Array(@items).each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def with_feat(name, bucket = 'general')
      @char.update(:pf2_feats => { bucket => [ name ] })

      reread
    end

    def with_item(name)
      info = Global.read_config('pf2e_magicitem', name)
      item = Pf2egear.create_item(@char, 'magicitem', name, 1, info)
      item.update(:invested => true)
      @items = (@items || []) << item

      reread
    end

    # "Martial goblin weapons count as simple for you." The feat says which weapons and which
    # proficiency to copy, so nothing in the engine names the feat.
    describe "a proficiency a feat grants" do
      def goblin_martial
        { 'category' => 'martial', 'group' => 'axe', 'traits' => [ 'goblin' ] }
      end

      it "should copy the proficiency the feat names" do
        expect(Pf2eCombat.granted_weapon_prof(with_feat('Goblin Weapon Familiarity'), 'Dogslicer',
                                              goblin_martial)).to include 'expert'
      end

      it "should grant nothing to a character without the feat" do
        expect(Pf2eCombat.granted_weapon_prof(reread, 'Dogslicer', goblin_martial)).to eq []
      end

      it "should grant nothing over a weapon the definition does not describe" do
        plain = { 'category' => 'martial', 'group' => 'sword', 'traits' => [] }

        expect(Pf2eCombat.granted_weapon_prof(with_feat('Goblin Weapon Familiarity'), 'Longsword',
                                              plain)).to eq []
      end

      # Monastic Weaponry copies the unarmed proficiency but no higher than master.
      it "should go no higher than the feat's ceiling" do
        @combat.update(:weapon_prof => { 'unarmed' => 'legendary' })
        monk = { 'category' => 'martial', 'group' => 'sword', 'traits' => [ 'monk' ] }

        granted = Pf2eCombat.granted_weapon_prof(with_feat('Monastic Weaponry'), 'Temple Sword', monk)

        expect(granted).to eq [ 'master' ]
      end
    end

    # A sense is not a figure, but the sheet shows it and a predicate can ask about it.
    describe "a sense something granted" do
      it "should be none for a character with nothing that grants one" do
        expect(Pf2e::Effects.senses(reread)).to eq []
      end

      it "should be the sense the item or feat names" do
        senses = Pf2e::Effects.senses(with_item('Eyes of the Cat'))

        expect(senses.map { |one| one['name'] }).to include 'low-light-vision'
      end

      it "should say what granted it" do
        expect(Pf2e::Effects.senses(with_item('Eyes of the Cat')).first['source'])
          .to eq 'Eyes of the Cat'
      end

      # A sense with circumstances nobody has established is offered and not held: Moonlit Chain wants
      # moonlight, which is terrain this engine does not model.
      it "should not grant one whose circumstances are unmet" do
        expect(Pf2e::Effects.senses(with_item('Moonlit Chain'))).to eq []
      end

      it "should be a fact a predicate can ask about" do
        expect(Pf2e::Effects.facts(with_item('Eyes of the Cat')))
          .to include 'self:sense:low-light-vision'
      end
    end

    # The critical specialisation effect, said outright by a feat rather than inferred.
    describe "critical specialisation a feat grants" do
      def monk_weapon
        { 'category' => 'martial', 'group' => 'sword', 'traits' => [ 'monk' ] }
      end

      it "should apply when the feat's circumstances are met" do
        @char.update(:pf2_feats => { 'charclass' => [ 'Monastic Weaponry' ] },
                     :pf2_features => { 'charclass_features' => [ 'Expert Strikes' ] })

        expect(Pf2e.granted_crit_spec?(reread, 'Temple Sword', monk_weapon)).to be true
      end

      it "should not apply without the feature the feat wants" do
        @char.update(:pf2_feats => { 'charclass' => [ 'Monastic Weaponry' ] })

        expect(Pf2e.granted_crit_spec?(reread, 'Temple Sword', monk_weapon)).to be false
      end

      it "should not apply to a weapon the feat does not describe" do
        @char.update(:pf2_feats => { 'charclass' => [ 'Monastic Weaponry' ] },
                     :pf2_features => { 'charclass_features' => [ 'Expert Strikes' ] })
        plain = { 'category' => 'martial', 'group' => 'sword', 'traits' => [] }

        expect(Pf2e.granted_crit_spec?(reread, 'Longsword', plain)).to be false
      end
    end

    # An alteration changes a roll after it is built: the kind of damage, how many dice, how large.
    describe "an alteration to a damage roll" do
      def fist
        { 'name' => 'Fist', 'prof' => 'master', 'traits' => [], 'ranged' => false, 'unarmed' => true,
          'bomb' => false, 'die' => 'd4', 'damage_type' => 'B', 'striking' => 0, 'rune' => 0 }
      end

      def altered(rows)
        allow(Pf2e::Rules).to receive(:damage_alterations).and_return(rows)

        Pf2e::Damage.formula(reread, fist)
      end

      it "should change the kind of damage" do
        expect(altered([ { 'property' => 'damage-type', 'mode' => 'override', 'value' => 'fire' } ]))
          .to match(/fire/)
      end

      it "should multiply how many dice it rolls" do
        expect(altered([ { 'property' => 'dice-number', 'mode' => 'multiply', 'value' => 2 } ]))
          .to match(/\A2d4/)
      end

      # `dice-faces` with nothing to upgrade to means one step larger, which is Diamond Fists.
      it "should raise the die a step when it says to upgrade the faces" do
        expect(altered([ { 'property' => 'dice-faces', 'mode' => 'upgrade', 'value' => nil } ]))
          .to match(/\A1d6/)
      end

      it "should leave the roll alone when nothing alters it" do
        expect(altered([])).to eq Pf2e::Damage.formula(reread, fist)
      end
    end
  end
end
