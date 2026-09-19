require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A fight played through the commands a GM and a player type: creatures added from the bestiary,
    # actions resolved against their real defences, consequences applied with the command that reverses
    # them, cover set by whoever may set it, and time passing at the turn.
    #
    # Dice are loaded: `@dice` is what every die shows, as a fraction of its faces - 1.0 is a natural 20
    # on a d20 and a 6 on a d6.
    describe "acting in an encounter", :dbtest => true do

      class ActClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |msg| @said << msg.to_s } }

        def to_s
          "ActClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = ActClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' },
                                    :unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B',
                                                                      'traits' => %w{agile finesse nonlethal unarmed} } })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1,
                                         :participants => [ [ 30.0, @hero.name ] ], :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.number(@encounter, @hero.name)

        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        encounter = PF2Encounter[@encounter.id]
        encounter&.npcs&.each(&:delete)
        ActiveEffects.on(Character[@hero.id]).each(&:delete)
        (@abilities + [ @encounter, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
        @encounter = PF2Encounter[@encounter.id]
      end

      def said
        @client.said.join("\n")
      end

      def npc(number)
        @encounter.npcs.to_a.find { |one| one.number == number }
      end

      def add(text)
        run(PF2EncounterAddCmd, "e/add #{text}")
      end

      describe "adding creatures" do
        it "should give each its own id and place in the order" do
          add('2 goblin warrior')

          expect(@client.failures).to eq []
          expect(@encounter.npcs.to_a.map(&:number).sort).to eq [ 2, 3 ]
          expect(@encounter.participants.map(&:last)).to include('Goblin Warrior #2', 'Goblin Warrior #3')
          expect(npc(2).max_hp).to eq 6
        end

        it "should take a creature described by its numbers" do
          add('Bandit=ac 15 fort 6 ref 8 will 4 perception 5 hp 20')

          expect(npc(2).stat_block['ac']).to eq 15
          expect(npc(2).max_hp).to eq 20
        end

        it "should find a combatant by id and by name" do
          add('goblin warrior=Grik')

          expect(Combatants.find(@encounter, '#2').state.label).to eq 'Grik'
          expect(Combatants.find(@encounter, 'grik').state.number).to eq 2
        end
      end

      describe "an action with a check" do
        before(:each) { add('2 goblin warrior') }

        it "should knock the target prone on a success, and say how to undo it" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')

          expect(@client.failures).to eq []
          expect(npc(3).pf2_conditions).to have_key('Prone')
          expect(said).to include('Reflex DC')
          expect(said).to include('undo: condition/set #3=Prone/0')
        end

        it "should put the tripper down on a critical failure" do
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')

          expect(npc(2).pf2_conditions).to have_key('Prone')
          expect(npc(3).pf2_conditions).not_to have_key('Prone')
        end

        it "should deal Trip's damage on a critical success" do
          @dice = 1.0
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')

          expect(npc(3).damage).to eq 6
          expect(said).to include('undo: heal #3=6')
        end

        it "should reverse with the command it printed" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')
          run(PF2ConditionSetCmd, 'condition/set #3=Prone/0')

          expect(@client.failures).to eq []
          expect(npc(3).pf2_conditions).not_to have_key('Prone')
        end

        it "should leave a demoralized creature frightened, easing at the end of its turn" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act demoralize=#3')

          expect(Pf2e.condition_level(npc(3), 'Frightened')).to eq 1

          Turns.turn_ended(@encounter, npc(3).name, 1)

          expect(npc(3).pf2_conditions).not_to have_key('Frightened')
        end

        it "should read a frightened creature's lower Will" do
          Pf2e.set_condition(npc(3), 'Frightened', 2)

          expect(Resolve.defence(npc(3), 'will')['dc']).to eq 10 + 3 - 2
        end

        it "should put Bon Mot's critical penalty on the target" do
          @dice = 1.0
          run(PF2EncounterAsCmd, 'e/as #2=act bon mot=#3')

          expect(ActiveEffects.on(npc(3)).map(&:name)).to eq [ 'Effect: Bon Mot' ]
          expect(Resolve.defence(npc(3), 'will')['dc']).to eq 10 + 3 - 3
        end

        it "should give a critically failed Aid's penalty, not a bonus" do
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=act aid=#3/athletics')

          expect(ActiveEffects.on(npc(3)).first.answers).to eq [ '-1' ]
        end

        it "should count an attack action toward the multiple attack penalty" do
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')

          expect(TurnState.turn(npc(2))['attacks']).to eq 1
          expect(TurnState.map_options(npc(2))).to eq [ 'map:increases:1' ]
        end
      end

      describe "a Strike" do
        before(:each) { add('2 goblin warrior') }

        it "should hit against AC and deal the creature's damage" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')

          expect(@client.failures).to eq []
          expect(said).to include('vs AC 16 - ')
          expect(npc(3).damage).to be > 0
        end

        it "should take the agile penalty on the second Strike" do
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')
          check = Check.of(npc(2), 'attack', Npcs.strike(npc(2)), TurnState.map_options(npc(2)))

          expect(check.total).to eq 7 - 4
        end

        it "should let a character strike a creature with their fist" do
          @dice = 0.75
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

          expect(@client.failures).to eq []
          expect(said).to include('with Fist')
          expect(npc(3).damage).to be > 0
        end

        it "should miss a hidden target that fails its flat check" do
          @encounter.update(:concealment => { '3' => 'hidden' })
          @dice = 0.25
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')

          expect(said).to include('flat check')
          expect(npc(3).damage).to eq 0
        end

        it "should read a weakness" do
          add('zombie brute')
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=strike #4')

          expect(said).to include('weakness 10')
        end
      end

      describe "cover and trust" do
        before(:each) { add('goblin warrior') }

        it "should let the GM set cover, which raises AC" do
          run(PF2EncounterCoverCmd, 'e/cover #2=standard')

          expect(@encounter.cover).to eq('2' => 'standard')
          scene = Acting::Scene.new(@encounter, Combatants.find(@encounter, @hero.name).state,
                                    Combatants.find(@encounter, '#2').state, @hero, false)
          extra = Acting.defender_extra(scene, Acting.said([], false), 'ac')

          expect(Resolve.defence(npc(2), 'ac', :extra => extra)['dc']).to eq 18
        end

        it "should refuse a player the GM has not trusted" do
          run(PF2EncounterCoverCmd, 'e/cover #2=greater', @hero)

          expect(@client.failures.join).to include('trusted')
          expect(@encounter.cover).to eq({})
        end

        it "should let a trusted player set it, for this encounter only" do
          run(PF2EncounterTrustCmd, "e/trust #{@hero.name}")
          run(PF2EncounterCoverCmd, 'e/cover #2=lesser', @hero)

          expect(@encounter.cover).to eq('2' => 'lesser')

          run(PF2EncounterEndCmd, "encounter/end #{@encounter.id}")

          expect(@encounter.trusted).to eq []
          expect(@encounter.cover).to eq({})
        end

        it "should refuse a player's word for cover on their own roll" do
          @dice = 0.75
          run(PF2EncounterStrikeCmd, 'e/strike #2=fist/greater cover', @hero)

          expect(said).to include('Only the GM')
        end
      end

      describe "casting" do
        it "should roll each target's save and leave what the outcome says" do
          add('spirit priest')
          add('goblin warrior')
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=cast fear=#3')

          expect(@client.failures).to eq []
          expect(said).to include('rolls Will')
          expect(Pf2e.condition_level(npc(3), 'Frightened')).to eq 3
          expect(TurnState.turn(npc(2))['actions']).to eq 2
        end
      end

      describe "the turn" do
        before(:each) { add('goblin warrior') }

        it "should end a condition set until the start of the actor's next turn" do
          Pf2e.set_condition(npc(2), 'Off-Guard')
          Acting.expire_at(npc(2), 'Off-Guard', Turns.expiry('next-turn-start', @hero.name, 1))

          Turns.turn_started(@encounter, @hero.name, 2)

          expect(npc(2).pf2_conditions).not_to have_key('Off-Guard')
        end

        it "should start the counts over as a turn starts" do
          TurnState.spend(npc(2), 'Strike', :attack => true)
          Turns.turn_started(@encounter, npc(2).name, 2)

          expect(TurnState.turn(npc(2))['attacks']).to eq 0
        end

        it "should remind the GM of a creature's turn" do
          expect(Turns.reminder(npc(2), 2)).to include('+e/as #2=strike')
        end
      end

      describe "what the web portal reads" do
        before(:each) do
          add('goblin warrior')
          allow(Website).to receive(:check_login).and_return(nil)
        end

        def request(who, args = {})
          double(:args => args, :enactor => Character[who.id], :log_request => nil)
        end

        it "should list each combatant with its id, and a creature's hit points only to the GM" do
          seen = PF2EncounterHandler.new.handle(request(@hero, 'id' => @encounter.id))

          expect(seen[:combatants].map { |one| one[:id] }).to eq [ 1, 2 ]
          expect(seen[:combatants].last[:hp]).to be_nil
          expect(PF2EncounterHandler.new.handle(request(@gm, 'id' => @encounter.id))[:combatants].last[:hp]).to eq '6 / 6'
        end

        it "should list the viewer's actions by mode, with what each rolls" do
          trip = PF2ActionsHandler.new.handle(request(@hero))[:modes]['combat'].find { |one| one[:name] == 'Trip' }

          expect(trip[:rolls]).to eq 'athletics'
          expect(trip[:against]).to eq 'reflex'
        end

        it "should give the viewer's last roll" do
          @dice = 0.75
          run(PF2EncounterStrikeCmd, 'e/strike #2=fist', @hero)

          expect(PF2LastRollHandler.new.handle(request(@hero))[:lines].first).to include('Fist')
        end
      end

      describe "the commands that reverse" do
        before(:each) { add('goblin warrior') }

        it "should damage and heal a creature by its id" do
          run(PF2DamagePlayerCmd, 'damage #2=4 slashing')
          expect(npc(2).damage).to eq 4

          run(PF2HealPlayerCmd, 'heal #2=3')
          expect(npc(2).damage).to eq 1
        end
      end
    end
  end
end
