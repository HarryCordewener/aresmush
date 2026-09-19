require "plugin_test_loader"

module AresMUSH

  # Size, auras and battle forms: what an effect makes of the character's body, and what it puts on the
  # people around them. Each is Foundry's own rule, read with no command yet to drive it.
  describe "forms, size and auras", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @chars = []
      @char = person("Form")
      @items = []
    end

    after(:each) do
      @chars.each do |char|
        Pf2e::ActiveEffects.on(Character[char.id]).each(&:delete)
        [ char.combat, char.hp ].compact.each(&:delete)
        char.abilities.each(&:delete)
        char.delete
      end
      @items.each(&:delete)
    end

    def person(prefix)
      char = Character.create(:name => "#{prefix}#{rand(1000000)}")
      combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                 :unarmed_prof => 'trained', :weapon_prof => { 'unarmed' => 'trained' })
      hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 10)
      char.update(:combat => combat, :hp => hp, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                  :pf2_derived => {}, :pf2_feats => {}, :pf2_movement => { 'Size' => 'M', 'base_speed' => 25 })
      Pf2e::ABILITIES.each { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => 12) }
      @chars << char

      Character[char.id]
    end

    def reread(char = @char)
      Character[char.id]
    end

    def apply(name, options = [], char = @char)
      Pf2e::ActiveEffects.apply(reread(char), name, :options => options).state
    end

    describe "size" do
      it "should be the ancestry's until something changes it" do
        expect(Pf2e::Size.of(reread)).to eq('size' => 'med', 'reach' => 5)
      end

      # Shrinking Potion makes you tiny, and a tiny creature reaches nothing.
      it "should be what an effect names" do
        apply('Shrinking Potion')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'tiny', 'reach' => 0)
      end

      # Applereed Mutagen makes you one size larger, and says your reach does not change with it.
      it "should step up one size, and keep reach where the rule says" do
        apply('Applereed Mutagen (Lesser)')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'lg', 'reach' => 5)
      end

      # Bone Swarm makes you huge and says nothing of reach, so reach grows with the size.
      it "should grow reach with the size where the rule says nothing of it" do
        apply('Bone Swarm')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'huge', 'reach' => 15)
      end

      it "should be something a predicate can ask about" do
        apply('Shrinking Potion')

        expect(Pf2e::Effects.facts(reread)).to include 'self:size:tiny', 'self:size:0'
      end
    end

    # Animal Form (Bear) at 2nd rank: AC 16 + level, attacks at +9, a land speed of 30 feet and scent.
    describe "a battle form" do
      before(:each) { apply('Animal Form (Bear)', [ 'rank 2' ]) }

      it "should be the form the character is in" do
        expect(Pf2e::BattleForms.active?(reread)).to be true
      end

      it "should give the form's AC, since AC does not keep the character's own" do
        expect(Pf2e::Stat.total(reread, 'ac')).to eq 16 + 5
      end

      it "should keep a status penalty on top of it" do
        Pf2e.set_condition(reread, 'Frightened', 2)

        expect(Pf2e::Stat.total(reread, 'ac')).to eq 16 + 5 - 2
      end

      it "should give the form's attacks, at the form's modifier where it is better" do
        claw = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'claw' }

        expect(Pf2e::Stat.total(reread, 'attack', claw)).to eq 9
      end

      it "should roll the form's damage with the form's own modifier" do
        claw = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'claw' }

        expect(Pf2e::Damage.formula(reread, claw)).to start_with '1d8+1'
      end

      it "should replace the character's speeds" do
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 30
      end

      it "should give its senses through the ordinary rule" do
        expect(Pf2e::Effects.senses(reread).map { |one| one['name'] }).to include 'scent', 'low-light-vision'
      end

      it "should say the character is polymorphed" do
        expect(Pf2e::Effects.options(reread)).to include 'polymorph', 'battle-form'
      end

      it "should give its temporary hit points" do
        expect(reread.hp.temp_hp).to eq 5
      end

      it "should be over when the effect is" do
        Pf2e::ActiveEffects.remove_named(reread, 'Animal Form (Bear)')

        expect(Pf2e::BattleForms.active?(reread)).to be false
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 25
      end
    end

    # Angelic Halo puts its effect on allies inside it.
    describe "an aura" do
      before(:each) do
        @ally = person("Ally")
        @foe = person("Foe")
        apply('Angelic Halo')
      end

      def halo
        Pf2e::Auras.of(reread).first
      end

      it "should say what it projects" do
        expect(halo['radius']).to eq 15
        expect(halo['effects'].map { |one| one['name'] }).to eq [ 'Spell Effect: Angelic Halo' ]
      end

      it "should put its effect on an ally inside it" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')

        expect(Pf2e::ActiveEffects.on(reread(@ally)).map(&:name)).to eq [ 'Spell Effect: Angelic Halo' ]
      end

      it "should not put it on an enemy, whom it does not affect" do
        Pf2e::Auras.enter(reread, reread(@foe), halo['slug'], 'enemy')

        expect(Pf2e::ActiveEffects.on(reread(@foe))).to eq []
      end

      it "should not put it on anyone twice" do
        2.times { Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally') }

        expect(Pf2e::ActiveEffects.on(reread(@ally)).size).to eq 1
      end

      it "should take it away when they leave" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')
        Pf2e::Auras.leave(reread, reread(@ally), halo['slug'])

        expect(Pf2e::ActiveEffects.on(reread(@ally))).to eq []
      end

      it "should take it from everyone when the aura ends" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')
        Pf2e::ActiveEffects.remove_named(reread, 'Angelic Halo')

        expect(Pf2e::ActiveEffects.on(reread(@ally))).to eq []
      end
    end
  end
end
