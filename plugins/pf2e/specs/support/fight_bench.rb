module AresMUSH
  module Pf2e

    # A fight on a bench, for a spec about what happens in one: a room, a scene, a Plotmaster running an
    # encounter, and a level 1 hero in it with a fist and a claw, every die held at the fraction of its
    # faces the spec sets. Commands are typed through their handlers and what the room and the typist
    # were told is read back.
    #
    # Included in a describe block tagged `:dbtest`, which calls `bench!` before each example and
    # `clear_bench!` after.
    module FightBench

      class Client
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

      # A 12 on the d20 hits most things without a critical hit; a 19 succeeds; a 1 fails.
      HITS = 0.6
      HIGH = 0.95
      LOW = 0.05

      def bench!(level: 1, hp: 30)
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = Client.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' },
                                    :unarmed_attacks => {
                                      'Fist' => { 'damage' => 'd4', 'damage_type' => 'B', 'group' => 'Brawling',
                                                  'traits' => %w{agile finesse nonlethal unarmed} },
                                      'Claw' => { 'damage' => 'd6', 'damage_type' => 'S', 'group' => 'Brawling',
                                                  'traits' => %w{agile finesse unarmed} }
                                    })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => hp - 8)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => level, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_baseinfo_locked => true, :pf2_derived => {}, :pf2_feats => {},
                     :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @scene.participants.add @hero

        @dice = HITS
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in) { |_who, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }

        run(PF2InitiateCombatCmd, 'encounter')
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}", @hero)
        @client.said.clear
      end

      def clear_bench!
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

      def hero
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def held
        hero.pf2_conditions || {}
      end

      def hero_hp
        Pf2eHP.get_current_hp(hero)
      end

      def add(creature)
        run(PF2EncounterAddCmd, "e/add #{creature}")
        @client.said.clear
      end

      # Everything told since the last command began, without the colour codes.
      def heard
        @client.said.join("\n").gsub(/%x(?:\d{1,3}|[a-zA-Z])/, '')
      end

      def refused
        @client.failures
      end

      # The GM acts for a creature with the dice at `dice`.
      def as(number, text, dice = HITS)
        typed(PF2EncounterAsCmd, "e/as ##{number}=#{text}", @gm, dice)
      end

      # The hero types a command with the dice at `dice`.
      def hero_types(text, dice = HITS)
        handler = Pf2e.get_cmd_handler(@client, Command.new(text), Character[@hero.id])

        typed(handler, text, @hero, dice)
      end

      def typed(cmd_class, text, who, dice)
        @dice = dice
        @client.said.clear
        @client.failures.clear
        run(cmd_class, text, who)
      end

      def next_turn
        run(PF2EncounterNextCmd, 'e/next')
      end

      # Moves the order on until it is this combatant's turn.
      def turn_to(label)
        (Combatants.rows(encounter).size + 1).times do
          break if ActiveEffects.current_turn(encounter) == label

          next_turn
        end
      end
    end
  end
end
