require "plugin_test_loader"

module AresMUSH

  # What an effect does to a roll, and to the character's own things.
  #
  # `removeAfterRoll` spends a one-off bonus on the roll it helps; `RollTwice` is fortune and misfortune;
  # `Note` is what a roll should remind the player of; an owned-item choice is "the weapon you choose";
  # `ItemAlteration` changes one of the character's things while an effect lasts. None was read, and
  # each is Foundry's own semantics.
  describe "rolls and alterations", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Roll#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :perception => 'trained',
                                  :weapon_prof => { 'martial' => 'trained', 'simple' => 'trained' },
                                  :armor_prof => { 'unarmored' => 'trained', 'light' => 'trained',
                                                   'medium' => 'trained' },
                                  :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained',
                                              'Will' => 'trained' })
      @char.update(:combat => @combat, :pf2_level => 12, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_aliases => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @items = []
    end

    after(:each) do
      Pf2e::ActiveEffects.on(Character[@char.id]).each(&:delete)
      @items.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def apply(name, options = [])
      Pf2e::ActiveEffects.apply(reread, name, :options => options)
    end

    def under
      Pf2e::ActiveEffects.on(reread).map(&:name)
    end

    def carry(category, name)
      info = Global.read_config("pf2e_#{category}", name) || raise("no such #{category}: #{name}")
      item = Pf2egear.create_item(@char, category, name, 1, info)
      item.update(:equipped => true)
      @items << item

      item
    end

    # Guidance: +1 status bonus to one roll, spent on the roll it counted in (`if-enabled`).
    describe "a one-off bonus" do
      it "should count in the roll it helps, and be spent by it" do
        apply('guidance')
        plain = Pf2eCombat.get_perception(reread)

        rolled = Pf2e.parse_roll_string(reread, [ '1d1', 'perception' ], Pf2e.circumstances([ 'guidance' ]))

        # A one-sided die rolls one, so what is left is Perception and the bonus.
        expect(rolled['total']).to eq 1 + plain + 1
        expect(under).to eq []
      end

      it "should not be spent on a roll it did not count in" do
        apply('guidance')

        Pf2e.parse_roll_string(reread, [ '1d1', 'perception' ])

        expect(under).to eq [ 'Spell Effect: Guidance' ]
      end
    end

    describe "fortune and misfortune" do
      it "should roll a check twice and keep the higher" do
        apply('Bless Ally')

        expect(Pf2e::Check.of(reread, 'save', 'Will').roll_twice).to eq 'keep-higher'
      end

      it "should say both dice, and keep the one it says" do
        apply('Bless Ally')

        rolled = Pf2e.parse_roll_string(reread, [ 'will' ])

        expect(rolled['rolled_twice']['rolls'].size).to eq 2
        expect(rolled['result'].first).to include rolled['rolled_twice']['rolls'].max.to_s
      end

      # An effect's fortune is spent on the roll it made twice.
      it "should end the effect that gave it once it has been used" do
        apply('Bless Ally')

        Pf2e.parse_roll_string(reread, [ 'will' ])

        expect(under).to eq []
      end

      it "should leave another kind of check alone" do
        apply('Bless Ally')

        expect(Pf2e::Check.of(reread, 'save', 'Fortitude').roll_twice).to be_nil
      end

      # One of each cancels, which is the rule.
      it "should roll once where fortune and misfortune both apply" do
        apply('Bless Ally')
        apply('Albatross Curse (Failure)')

        expect(Pf2e::Check.of(reread, 'save', 'Will').roll_twice).to be_nil
      end
    end

    describe "a note on a roll" do
      def attack
        Pf2e::Check.of(reread, 'attack', Pf2eCombat.attack_descriptor(reread, carry('weapons', 'Longsword')))
      end

      # Bismuth Armor reminds the attacker what happens when they miss.
      it "should show for the outcome it names" do
        apply('Bismuth Armor')

        expect(attack.notes(Pf2e::Degree::FAILURE).map { |note| note['text'] }.join)
          .to include 'reflects toward the caster'
      end

      it "should not show for another outcome" do
        apply('Bismuth Armor')

        expect(attack.notes(Pf2e::Degree::SUCCESS)).to eq []
      end
    end

    # Clay Sphere: the weapon you choose gains the versatile traits.
    describe "the weapon you choose" do
      it "should find the weapon by the name the player typed" do
        sword = carry('weapons', 'Longsword')

        effect = apply('Clay Sphere - Weapon', [ 'longsword' ]).state

        expect(effect.answers).to eq [ sword.id.to_s ]
      end

      it "should change that weapon" do
        sword = carry('weapons', 'Longsword')
        apply('Clay Sphere - Weapon', [ 'longsword' ])

        expect(Pf2eCombat.attack_descriptor(reread, sword)['traits']).to include 'versatile-b'
      end

      it "should leave another weapon alone" do
        carry('weapons', 'Longsword')
        dagger = carry('weapons', 'Dagger')
        apply('Clay Sphere - Weapon', [ 'longsword' ])

        expect(Pf2eCombat.attack_descriptor(reread, dagger)['traits']).to_not include 'versatile-b'
      end

      # Azarim makes the weapon chosen a +2 weapon from 11th level, as a potency rune.
      it "should give the weapon chosen the rune the effect says" do
        sword = carry('weapons', 'Longsword')
        apply('Azarim', [ 'longsword' ])

        expect(Pf2eCombat.attack_descriptor(reread, sword)['rune']).to eq 2
      end

      it "should stop changing it when the effect ends" do
        sword = carry('weapons', 'Longsword')
        apply('Azarim', [ 'longsword' ])
        Pf2e::ActiveEffects.remove_named(reread, 'Azarim')

        expect(Pf2eCombat.attack_descriptor(reread, sword)['rune']).to eq 0
      end
    end

    # Forgefather's Seal hardens light and medium armour by one.
    describe "armour an effect changes" do
      it "should raise the armour's AC while it lasts" do
        carry('armor', 'Chain Shirt')
        plain = Pf2e::Stat.total(reread, 'ac')

        apply("Forgefather's Seal")

        expect(Pf2e::Stat.total(reread, 'ac')).to eq plain + 1
      end

      it "should not reach armour it is not about" do
        @combat.update(:armor_prof => @combat.armor_prof.merge('heavy' => 'trained'))
        carry('armor', 'Full Plate')
        plain = Pf2e::Stat.total(reread, 'ac')

        apply("Forgefather's Seal")

        expect(Pf2e::Stat.total(reread, 'ac')).to eq plain
      end
    end
  end
end
