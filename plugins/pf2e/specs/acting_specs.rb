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
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @hero.encounters.add @encounter
        @encounter.characters.add @hero
        Combatants.join(@encounter, @hero.name, 30, :holder => @hero)

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
          expect(@encounter.participants.map { |row| row['name'] }).to include('Goblin Warrior #2', 'Goblin Warrior #3')
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

        it "should knock the target prone on a success" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')

          expect(@client.failures).to eq []
          expect(npc(3).pf2_conditions).to have_key('Prone')
          expect(said).to include('Reflex DC')
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
        end

        it "should be taken back by the GM" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act trip=#3')
          run(PF2EncounterUndoCmd, 'e/undo')

          expect(@client.failures).to eq []
          expect(npc(3).pf2_conditions).not_to have_key('Prone')
        end

        it "should leave a demoralized creature frightened, easing at the end of its turn" do
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=act demoralize=#3')

          expect(Pf2e.condition_level(npc(3), 'Frightened')).to eq 1
          # Told once, as it is set, not again in the action's own words.
          expect(said.scan(/Frightened 1/).size).to eq 1

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

        # Battle Medicine is a Medicine check against Treat Wounds' DC: 15, or a higher one said for more.
        describe "Battle Medicine" do
          before(:each) do
            @hero.update(:pf2_feats => { 'skill' => [ 'Battle Medicine' ] })
            Pf2eHP.get_hp_obj(state).update(:damage => 15)
          end

          def state
            CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
          end

          def treat(text = '')
            run(PF2EncounterActCmd, "e/act battle medicine=#{@hero.name}#{text}", @hero)
          end

          it "should heal 2d8 on a success against DC 15" do
            @dice = 0.75
            treat

            expect(@client.failures).to eq []
            expect(said).to include('Medicine', 'DC 15 - ')
            expect(said).to include(t('pf2e.act_healed', :target => @hero.name, :count => 12))
            expect(Pf2eHP.get_hp_obj(state).damage).to eq 3
          end

          it "should add the bonus of a higher DC said" do
            @dice = 1.0
            treat('/20')

            expect(said).to include('DC 20 - ')
            expect(Pf2eHP.get_hp_obj(state).damage).to eq 0
          end

          it "should hurt on a critical failure" do
            @dice = 0.05
            treat

            expect(Pf2eHP.get_hp_obj(state).damage).to eq 16
          end
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

        # The room is told when a hit drops something: a creature is down, a character dying.
        it "should say a creature is down when a hit takes its last hit point" do
          @dice = 1.0
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

          expect(npc(3).hp_left).to eq 0
          expect(said).to include(t('pf2e.act_down', :target => 'Goblin Warrior #3'))
        end

        it "should say a character is dying when a hit drops them" do
          state = CombatantStates.of(@encounter, Character[@hero.id])
          state.update(:damage => Pf2eHP.get_max_hp(state) - 1)
          @dice = 1.0
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

          expect(said).to include(t('pf2e.act_dying', :target => @hero.name, :value => 2))
        end

        # +e/why names what the roll was against, and a defence with nothing to add ends there.
        # The base of a figure says what it is: the attack's proficiency and level. A creature's AC is
        # its stat block's, and says no more than the number.
        it "should explain a Strike against the AC it named" do
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)
          @client.said.clear
          run(PF2EncounterWhyCmd, 'e/why', @hero)

          expect(said).to include('from 3 (trained, level 1):')
          expect(said).to include('against AC 16.')
          expect(said).to_not include('(base')
        end

        # A reaction that is a Strike rolls it: the reaction is spent, and the Strike neither takes nor
        # adds to the multiple attack penalty.
        it "should make Reactive Strike's Strike outside the multiple attack penalty" do
          @hero.update(:pf2_features => { 'charclass_features' => [ 'Reactive Strike' ], 'archetype_features' => [] })
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)
          @client.said.clear
          run(PF2EncounterActCmd, 'e/act reactive strike=#3/fist', @hero)
          turn = TurnState.turn(CombatantStates.of(@encounter, Character[@hero.id]))

          expect(@client.failures).to eq []
          expect(said).to include('Reactive Strike')
          expect(said).to include('with Fist')
          expect(said).to_not include('2nd attack')
          expect(turn).to include('actions' => 1, 'attacks' => 1, 'reaction' => true)
        end

        # Flurry of Blows is one action that makes two unarmed Strikes, each counting toward the multiple
        # attack penalty as Strikes do. Both hitting, their damage is dealt as one, for resistances.
        it "should make Flurry of Blows' two unarmed Strikes for one action" do
          @hero.update(:pf2_features => { 'charclass_features' => [ 'Flurry of Blows' ], 'archetype_features' => [] })
          @dice = 0.75
          run(PF2EncounterActCmd, 'e/act flurry of blows=#3', @hero)
          turn = TurnState.turn(CombatantStates.of(@encounter, Character[@hero.id]))

          expect(@client.failures).to eq []
          expect(said.scan('strikes Goblin Warrior #3 with Fist').size).to eq 2
          expect(said).to include('Fist (2nd attack)')
          expect(said.scan('Damage to Goblin Warrior #3').size).to eq 1
          expect(turn).to include('actions' => 1, 'attacks' => 2)
        end

        # A creature with no hit points left, or a character knocked out, does nothing.
        it "should refuse a creature with no hit points left" do
          npc(2).update(:damage => npc(2).max_hp)
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

          expect(@client.failures.join).to include(t('pf2e.act_cannot_act', :actor => 'Goblin Warrior #2'))
        end

        it "should refuse a character who is unconscious" do
          Pf2e.set_condition(CombatantStates.of(@encounter, Character[@hero.id]), 'Unconscious')
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

          expect(@client.failures.join).to include(t('pf2e.act_cannot_act', :actor => @hero.name))
        end

        # An action that is a Strike and more makes the Strike, of the kind it names, with the action's own
        # rules switched on for it: Deadly Aim's -2 to hit, for its extra damage.
        it "should make an action's ranged Strike with the action's own rules on" do
          @hero.update(:pf2_feats => { 'charclass' => [ 'Deadly Aim' ] })
          state = CombatantStates.of(@encounter, Character[@hero.id])
          bow = Pf2egear.create_item(state, 'weapons', 'Shortbow', 1, Global.read_config('pf2e_weapons', 'Shortbow'))
          bow.update(:equipped => true)
          run(PF2EncounterActCmd, 'e/act deadly aim=#3', @hero)
          turn = TurnState.turn(CombatantStates.of(@encounter, Character[@hero.id]))
          run(PF2EncounterWhyCmd, 'e/why', @hero)

          expect(@client.failures).to eq []
          expect(said).to include('with Shortbow')
          expect(said).to include('-2 circumstance (Deadly Aim)')
          expect(turn).to include('actions' => 1, 'attacks' => 1)
        end

        # What a Strike does is the story of the scene: it goes in the scene's log as a line a shared log
        # keeps, where the bookkeeping of turns and joins goes in as OOC.
        it "should log a Strike's result in the scene as a line its shared log keeps" do
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

          expect(Scenes).to have_received(:add_to_scene).with(anything, a_string_including('strikes Goblin Warrior #3'))
        end

        it "should let a character strike a creature with their fist" do
          @dice = 0.75
          run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

          expect(@client.failures).to eq []
          expect(said).to include('with Fist')
          expect(npc(3).damage).to be > 0
        end

        # A critical hit with a weapon whose critical specialization the character has applies it: a
        # hammer knocks the target prone. Without the access, a critical hit is only double damage.
        describe "critical specialization" do
          before(:each) do
            @combat.update(:unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B', 'group' => 'Hammer',
                                                              'traits' => %w{agile finesse nonlethal unarmed} } })
            @dice = 1.0
          end

          it "should apply the group's effect for an attack the character has it with" do
            allow(Pf2e).to receive(:crit_spec_access).and_return('Hammer' => [ 'Fist' ])
            run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

            expect(said).to include('Critical specialization')
            expect(npc(3).pf2_conditions).to have_key('Prone')
          end

          it "should do nothing more for an attack the character does not have it with" do
            allow(Pf2e).to receive(:crit_spec_access).and_return({})
            run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

            expect(said).to_not include('Critical specialization')
            expect(npc(3).pf2_conditions).to_not have_key('Prone')
          end

          it "should set a knife's bleed burning" do
            @combat.update(:unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'P', 'group' => 'Knife',
                                                              'traits' => %w{agile unarmed} } })
            allow(Pf2e).to receive(:crit_spec_access).and_return('Knife' => [ 'Fist' ])
            run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

            expect(PersistentDamage.held(npc(3)).map { |one| [ one['formula'], one['type'] ] }).to eq [ [ '1d6', 'bleed' ] ]
          end

          it "should show a group's text where its effect is the GM's to apply" do
            @combat.update(:unarmed_attacks => { 'Fist' => { 'damage' => 'd4', 'damage_type' => 'B', 'group' => 'Club',
                                                              'traits' => %w{agile unarmed} } })
            allow(Pf2e).to receive(:crit_spec_access).and_return('Club' => [ 'Fist' ])
            run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)

            expect(said).to include('forced movement')
          end
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

      # A creature's abilities and Strikes carry rule elements the way a feat does, and they reach its
      # figures, its damage, its auras and its turn.
      describe "a creature's own rules" do
        # Drained's own rule lowers maximum hit points by its value times the level, as it does a
        # character's.
        it "should lose maximum hit points to Drained" do
          add('zombie brute')
          full = npc(2).max_hp

          Pf2e.set_condition(npc(2), 'Drained', 1)

          expect(npc(2).max_hp).to eq full - [ npc(2).pf2_level, 1 ].max
        end

        # An ability that says what it deals and the save against it rolls each target's save and deals
        # the damage by the save, basic as an area's or a Constrict's is.
        it "should roll the save against an ability's damage and deal it" do
          add('python')
          @dice = 0.05
          run(PF2EncounterAsCmd, "e/as #2=act constrict=#{@hero.name}")

          state = CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
          expect(@client.failures).to eq []
          expect(said).to include("#{@hero.name} rolls Fortitude", 'vs DC 17')
          expect(Pf2eHP.get_hp_obj(state).damage).to be > 0
        end

        it "should roll it for each target a breath is aimed at" do
          add('fire scamp')
          add('goblin warrior')
          run(PF2EncounterAsCmd, "e/as #2=act flame breath=#3,#{@hero.name}")

          expect(@client.failures).to eq []
          expect(said.scan(/rolls Reflex/).size).to eq 2
        end

        it "should refuse several targets for an action that takes one" do
          add('goblin warrior')
          add('goblin warrior')
          run(PF2EncounterActCmd, "e/act demoralize=#2,#3", @hero)

          expect(@client.failures.join).to include(t('pf2e.act_one_target', :action => 'Demoralize'))
        end

        it "should add an ability's bonus to its saves" do
          add('shade (dreamlands)')

          expect(Resolve.defence(npc(2), 'reflex')['dc']).to eq 10 + 7 + 1
        end

        it "should project an ability's aura" do
          add('choral')

          aura = Auras.of(npc(2)).find { |one| one['slug'] == 'harmonizing-aura' }

          expect(aura['radius']).to eq 20
          expect(aura['effects'].map { |one| one['name'] }).to include('Effect: Harmonizing Aura (Allies)')
        end

        # A toggle is on until someone says otherwise, as a character's is (`RollOptions`): Air Scamp's
        # fast healing holds in open air, and the GM switches it off when the scamp is not.
        it "should heal by its ability's rule, which the GM can switch off" do
          add('air scamp')
          expect(Turns.healing(npc(2)).sum { |one| one['value'] }).to eq 2

          run(PF2EncounterOptionCmd, 'e/option #2=fast-healing/off')

          expect(@client.failures).to eq []
          expect(Turns.healing(npc(2)).sum { |one| one['value'] }).to eq 0
        end

        it "should add an ability's damage to a critical Strike" do
          add('aesra')
          add('goblin warrior')
          @dice = 1.0
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')

          expect(PersistentDamage.held(npc(3)).map { |one| one['type'] }).to include('fire')
          # Told in words, with the rest of the hit.
          expect(said).to match(/Damage to Goblin Warrior #3: .* \+ \S+ persistent fire/)
          expect(said).to_not include('"key"')
        end

        # Knockdown is its own action after a Strike that lists it: a Trip that neither takes nor adds to
        # the multiple attack penalty.
        it "should knock down after a Strike, without counting toward the multiple attack penalty" do
          add('wolf')
          add('goblin warrior')
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')
          run(PF2EncounterAsCmd, 'e/as #2=act knockdown=#3')

          expect(@client.failures).to eq []
          expect(said).to include('Knockdown')
          expect(npc(3).pf2_conditions).to have_key('Prone')
          expect(TurnState.turn(npc(2))['attacks']).to eq 1
        end

        it "should name the follow-up on a hit" do
          add('wolf')
          add('goblin warrior')
          @dice = 0.75
          run(PF2EncounterAsCmd, 'e/as #2=strike #3')

          expect(said).to include('+e/as #2=act knockdown=#3')
        end
      end

      # Shield Block answers a hit just taken: the raised shield's Hardness comes off its physical damage,
      # and the shield takes what is left.
      describe "Shield Block" do
        before(:each) do
          add('2 goblin warrior')
          @hero.update(:pf2_feats => { 'general' => [ 'Shield Block' ] })
          @shield = Pf2egear.create_item(state, 'shields', 'Steel Shield', 1, Global.read_config('pf2e_shields', 'Steel Shield'))
          @shield.update(:equipped => true)
        end

        def state
          CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
        end

        def damage_taken
          Pf2eHP.get_hp_obj(state).damage.to_i
        end

        def struck
          @dice = 1.0
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")
        end

        it "should take the shield's Hardness off the hit, and leave the rest to the shield" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          struck
          taken = damage_taken
          run(PF2EncounterActCmd, 'e/act shield block', @hero)

          expect(@client.failures).to eq []
          expect(taken).to be > 5
          expect(damage_taken).to eq taken - 5
          expect(PF2Shield[@shield.id].damage).to eq taken - 5
          expect(TurnState.turn(state)['reaction']).to be true
        end

        it "should keep them up when what the shield takes leaves them hit points" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          Pf2eHP.get_hp_obj(state).update(:damage => Pf2eHP.get_max_hp(state) - 8)
          struck

          expect(Pf2e.condition_level(state, 'Dying')).to be > 0

          run(PF2EncounterActCmd, 'e/act shield block', @hero)

          expect(Pf2e.condition_level(state, 'Dying')).to eq 0
          expect(Pf2eHP.get_current_hp(state)).to be > 0
        end

        it "should offer Shield Block when a raised shield could block the hit" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          struck

          expect(said).to include('+e/act shield block')
        end

        it "should refuse without a raised shield" do
          struck
          taken = damage_taken
          run(PF2EncounterActCmd, 'e/act shield block', @hero)

          expect(@client.failures.join).to include(t('pf2e.shield_block_no_shield'))
          expect(damage_taken).to eq taken
        end

        # Shield Block answers the last attack; one that missed leaves nothing to block.
        it "should leave nothing to block after a later attack misses" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          struck
          @dice = 0.05
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

          expect(ShieldBlock.offered?(state)).to be_falsey
          run(PF2EncounterActCmd, 'e/act shield block', @hero)
          expect(@client.failures.join).to include(t('pf2e.shield_block_no_hit'))
        end

        # A broken shield gives nothing raised; raising it is refused and says why.
        it "should not offer a block once the shield is no longer raised" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          struck
          ActiveEffects.named_on(state, 'Effect: Raise a Shield').each(&:delete)

          expect(ShieldBlock.offered?(state)).to be_falsey
        end

        it "should refuse to raise a broken shield" do
          @shield.update(:damage => 10)
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)

          expect(@client.failures.join).to include(t('pf2e.raise_shield_broken', :shield => 'Steel Shield'))
          expect(ActiveEffects.named_on(state, 'Effect: Raise a Shield')).to be_empty
        end

        it "should refuse with nothing to block" do
          run(PF2EncounterActCmd, 'e/act raise a shield', @hero)
          run(PF2EncounterActCmd, 'e/act shield block', @hero)

          expect(@client.failures.join).to include(t('pf2e.shield_block_no_hit'))
        end
      end

      # Nimble Dodge answers an attack that has hit: its +2 to AC is put against the roll, and a hit it
      # turns into a miss is undone.
      # Stand rolls nothing: you stand up from prone, and Drop Prone puts you there.
      describe "Stand" do
        it "should leave the character no longer prone, and roll nothing" do
          state = CombatantStates.of(@encounter, Character[@hero.id])
          Pf2e.set_condition(state, 'Prone')
          run(PF2EncounterActCmd, 'e/act stand', @hero)

          expect(@client.failures).to eq []
          expect(CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id]).pf2_conditions).to_not have_key('Prone')
          expect(said).to_not include(' vs ')
          expect(said).to include(t('pf2e.act_no_longer', :target => @hero.name, :condition => 'Prone').strip)
        end

        it "should leave the character prone when they drop prone" do
          run(PF2EncounterActCmd, 'e/act drop prone', @hero)

          expect(CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id]).pf2_conditions).to have_key('Prone')
        end
      end

      # An action with a command of its own is done with that command; using it as an action says which.
      it "should point Quick Alchemy at the command that makes the item" do
        @hero.update(:pf2_features => { 'charclass_features' => [ 'Quick Alchemy' ], 'archetype_features' => [] })
        run(PF2EncounterActCmd, 'e/act quick alchemy', @hero)

        expect(@client.failures.join).to include('+e/alchemy')
        expect(TurnState.turn(CombatantStates.of(@encounter, Character[@hero.id]))['actions'].to_i).to eq 0
      end

      describe "Nimble Dodge" do
        before(:each) do
          add('2 goblin warrior')
          @hero.update(:pf2_feats => { 'charclass' => [ 'Nimble Dodge' ] })
        end

        def state
          CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
        end

        def ac
          Resolve.defence(state, 'ac')['dc']
        end

        # The goblin's Strike is +7: a die that meets the AC exactly hits, and +2 makes it miss.
        def struck_exactly
          @dice = (ac - 7) / 20.0
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")
        end

        it "should turn a hit by less than 2 into a miss, and undo it" do
          struck_exactly
          expect(Pf2eHP.get_hp_obj(state).damage).to be > 0

          run(PF2EncounterActCmd, 'e/act nimble dodge', @hero)

          expect(@client.failures).to eq []
          expect(Pf2eHP.get_hp_obj(state).damage).to eq 0
          expect(TurnState.turn(state)['reaction']).to be true
        end

        it "should offer itself when it could turn the hit" do
          struck_exactly

          expect(said).to include('+e/act nimble dodge')
        end

        it "should refuse once something has moved their hit points since" do
          struck_exactly
          Harm.heal(state, 1)

          run(PF2EncounterActCmd, 'e/act nimble dodge', @hero)

          expect(@client.failures.join).to include('Too late for Nimble Dodge')
        end

        it "should leave a hit it cannot turn as it was" do
          @dice = 1.0
          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")
          taken = Pf2eHP.get_hp_obj(state).damage

          run(PF2EncounterActCmd, 'e/act nimble dodge', @hero)

          expect(Pf2eHP.get_hp_obj(state).damage).to eq taken
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
          # A critical failure also leaves the target fleeing for a round.
          expect(npc(3).pf2_conditions).to have_key('Fleeing')
          expect(TurnState.turn(npc(2))['actions']).to eq 2
        end
      end

      describe "what a spell's outcome says" do
        before(:each) do
          add('gnome bard')
          add('goblin warrior')
        end

        # Daze's stun is in a sentence of its own rather than an outcome's paragraph.
        it "should stun a target that critically fails Daze's save" do
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=cast daze=#3')

          expect(Pf2e.condition_level(npc(3), 'Stunned')).to eq 1
        end

        # A critical success on a basic save takes nothing, and the room is told so, not of 0 damage.
        it "should say a target that critically succeeds a basic save takes no damage" do
          @dice = 1.0
          run(PF2EncounterAsCmd, 'e/as #2=cast daze=#3')

          expect(said).to include(t('pf2e.act_unharmed', :target => 'Goblin Warrior #3').strip)
          expect(said).to_not include('Damage to Goblin Warrior #3')
        end

        # A save that is not basic scales the persistent damage as its outcome says: Blistering Invective's
        # half on a success, double on a critical failure.
        it "should halve the persistent damage on a success" do
          @dice = 0.95
          run(PF2EncounterAsCmd, 'e/as #2=cast blistering invective=#3')

          expect(said).to include('Will', 'success')
          expect(npc(3).pf2_persistent).to eq [ { 'formula' => '1d6', 'type' => 'fire', 'dc' => 15 } ]
        end

        it "should double the persistent damage on a critical failure" do
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=cast blistering invective=#3')

          expect(npc(3).pf2_persistent).to eq [ { 'formula' => '4d6', 'type' => 'fire', 'dc' => 15 } ]
        end

        # A spell with no save that ends a condition on its target does: Stabilize ends dying.
        it "should end a dying target's dying with Stabilize" do
          state = CombatantStates.of(@encounter, Character[@hero.id])
          Pf2eHP.get_hp_obj(state).update(:damage => Pf2eHP.get_max_hp(state))
          Pf2e.set_condition(state, 'Dying', 1)
          run(PF2EncounterAsCmd, "e/as #2=cast stabilize=#{@hero.name}")

          expect(@client.failures).to eq []
          expect(Pf2e.condition_level(CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id]), 'Dying')).to eq 0
        end

        # A spell cast one way for the living and another against the undead, cast without saying which,
        # is cast the way its target calls for: Lay on Hands heals a living ally.
        it "should heal a living target with Lay on Hands" do
          state = CombatantStates.of(@encounter, Character[@hero.id])
          Pf2eHP.get_hp_obj(state).update(:damage => 10)
          run(PF2EncounterAsCmd, "e/as #2=cast lay on hands=#{@hero.name}")

          expect(@client.failures).to eq []
          expect(Pf2eHP.get_hp_obj(CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])).damage).to eq 4
        end

        # What Command does is the target's to do; the room is told what that is.
        it "should tell the room what an outcome does where it sets no condition" do
          @dice = 0.05
          run(PF2EncounterAsCmd, 'e/as #2=cast command=#3')

          expect(said).to include('The target must use all its actions on its next turn to obey your command.')
        end

        # A spell attack's outcomes are the attack's: Briny Bolt's critical hit blinds and dazzles.
        it "should leave what a spell attack's outcome says on what it hits" do
          @dice = 1.0
          run(PF2EncounterAsCmd, 'e/as #2=cast briny bolt=#3')

          expect(npc(3).pf2_conditions.keys).to include('Blinded', 'Dazzled')
        end
      end

      describe "the turn" do
        before(:each) { add('goblin warrior') }

        # "Until the end of its next turn" is the target's: this round's turn if it has yet to act, and
        # next round's if it has.
        it "should end a condition at the end of the target's next turn, which is this round's if it is still to come" do
          @encounter.update(:next_init => 1)
          ends = Turns.expiry_for('its-next-turn-end', @encounter, @hero.name, npc(2).name)

          expect(ends).to eq('event' => 'turn-end', 'of' => npc(2).name, 'round' => 1)

          Pf2e.set_condition(npc(2), 'Dazzled')
          Acting.expire_at(npc(2), 'Dazzled', ends)
          Turns.turn_ended(@encounter, npc(2).name, 1)

          expect(npc(2).pf2_conditions).not_to have_key('Dazzled')
        end

        it "should end it at the end of the target's turn next round when the target has acted" do
          @encounter.update(:next_init => 2)

          expect(Turns.expiry_for('its-next-turn-end', @encounter, @hero.name, npc(2).name)['round']).to eq 2
          expect(Turns.expiry_for('its-next-turn-start', @encounter, @hero.name, npc(2).name)['event']).to eq 'turn-start'
        end

        it "should time the caster's own durations from the caster's turn, as before" do
          expect(Turns.expiry_for('next-turn-end', @encounter, @hero.name, npc(2).name)).to eq Turns.expiry('next-turn-end', @hero.name, 1)
        end

        it "should end a condition set until the start of the actor's next turn" do
          Pf2e.set_condition(npc(2), 'Off-Guard')
          Acting.expire_at(npc(2), 'Off-Guard', Turns.expiry('next-turn-start', @hero.name, 1))

          Turns.turn_started(@encounter, @hero.name, 2)

          expect(npc(2).pf2_conditions).not_to have_key('Off-Guard')
        end

        # A dying character rolls a recovery check as their turn starts: a flat check against 10 and their
        # dying value. A critical success takes two off, a success one; a failure adds one, a critical
        # failure two. At nothing they stop dying, wounded and still unconscious.
        describe "a recovery check" do
          def hero_state
            CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
          end

          def dying(value)
            state = hero_state
            state.update(:damage => Pf2eHP.get_max_hp(state))
            Pf2e.set_condition(state, 'Dying', value)
          end

          def turn
            Turns.turn_started(PF2Encounter[@encounter.id], @hero.name, 2)
          end

          it "should bring someone out of dying on a natural 20, wounded and unconscious" do
            dying(2)
            @dice = 1.0

            told = turn

            expect(Pf2e.condition_level(hero_state, 'Dying')).to eq 0
            expect(Pf2e.condition_level(hero_state, 'Wounded')).to eq 1
            expect(hero_state.pf2_conditions).to have_key('Unconscious')
            expect(told.map { |one| one['key'] }).to include('pf2e.recovery_check')
          end

          # Out of dying they are unconscious for having no hit points, and healing wakes them.
          it "should wake someone healed after they stopped dying, still wounded once" do
            dying(1)
            @dice = 1.0
            turn

            Harm.heal(hero_state, 5)

            expect(hero_state.pf2_conditions).to_not have_key('Unconscious')
            expect(Pf2e.condition_level(hero_state, 'Wounded')).to eq 1
          end

          it "should not wake someone asleep for another reason" do
            Pf2e.set_condition(hero_state, 'Unconscious')
            hero_state.update(:damage => 3)

            Harm.heal(hero_state, 2)

            expect(hero_state.pf2_conditions).to have_key('Unconscious')
          end

          it "should take one off on a success" do
            dying(1)
            @dice = 0.6

            turn

            expect(Pf2e.condition_level(hero_state, 'Dying')).to eq 0
          end

          it "should add one on a failure" do
            dying(1)
            @dice = 0.25

            turn

            expect(Pf2e.condition_level(hero_state, 'Dying')).to eq 2
          end

          # Death is the GM's to say: a check that would kill leaves them one short, and says so.
          it "should stop one short of death, and tell the GM" do
            dying(3)
            @dice = 0.25

            told = turn

            expect(Pf2e.condition_level(hero_state, 'Dying')).to eq 3
            expect(Character[@hero.id].pf2_is_dead).to be_falsey
            expect(told.map { |one| one['key'] }).to include('pf2e.recovery_at_death')
          end

          it "should roll nothing for someone who is not dying" do
            expect(turn.map { |one| one['key'] }).to_not include('pf2e.recovery_check')
          end
        end

        it "should start the counts over as a turn starts" do
          TurnState.spend(npc(2), 'Strike', :attack => true)
          Turns.turn_started(@encounter, npc(2).name, 2)

          expect(TurnState.turn(npc(2))['attacks']).to eq 0
        end

        # A creature with no hit points left has no turn to take; the GM is told so, and how to clear it.
        it "should tell the GM a creature's turn is a fallen one's" do
          npc(2).update(:damage => npc(2).max_hp)

          reminder = Turns.reminder(npc(2), 2)

          expect(reminder).to include(t('pf2e.turn_down', :name => npc(2).name, :ref => '#2'))
          expect(reminder).to_not include('+e/as #2=strike')
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

        it "should show the encounter's difficulty and its history" do
          seen = PF2EncounterHandler.new.handle(request(@hero, 'id' => @encounter.id))

          expect(seen[:difficulty]).to eq "Moderate: 20 XP of 20 for a party of 1 at level 1."
          expect(seen[:history].map { |one| one[:said] }).to include(a_string_including('e/add goblin warrior'))
          expect(seen[:history].map { |one| one[:undone] }.uniq).to eq [ false ]
        end

        # The same rule the sheet keeps: a character's hit points are on their combat sheet, and whoever
        # may not see that may not see them here either.
        it "should show a character's hit points only to whoever may see their sheet" do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e', 'open_sheets').and_return(false)
          other = Character.create(:name => "Bram#{rand(1000000)}", :room => @room)
          other_hp = Pf2eHP.create(:character => other, :ancestry_hp => 8, :charclass_hp => 10)
          other.update(:hp => other_hp, :pf2_level => 1)
          Combatants.join(@encounter, other.name, 25, :holder => other)

          seen = PF2EncounterHandler.new.handle(request(@hero, 'id' => @encounter.id))[:combatants]
          mine = seen.find { |one| one[:name] == @hero.name }
          theirs = seen.find { |one| one[:name] == other.name }

          expect(mine[:hp]).to_not be_nil
          expect(theirs[:hp]).to be_nil
        ensure
          other_hp&.delete
          other&.delete
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

        # The GM's damage drops someone as a Strike does, and the room is told the same.
        it "should say when the GM's damage drops someone" do
          allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
          run(PF2DamagePlayerCmd, "damage #2=#{npc(2).max_hp}")
          run(PF2DamagePlayerCmd, "damage #{@hero.name}=#{Pf2eHP.get_max_hp(CombatantStates.of(@encounter, Character[@hero.id]))}")

          expect(said).to include(t('pf2e.act_down', :target => 'Goblin Warrior #2').strip)
          expect(said).to include(t('pf2e.act_dying', :target => @hero.name, :value => 1).strip)
        end
      end
    end
  end
end
