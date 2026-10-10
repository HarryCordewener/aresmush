require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Who runs an encounter decides how far it may go. Any approved character runs one, as an event
    # runner: with the creatures of Monster Core and Monster Core 2, and without leaving a character
    # Drained, Doomed or dead. A Plotmaster - the `kill_pc` permission - and staff run one with any
    # creature, one of their own making among them, and it may do all three.
    describe "who runs an encounter", :dbtest => true do

      class GmKindClient
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

        @client = GmKindClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @runner = Character.create(:name => "Runner#{rand(1000000)}", :room => @room)
        @plotmaster = Character.create(:name => "Plot#{rand(1000000)}", :room => @room)
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

        # Every die shows its highest face: a Strike is a critical hit, and a recovery check is passed
        # unless a spec says otherwise.
        @dice = 1.0
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @plotmaster.name }
      end

      after(:each) do
        PF2Encounter.find(:scene_id => @scene.id).each do |one|
          one.npcs.each(&:delete)
          one.delete
        end
        (@abilities + [ @hp, @combat, @hero, @runner, @plotmaster, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def encounter
        PF2Encounter.scene_active_encounter(Scene[@scene.id])
      end

      def hero
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def npc(number)
        encounter.npcs.to_a.find { |one| one.number == number }
      end

      # A fight run by the GM named, with the hero in it.
      def fight(gm)
        run(PF2InitiateCombatCmd, 'encounter', gm)
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}", @hero)
        @client.failures.clear
        @client.said.clear
      end

      def heard
        @client.said.join("\n")
      end

      describe "starting one" do
        it "should let any approved character start an encounter" do
          run(PF2InitiateCombatCmd, 'encounter', @hero)

          expect(@client.failures).to eq []
          expect(encounter.organizer).to eq @hero.name
        end

        it "should let any approved character start an exploration" do
          run(PF2ExploreCmd, 'e/explore', @hero)

          expect(@client.failures).to eq []
          expect(Exploration.exploring?(encounter)).to be true
        end

        it "should refuse a character who is not approved" do
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(false)

          run(PF2ExploreCmd, 'e/explore', @hero)

          expect(encounter).to be_nil
        end
      end

      describe "the kind of GM" do
        it "should be an event runner's for anyone" do
          expect(Gm.kind(Character[@runner.id])).to eq 'event runner'
        end

        it "should be a Plotmaster's with the right to kill a character" do
          expect(Gm.kind(Character[@plotmaster.id])).to eq 'Plotmaster'
        end

        it "should be staff's for an admin" do
          allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

          expect(Gm.kind(Character[@runner.id])).to eq 'staff'
        end
      end

      describe "the creatures an event runner adds" do
        before(:each) { fight(@runner) }

        it "should include Monster Core's" do
          run(PF2EncounterAddCmd, 'e/add goblin warrior', @runner)

          expect(@client.failures).to eq []
          expect(npc(2).name).to start_with 'Goblin Warrior'
        end

        it "should include Monster Core 2's" do
          run(PF2EncounterAddCmd, 'e/add ravener', @runner)

          expect(@client.failures).to eq []
        end

        it "should leave out any other book's" do
          run(PF2EncounterAddCmd, 'e/add guard', @runner)

          expect(@client.failures).to eq [ t('pf2e.creature_not_open', :creature => 'Guard') ]
          expect(encounter.npcs.to_a).to eq []
        end

        it "should leave out one of their own making" do
          run(PF2EncounterAddCmd, 'e/add Bandit=ac 16 fort 5 ref 7 will 3 perception 2 hp 20', @runner)

          expect(@client.failures).to eq [ t('pf2e.creature_custom_not_open') ]
          expect(encounter.npcs.to_a).to eq []
        end

        it "should be all a search of the bestiary shows them" do
          run(PF2EncounterBestiaryCmd, 'e/bestiary abbot of abadar', @runner)

          expect(@client.failures).to eq [ t('pf2e.creature_not_found', :creature => 'abbot of abadar') ]
        end
      end

      describe "the creatures a Plotmaster adds" do
        before(:each) { fight(@plotmaster) }

        it "should include any book's" do
          run(PF2EncounterAddCmd, 'e/add guard', @plotmaster)

          expect(@client.failures).to eq []
          expect(npc(2).name).to start_with 'Guard'
        end

        it "should include one of their own making" do
          run(PF2EncounterAddCmd, 'e/add Bandit=ac 16 fort 5 ref 7 will 3 perception 2 hp 20', @plotmaster)

          expect(@client.failures).to eq []
          expect(npc(2).name).to start_with 'Bandit'
        end

        it "should be found by a search of the bestiary" do
          run(PF2EncounterBestiaryCmd, 'e/bestiary abbot of abadar', @plotmaster)

          expect(heard).to start_with 'Abbot of Abadar'
        end
      end

      describe "Drained and Doomed" do
        it "should not be an event runner's to give a character" do
          fight(@runner)

          %w{Drained Doomed}.each do |condition|
            run(PF2ConditionSetCmd, "condition/set #{@hero.name}=#{condition}/1", @runner)

            expect(@client.failures.pop).to eq t('pf2e.condition_not_lasting', :condition => condition)
            expect(hero.pf2_conditions).to_not have_key(condition)
          end
        end

        it "should leave an event runner any other condition to give" do
          fight(@runner)

          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=Frightened/1", @runner)

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(hero, 'Frightened')).to eq 1
        end

        it "should be an event runner's to give a creature" do
          fight(@runner)
          run(PF2EncounterAddCmd, 'e/add goblin warrior', @runner)

          run(PF2ConditionSetCmd, 'condition/set #2=Drained/1', @runner)

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(npc(2), 'Drained')).to eq 1
        end

        it "should be an event runner's to take off a character" do
          fight(@runner)
          Pf2e.set_condition(hero, 'Doomed', 2)

          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=Doomed/1", @runner)

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(hero, 'Doomed')).to eq 1
        end

        it "should be a Plotmaster's to give a character" do
          fight(@plotmaster)

          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=Doomed/1", @plotmaster)

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(hero, 'Doomed')).to eq 1
        end

        # What an action does to its target is the encounter's to allow, whoever typed it.
        describe "from what happens in the fight" do
          def drained_by(gm, actor, target)
            fight(gm)
            run(PF2EncounterAddCmd, 'e/add goblin warrior', gm)
            scene = Acting::Scene.new(encounter, actor.call, target.call, Character[gm.id], true)
            out = Acting.report

            Acting.consequences(scene, [ { 'condition' => 'Drained', 'value' => 1, 'on' => 'target' } ], out)

            Telling.lines(out['lines']).join("\n")
          end

          def goblin
            Combatants.find(encounter, '#2').state
          end

          def aria
            Combatants.find(encounter, @hero.name).state
          end

          it "should pass a character by in an event runner's encounter, and say so" do
            told = drained_by(@runner, method(:goblin), method(:aria))

            expect(hero.pf2_conditions).to_not have_key('Drained')
            expect(told).to include(t('pf2e.act_not_lasting', :target => @hero.name, :condition => 'Drained').strip)
          end

          it "should land on a character in a Plotmaster's" do
            drained_by(@plotmaster, method(:goblin), method(:aria))

            expect(Pf2e.condition_level(hero, 'Drained')).to eq 1
          end

          it "should land on a creature in an event runner's" do
            drained_by(@runner, method(:aria), method(:goblin))

            expect(Pf2e.condition_level(npc(2), 'Drained')).to eq 1
          end

          it "should land on a character who does it to themselves" do
            drained_by(@runner, method(:aria), method(:aria))

            expect(Pf2e.condition_level(hero, 'Drained')).to eq 1
          end
        end
      end

      describe "death" do
        # One hit from death: no hit points left, Dying 3.
        def at_deaths_door
          hero.update(:damage => Pf2eHP.get_max_hp(hero))
          Pf2e.set_condition(hero, 'Dying', 3)
          @client.said.clear
        end

        def struck(gm)
          run(PF2EncounterAddCmd, 'e/add goblin warrior', gm)
          at_deaths_door
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}", gm)
        end

        describe "in an event runner's encounter" do
          before(:each) { fight(@runner) }

          it "should be unconsciousness when a hit would kill" do
            struck(@runner)

            expect(hero.pf2_is_dead).to be_falsey
            expect(Pf2e.condition_level(hero, 'Dying')).to eq 0
            expect(hero.pf2_conditions).to have_key('Unconscious')
            expect(heard).to include(t('pf2e.act_spared', :target => @hero.name).strip)
          end

          it "should be unconsciousness when a failed recovery check would kill" do
            at_deaths_door
            @dice = 0.25

            told = Turns.recovery(hero).map { |one| one['key'] }

            expect(told).to include('pf2e.recovery_spared')
            expect(hero.pf2_is_dead).to be_falsey
            expect(Pf2e.condition_level(hero, 'Dying')).to eq 0
            expect(hero.pf2_conditions).to have_key('Unconscious')
          end

          it "should be unconsciousness when persistent damage would kill" do
            at_deaths_door
            PersistentDamage.add(hero, '1d6', 'fire')

            told = PersistentDamage.end_of_turn(hero).map { |one| one['key'] }

            expect(told).to include('pf2e.act_spared')
            expect(hero.pf2_is_dead).to be_falsey
          end

          it "should be unconsciousness from the GM's own damage" do
            at_deaths_door

            run(PF2DamagePlayerCmd, "damage #{@hero.name}=5", @runner)

            expect(@client.failures).to eq []
            expect(hero.pf2_is_dead).to be_falsey
            expect(Pf2e.condition_level(hero, 'Dying')).to eq 0
          end

          it "should end with whoever was spared healed awake" do
            struck(@runner)

            Harm.heal(hero, 5)

            expect(hero.pf2_conditions).to_not have_key('Unconscious')
          end
        end

        describe "in a Plotmaster's encounter" do
          before(:each) { fight(@plotmaster) }

          it "should come when a hit kills" do
            struck(@plotmaster)

            expect(hero.pf2_is_dead).to be true
            expect(heard).to include(t('pf2e.act_dead', :target => @hero.name).strip)
          end

          it "should come when a failed recovery check kills" do
            at_deaths_door
            @dice = 0.25

            told = Turns.recovery(hero).map { |one| one['key'] }

            expect(told).to include('pf2e.recovery_dead')
            expect(hero.pf2_is_dead).to be true
          end

          it "should come when persistent damage kills" do
            at_deaths_door
            PersistentDamage.add(hero, '1d6', 'fire')

            told = PersistentDamage.end_of_turn(hero).map { |one| one['key'] }

            expect(told).to include('pf2e.act_dead')
            expect(hero.pf2_is_dead).to be true
          end

          it "should not come from damage the Plotmaster says may not kill" do
            at_deaths_door

            run(PF2DamagePlayerCmd, "damage/ndc #{@hero.name}=5", @plotmaster)

            expect(hero.pf2_is_dead).to be_falsey
          end

          describe "once it has come" do
            before(:each) { struck(@plotmaster) }

            it "should end the recovery checks" do
              expect(Turns.recovery(hero)).to eq []
            end

            it "should end what was burning them" do
              PersistentDamage.add(hero, '1d6', 'fire')

              expect(PersistentDamage.end_of_turn(hero)).to eq []
            end

            it "should not be healed away" do
              Harm.heal(hero, 5)

              expect(hero.pf2_is_dead).to be true
              expect(Pf2eHP.get_current_hp(hero)).to eq 0
            end

            it "should show in the encounter" do
              @client.said.clear
              run(PF2InitViewCmd, 'e/view', @plotmaster)

              expect(heard).to include('Dead')
            end

            it "should be taken back as the hit is" do
              run(PF2EncounterUndoCmd, 'e/undo', @plotmaster)

              expect(hero.pf2_is_dead).to be_falsey
            end
          end
        end
      end
    end
  end
end
