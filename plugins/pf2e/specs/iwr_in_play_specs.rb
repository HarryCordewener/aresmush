require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a creature shrugs off and what hurts it more, where damage and conditions actually land in a
    # fight: a Strike, the GM's own damage, a condition set on it, an action aimed at it.
    describe "immunities, weaknesses and resistances in a fight", :dbtest => true do

      class IwrClient
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

        @client = IwrClient.new
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

      # What a command took off the creature's hit points.
      def taken
        before = npc.damage
        yield
        npc.damage - before
      end

      describe "a devil's resistance to anything physical but silver, and its weaknesses" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Imp=ac 14 hp 200; resist physical 5 except silver; weak cold iron 5, holy 5')
          @client.said.clear
        end

        it "should come off the GM's slashing damage" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 slashing') }).to eq 7
        end

        it "should let silver through" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 slashing silver') }).to eq 12
        end

        it "should be hurt more by cold iron, whatever kind of damage it deals" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 fire cold iron') }).to eq 17
        end

        it "should not resist fire" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 fire') }).to eq 12
        end

        it "should come off a Strike, which says so" do
          expect(taken { run(PF2EncounterStrikeCmd, 'e/strike #2=fist', @hero) }).to eq 0
          expect(heard).to include('0 bludgeoning (resistance -5)')
        end

        it "should let through a Strike with a weapon said to be silver" do
          expect(taken { run(PF2EncounterStrikeCmd, 'e/strike #2=fist/silver', @hero) }).to eq 5
        end

        it "should be hurt more by a Strike with a weapon said to be cold iron" do
          expect(taken { run(PF2EncounterStrikeCmd, 'e/strike #2=fist/cold iron', @hero) }).to eq 5
          expect(heard).to include('weakness 5', 'resistance -5')
        end
      end

      describe "a swarm" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Rats=ac 5 hp 200; resist physical 6; weak area damage 3, splash damage 3; immune precision')
          @client.said.clear
        end

        it "should resist a weapon" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=10 piercing') }).to eq 4
        end

        it "should be hurt more by damage to an area" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=10 fire area') }).to eq 13
        end

        it "should be hurt more by a splash" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=2 fire splash') }).to eq 5
        end
      end

      # Animate Dream: all damage 5, except force, ghost touch and spirit, doubled against what is
      # not magical.
      describe "a spirit's resistance, doubled against what is not magical" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add animate dream')
          @client.said.clear
        end

        it "should be doubled against a plain blade" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 slashing') }).to eq 2
        end

        it "should be itself against a magical one" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 slashing magical') }).to eq 7
        end

        it "should let force through" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 force') }).to eq 12
        end

        it "should show what it excepts and doubles against to its GM" do
          run(PF2EncounterCreatureCmd, 'e/creature #2')

          expect(heard).to include('all-damage 5 (except force, ghost-touch, spirit; double against non-magical)')
        end
      end

      describe "a creature immune to critical hits" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Ooze=ac 5 hp 200; immune critical hits, precision')
          @client.said.clear
        end

        it "should take a critical hit's damage undoubled, and be told why" do
          expect(taken { run(PF2EncounterStrikeCmd, 'e/strike #2=fist', @hero) }).to eq 5
          expect(heard).to include('critical hit', t('pf2e.act_crit_immune', :target => 'Ooze #2').strip)
        end
      end

      describe "a creature immune to a condition" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add skeleton guard')
          @client.said.clear
        end

        it "should not be given it by the GM, who is told why" do
          run(PF2ConditionSetCmd, 'condition/set #2=paralyzed')

          expect(@client.failures).to eq [ t('pf2e.condition_immune', :name => 'Skeleton Guard #2', :condition => 'Paralyzed') ]
          expect(npc.pf2_conditions).to_not have_key('Paralyzed')
        end

        it "should be given one it is not immune to" do
          run(PF2ConditionSetCmd, 'condition/set #2=frightened/1')

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(npc, 'Frightened')).to eq 1
        end
      end

      # What a creature is keeps things out without its stat block saying so.
      describe "a construct" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Golem=ac 5 hp 200; traits construct')
          @client.said.clear
        end

        %w{bleed poison spirit vitality void}.each do |kind|
          it "should take no #{kind} damage" do
            expect(taken { run(PF2DamagePlayerCmd, "damage #2=12 #{kind}") }).to eq 0
          end
        end

        it "should take damage of any other kind" do
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 fire') }).to eq 12
        end

        it "should take nothing from a blow that is nonlethal" do
          expect(taken { run(PF2EncounterStrikeCmd, 'e/strike #2=fist', @hero) }).to eq 0
        end

        it "should not be given a condition its kind is immune to" do
          run(PF2ConditionSetCmd, 'condition/set #2=sickened/1')

          expect(@client.failures).to eq [ t('pf2e.condition_immune', :name => 'Golem #2', :condition => 'Sickened') ]
        end

        it "should be listed with what it is immune to" do
          run(PF2EncounterScanCmd, 'e/scan')

          expect(heard).to include('Immune bleed, death-effects, disease')
        end
      end

      describe "a mindless creature" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Husk=ac 5 hp 200 will 0; traits mindless')
          @client.said.clear
        end

        it "should be untouched by anything mental" do
          run(PF2EncounterActCmd, 'e/act demoralize=#2', @hero)

          expect(npc.pf2_conditions).to_not have_key('Frightened')
          expect(heard).to include(t('pf2e.act_immune', :target => 'Husk #2', :to => 'mental').strip)
        end
      end

      describe "a swarm" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Rats=ac 5 hp 200 reflex 0 fortitude 0; traits swarm')
          @client.said.clear
        end

        %w{Grabbed Prone Restrained}.each do |condition|
          it "should not be #{condition.downcase}" do
            run(PF2ConditionSetCmd, "condition/set #2=#{condition.downcase}")

            expect(@client.failures).to eq [ t('pf2e.condition_immune', :name => 'Rats #2', :condition => condition) ]
          end
        end

        it "should not be knocked down by a Trip that succeeds" do
          run(PF2EncounterActCmd, 'e/act trip=#2', @hero)

          expect(npc.pf2_conditions).to_not have_key('Prone')
        end
      end

      # Vitality harms only what void heals, and void only what it does not.
      describe "void and vitality" do
        it "should leave the living untouched by vitality, and harm them with void" do
          run(PF2EncounterAddCmd, 'e/add Wolf=ac 5 hp 200')

          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 vitality') }).to eq 0
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 void') }).to eq 12
        end

        it "should leave the undead untouched by void, and harm them with vitality" do
          run(PF2EncounterAddCmd, 'e/add Ghoul=ac 5 hp 200; traits undead')

          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 void') }).to eq 0
          expect(taken { run(PF2DamagePlayerCmd, 'damage #2=12 vitality') }).to eq 12
        end

        it "should say why nothing was taken" do
          run(PF2EncounterAddCmd, 'e/add Wolf=ac 5 hp 200')
          @client.said.clear
          run(PF2DamagePlayerCmd, 'damage #2=12 vitality')

          expect(heard).to include('immune')
        end

        it "should leave a living character untouched by vitality" do
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=5 vitality")

          expect(Pf2eHP.get_hp_obj(CombatantStates.of(encounter, Character[@hero.id])).damage.to_i).to eq 0
        end

        it "should harm an undead character with vitality, and not with void" do
          CombatantStates.of(encounter, Character[@hero.id]).update(:pf2_traits => [ 'undead' ])
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=5 void")
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=4 vitality")

          expect(Pf2eHP.get_hp_obj(CombatantStates.of(encounter, Character[@hero.id])).damage.to_i).to eq 4
        end

        # What everything living shares is not worth a line on each of them.
        it "should not be listed among a creature's immunities" do
          run(PF2EncounterAddCmd, 'e/add Wolf=ac 5 hp 200')
          @client.said.clear
          run(PF2EncounterScanCmd, 'e/scan')

          expect(heard).to_not include('vitality')
        end
      end

      # A skeleton guard is mindless: immune to anything mental, which Demoralize is.
      describe "a creature immune to a kind of effect" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add Automaton=ac 5 hp 200 will 0; immune mental, fear effects')
          @client.said.clear
        end

        it "should be untouched by an action with that trait, which says so" do
          run(PF2EncounterActCmd, 'e/act demoralize=#2', @hero)

          expect(npc.pf2_conditions).to_not have_key('Frightened')
          expect(heard).to include(t('pf2e.act_immune', :target => 'Automaton #2', :to => 'mental').strip)
        end

        it "should not be untouched by an action without it" do
          run(PF2EncounterActCmd, 'e/act trip=#2', @hero)

          expect(heard).to_not include('immune')
        end
      end
    end
  end
end
