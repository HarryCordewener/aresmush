require "plugin_test_loader"

module AresMUSH

  # A condition that brings another with it.
  #
  # Grabbed makes you off-guard; Dying makes you unconscious, which blinds you and puts you on the
  # ground; Encumbered makes you clumsy. Foundry writes each as a `GrantItem`, and none were read, so a
  # grabbed character kept their full AC. What becomes of the granted condition when its granter goes
  # is the grant's own to say (`Pf2e::Grants`), and these specs hold the three answers it gives.
  describe "conditions that grant conditions", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Grant#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
    end

    after(:each) do
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def held
      Pf2e.held_conditions(reread)
    end

    def stored
      reread.pf2_conditions.keys
    end

    # Foundry's `inMemoryOnly`: a consequence rather than a condition anybody gave you.
    describe "one that exists only while its granter does" do
      it "should make a grabbed character off-guard" do
        Pf2e.set_condition(reread, 'Grabbed')

        expect(held.keys).to include 'Off-Guard', 'Immobilized'
      end

      it "should lower their AC, since Off-Guard's own rule is what does that" do
        plain = Pf2e::Stat.total(reread, 'ac')

        Pf2e.set_condition(reread, 'Grabbed')

        expect(Pf2e::Stat.total(reread, 'ac')).to eq plain - 2
      end

      it "should never be stored" do
        Pf2e.set_condition(reread, 'Grabbed')

        expect(stored).to eq [ 'Grabbed' ]
      end

      it "should go when its granter goes" do
        Pf2e.set_condition(reread, 'Grabbed')
        Pf2e.remove_condition(reread, 'Grabbed')

        expect(held.keys).to eq []
      end

      it "should say what brought it" do
        Pf2e.set_condition(reread, 'Grabbed')

        expect(held['Off-Guard']['granted_by']).to eq 'Grabbed'
      end

      # Encumbered's clumsy is clumsy 1, and a valued condition carries its value to the arithmetic.
      it "should give a valued condition its value" do
        Pf2e.set_condition(reread, 'Encumbered')

        expect(Pf2e.condition_level(reread, 'Clumsy')).to eq 1
      end

      # Being off-guard for a reason of your own does not stop when the grab does.
      it "should not displace one held in its own right" do
        Pf2e.set_condition(reread, 'Off-Guard')
        Pf2e.set_condition(reread, 'Grabbed')
        Pf2e.remove_condition(reread, 'Grabbed')

        expect(held.keys).to eq [ 'Off-Guard' ]
      end

      it "should make the fact available to a predicate" do
        Pf2e.set_condition(reread, 'Grabbed')

        expect(Pf2e::Effects.facts(reread)).to include 'self:condition:off-guard'
      end
    end

    # Stored in its own right, with the grant saying what happens next.
    describe "one stored in its own right" do
      it "should make a dying character unconscious, blind and prone" do
        Pf2e.set_condition(reread, 'Dying', 1)

        expect(stored).to include 'Dying', 'Unconscious', 'Blinded', 'Prone'
      end

      # `grantee: restrict` - nobody clears Unconscious off a character who is still dying.
      it "should refuse to clear one its granter holds in place" do
        Pf2e.set_condition(reread, 'Dying', 1)

        outcome = Pf2e.remove_condition(reread, 'Unconscious')

        expect(outcome.err?).to be true
        expect(outcome.code).to eq :restricted
        expect(stored).to include 'Unconscious'
      end

      # The default: a granted condition goes with its granter. Waking up ends the blindness.
      it "should go with its granter by default" do
        Pf2e.set_condition(reread, 'Dying', 1)
        Pf2e.remove_condition(reread, 'Dying')

        expect(stored).to_not include 'Unconscious', 'Blinded'
      end

      # `granter: detach` - you wake up still on the ground.
      it "should stay behind when the grant says to" do
        Pf2e.set_condition(reread, 'Dying', 1)
        Pf2e.remove_condition(reread, 'Dying')

        expect(stored).to eq [ 'Prone' ]
      end

      it "should forget what brought it once it stays behind, so it can be cleared like any other" do
        Pf2e.set_condition(reread, 'Dying', 1)
        Pf2e.remove_condition(reread, 'Dying')

        expect(Pf2e.remove_condition(reread, 'Prone').ok?).to be true
        expect(stored).to eq []
      end

      # Someone prone before they fell unconscious is not stood up by waking.
      it "should not claim one the character already had" do
        Pf2e.set_condition(reread, 'Prone')
        Pf2e.set_condition(reread, 'Unconscious')
        Pf2e.remove_condition(reread, 'Unconscious')

        expect(stored).to eq [ 'Prone' ]
      end
    end

    # The whole chain through the rules as a player meets it.
    describe "being dropped and healed" do
      before(:each) do
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
      end

      after(:each) { @hp&.delete }

      it "should leave a healed character wounded and prone, and nothing else" do
        Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(reread), false, true)
        Pf2eHP.modify_damage(reread, 5, true)

        expect(stored.sort).to eq %w{Prone Wounded}
      end
    end

    it "should match a condition however the player spells it" do
      Pf2e.set_condition(reread, 'off-guard')

      expect(stored).to eq [ 'Off-Guard' ]
    end
  end
end
