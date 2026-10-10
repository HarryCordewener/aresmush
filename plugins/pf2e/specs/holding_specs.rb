require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Who holds whom. A creature that grabs someone holds them, and what the rules hang on that follows
    # the holder: only its own failed Grapple lets go, it lets go when it drops, it tightens its grip
    # without a roll, and it crushes only those it holds. Whoever is held cannot walk away.
    describe "holding and being held", :dbtest => true do

      class HoldingClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }

        def screen_reader
          false
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = HoldingClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' },
                                    :unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B', 'group' => 'Brawling',
                                                                      'traits' => %w{agile finesse nonlethal unarmed} } })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [], :pf2_baseinfo_locked => true,
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @scene.participants.add @hero

        # Every die shows three quarters of its faces: a d20 is 15, a d4 is 3. The hero's fist deals 3 + 2.
        @dice = 0.75
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }

        run(PF2InitiateCombatCmd, 'encounter')
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}", @hero)
        @client.said.clear
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.delete
        end
        (@abilities + [ @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def encounter
        PF2Encounter.scene_active_encounter(Scene[@scene.id])
      end

      def npc(number = 2)
        encounter.npcs.to_a.find { |one| one.number == number }
      end

      def heard
        @client.said.join("\n")
      end

      def hero
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def held
        hero.pf2_conditions || {}
      end

      def as(number, text, dice = 0.95)
        @dice = dice
        @client.said.clear
        run(PF2EncounterAsCmd, "e/as ##{number}=#{text}")
      end

      def hero_types(cmd_class, text, dice = 0.95)
        @dice = dice
        @client.said.clear
        @client.failures.clear
        run(cmd_class, text, @hero)
      end

      # The dice a scene needs: a 12 hits without a critical hit, a 10 grabs without restraining.
      HITS = 0.6
      GRABS = 0.5

      # The python bites and grabs.
      def grabbed!(number = 2)
        as(number, "strike #{@hero.name}", HITS)
        as(number, "act grab=#{@hero.name}", GRABS)
      end

      before(:each) do
        run(PF2EncounterAddCmd, 'e/add 2 python')
        run(PF2EncounterNextCmd, 'e/next')
        @client.said.clear
      end

      describe "a Grab" do
        it "should need a hit with a Strike that lists it, as the action before" do
          as(2, "act grab=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.follow_up_needs_hit', :action => 'Grab', :actor => 'Python #2') ]
          expect(held).to_not have_key('Grabbed')
        end

        it "should not follow a Strike that missed" do
          as(2, "strike #{@hero.name}", 0.05)
          as(2, "act grab=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.follow_up_needs_hit', :action => 'Grab', :actor => 'Python #2') ]
        end

        it "should hold whoever it grabs, and say who holds them" do
          grabbed!

          expect(held['Grabbed']['by']).to eq 'Python #2'
          expect(Pf2e.condition_labels(hero, false)).to include('Grabbed (by Python #2)')
        end

        it "should not let go for another creature's failed Grab" do
          grabbed!
          as(3, "strike #{@hero.name}", HITS)
          as(3, "act grab=#{@hero.name}", 0.05)

          expect(held['Grabbed']['by']).to eq 'Python #2'
        end

        it "should let go for its own failed Grapple" do
          grabbed!
          as(2, "act grapple=#{@hero.name}", 0.05)

          expect(held).to_not have_key('Grabbed')
        end

        it "should tighten on someone it already holds without a roll, to the end of its next turn" do
          grabbed!
          was = held['Grabbed']['expires']
          run(PF2EncounterNextCmd, 'e/next')
          run(PF2EncounterNextCmd, 'e/next')
          run(PF2EncounterNextCmd, 'e/next')
          as(2, "act grab=#{@hero.name}", 0.05)

          expect(@client.failures).to eq []
          expect(heard).to include(t('pf2e.hold_extended', :actor => 'Python #2', :target => @hero.name).strip)
          expect(heard).to_not include('Athletics')
          expect(held['Grabbed']['expires']['round']).to eq was['round'] + 1
        end

        it "should let go when the holder drops" do
          grabbed!
          @client.said.clear
          run(PF2DamagePlayerCmd, "damage #2=#{npc(2).hp_left}")

          expect(held).to_not have_key('Grabbed')
          expect(heard).to include(t('pf2e.hold_released', :target => @hero.name, :actor => 'Python #2').strip)
        end

        it "should let go when the holder is taken out of the fight" do
          grabbed!
          run(PF2EncounterRemoveCmd, 'encounter/remove #2')

          expect(held).to_not have_key('Grabbed')
        end
      end

      describe "a Knockdown" do
        before(:each) { run(PF2EncounterAddCmd, 'e/add wolf') }

        it "should need a hit with a Strike that lists it" do
          as(4, "act knockdown=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.follow_up_needs_hit', :action => 'Knockdown', :actor => 'Wolf #4') ]
        end

        it "should trip after one" do
          as(4, "strike #{@hero.name}", HITS)
          as(4, "act knockdown=#{@hero.name}")

          expect(@client.failures).to eq []
          expect(held).to have_key('Prone')
        end
      end

      describe "Constrict" do
        it "should crush everyone the creature holds when no one is named" do
          grabbed!
          before = Pf2eHP.get_current_hp(hero)
          as(2, 'act constrict')

          expect(@client.failures).to eq []
          expect(Pf2eHP.get_current_hp(hero)).to be < before
        end

        it "should not crush someone it does not hold" do
          before = Pf2eHP.get_current_hp(hero)
          as(2, "act constrict=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.hold_none', :actor => 'Python #2', :action => 'Constrict') ]
          expect(Pf2eHP.get_current_hp(hero)).to eq before
        end

        it "should not crush someone another creature holds" do
          grabbed!(3)
          as(2, "act constrict=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.hold_none', :actor => 'Python #2', :action => 'Constrict') ]
        end
      end

      describe "someone who is grabbed" do
        before(:each) { grabbed! }

        it "should not be able to move" do
          hero_types(PF2EncounterActCmd, 'e/act stride')

          expect(@client.failures).to eq [ t('pf2e.act_immobilized', :actor => @hero.name, :action => 'Stride') ]
        end

        it "should lose an action that takes their hands on a flat check of 4 or less" do
          hero_types(PF2EncounterActCmd, 'e/act interact', 0.2)

          expect(heard).to include(t('pf2e.act_grabbed_lost', :actor => @hero.name, :action => 'Interact', :die => 4).strip)
          expect(TurnState.turn(hero)['actions']).to eq 1
        end

        it "should keep an action that takes their hands on a flat check of 5 or more" do
          hero_types(PF2EncounterActCmd, 'e/act interact', 0.25)

          expect(heard).to include(t('pf2e.act_grabbed_kept', :actor => @hero.name, :die => 5).strip)
          expect(heard).to include('uses Interact')
        end

        it "should still be able to Strike" do
          hero_types(PF2EncounterStrikeCmd, 'e/strike #2=fist')

          expect(@client.failures).to eq []
        end

        it "should Escape from whoever holds them without naming it" do
          hero_types(PF2EncounterActCmd, 'e/act escape', 1.0)

          expect(@client.failures).to eq []
          expect(heard).to include('Python #2')
          expect(held).to_not have_key('Grabbed')
        end
      end

      describe "someone who is restrained" do
        before(:each) do
          as(2, "strike #{@hero.name}", HITS)
          as(2, "act grab=#{@hero.name}", 1.0)
        end

        it "should be restrained by a critical Grab" do
          expect(held['Restrained']['by']).to eq 'Python #2'
        end

        it "should not be able to Strike" do
          hero_types(PF2EncounterStrikeCmd, 'e/strike #2=fist')

          expect(@client.failures).to eq [ t('pf2e.act_restrained', :actor => @hero.name, :action => 'Strike') ]
        end

        it "should still be able to Escape" do
          hero_types(PF2EncounterActCmd, 'e/act escape', 1.0)

          expect(@client.failures).to eq []
          expect(held).to_not have_key('Restrained')
        end
      end

      # A doru casts Charm, which takes its hands (manipulate).
      describe "a caster who is held" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add doru')
          @hero.update(:pf2_level => 5)
        end

        def doru
          Combatants.find(encounter, '#4').state
        end

        it "should lose a spell on a failed flat check when grabbed, and keep it on a passed one" do
          Pf2e.set_condition(npc(4), 'Grabbed')

          as(4, "cast charm=#{@hero.name}", 0.2)
          expect(heard).to include(t('pf2e.act_grabbed_lost', :actor => 'Doru #4', :action => 'Charm', :die => 4).strip)
          expect(heard).to_not include('casts Charm')

          as(4, "cast charm=#{@hero.name}", 0.5)
          expect(heard).to include('casts Charm')
        end

        it "should not cast at all when restrained" do
          Pf2e.set_condition(npc(4), 'Restrained')

          as(4, "cast charm=#{@hero.name}")

          expect(@client.failures).to eq [ t('pf2e.act_restrained', :actor => 'Doru #4', :action => 'Charm') ]
        end
      end

      describe "someone nothing holds" do
        it "should have nothing to Escape from" do
          hero_types(PF2EncounterActCmd, 'e/act escape')

          expect(@client.failures).to eq [ t('pf2e.escape_nothing') ]
        end
      end
    end
  end
end
