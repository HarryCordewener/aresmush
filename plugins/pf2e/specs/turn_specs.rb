require "plugin_test_loader"

module AresMUSH

  # What happens as a turn starts or ends: fast healing, persistent damage, and a sustained effect
  # nobody sustained. Each is answered as an event rather than told to anyone, so whoever tells the room
  # decides how.
  describe "turns", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Turn#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @char.update(:combat => @combat, :hp => @hp, :pf2_level => 10, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {}, :pf2_persistent => [],
                   :pf2_turn_state => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
      }
      @fight = PF2Encounter.create(:participants => [ [ 20.0, @char.name ], [ 10.0, 'Goblin' ] ],
                                   :round => 1, :next_init => 1, :organizer => 'Staff')
    end

    after(:each) do
      Pf2e::ActiveEffects.on(Character[@char.id]).each(&:delete)
      @fight&.delete
      @abilities.each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def damage
      Pf2eHP[@hp.id].damage
    end

    def hurt(amount, kind = nil)
      Pf2eHP.modify_damage(reread, amount, false, true, kind)
    end

    def starts
      Pf2e::Turns.turn_started(@fight, @char.name, @fight.round)
    end

    def ends
      Pf2e::Turns.turn_ended(@fight, @char.name, @fight.round)
    end

    describe "fast healing" do
      it "should heal as the character's turn starts" do
        hurt(30)
        Pf2e::ActiveEffects.apply(reread, 'Call Upon the Ancient Life', :encounter => @fight)

        events = starts

        expect(damage).to eq 15
        expect(events.map { |one| one['key'] }).to include 'pf2e.fast_healing'
      end

      it "should read a formula over the character" do
        hurt(30)
        Pf2e::ActiveEffects.apply(reread, 'Crimson Shroud', :encounter => @fight)

        starts

        expect(damage).to eq 30 - 5
      end

      it "should not heal on someone else's turn" do
        hurt(30)
        Pf2e::ActiveEffects.apply(reread, 'Call Upon the Ancient Life', :encounter => @fight)

        Pf2e::Turns.turn_started(@fight, 'Goblin', 1)

        expect(damage).to eq 30
      end
    end

    describe "persistent damage" do
      it "should be dealt as the character's turn ends" do
        Pf2e::PersistentDamage.add(reread, '5', 'fire')

        ends

        expect(damage).to eq 5
      end

      it "should say the character has it" do
        Pf2e::PersistentDamage.add(reread, '5', 'fire')

        expect(Pf2e.held_conditions(reread).keys).to include 'Persistent'
      end

      # The same kind does not stack; the higher applies.
      it "should keep the worse of two of the same kind" do
        Pf2e::PersistentDamage.add(reread, '2', 'fire')
        Pf2e::PersistentDamage.add(reread, '6', 'fire')
        Pf2e::PersistentDamage.add(reread, '1', 'fire')

        expect(Pf2e::PersistentDamage.held(reread).map { |one| one['formula'] }).to eq [ '6' ]
      end

      it "should keep two of different kinds apart" do
        Pf2e::PersistentDamage.add(reread, '2', 'fire')
        Pf2e::PersistentDamage.add(reread, '2', 'bleed')

        expect(Pf2e::PersistentDamage.held(reread).size).to eq 2
      end

      # A flat check against its DC ends it: an impossible DC never does, a trivial one always does.
      it "should end on a flat check that makes its DC" do
        Pf2e::PersistentDamage.add(reread, '1', 'fire', 1)

        events = ends

        expect(Pf2e::PersistentDamage.held(reread)).to eq []
        expect(events.map { |one| one['key'] }).to include 'pf2e.persistent_ended'
        expect(Pf2e.held_conditions(reread).keys).to_not include 'Persistent'
      end

      it "should go on when the flat check fails" do
        Pf2e::PersistentDamage.add(reread, '1', 'fire', 21)

        ends

        expect(Pf2e::PersistentDamage.held(reread).size).to eq 1
      end

      # Resistance to the kind reduces it, like any damage of that kind. Forgefather's Seal resists fire.
      it "should be resisted like any damage of its kind" do
        Pf2e::ActiveEffects.apply(reread, "Forgefather's Seal")
        Pf2e::PersistentDamage.add(reread, '5', 'fire')

        ends

        expect(damage).to eq 0
      end
    end

    describe "a sustained effect" do
      let(:sustained) { 'Effect: Alloy Flesh and Steel' }

      it "should end at the end of the caster's next turn unless it is sustained" do
        Pf2e::ActiveEffects.apply(reread, sustained, :encounter => @fight)

        ends
        expect(Pf2e::ActiveEffects.on(reread).size).to eq 1

        @fight.update(:round => 2)
        ends

        expect(Pf2e::ActiveEffects.on(reread)).to eq []
      end

      it "should go on when it is sustained" do
        effect = Pf2e::ActiveEffects.apply(reread, sustained, :encounter => @fight).state

        @fight.update(:round => 2)
        Pf2e::ActiveEffects.sustain(effect, @fight)
        ends

        expect(Pf2e::ActiveEffects.on(reread).size).to eq 1
      end
    end
  end
end
