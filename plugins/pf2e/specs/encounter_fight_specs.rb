require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A whole fight, through the commands a GM and a player type, from `encounter` to `encounter/end`.
    #
    # Each piece has its own specs; this is the one that holds them together, the way the level 20
    # audit holds a climb together. It starts an encounter, joins it, adds creatures, and moves the order
    # through two rounds - Strikes each way, a Demoralize, a turn's counts starting over, Frightened
    # easing at the end of the frightened creature's own turn - and ends it.
    #
    # Every die shows three quarters of its faces: a d20 is 15, a d6 is 5, a d4 is 3.
    describe "a fight, start to finish", :dbtest => true do

      class FightClient
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

        @client = FightClient.new
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

        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('run_encounters') { |char, _| char.name == @gm.name }

        @reminded = []
        allow(Login).to receive(:emit_ooc_if_logged_in) { |char, message| @reminded << [ char.name, message ] }
      end

      after(:each) do
        encounter = @scene ? PF2Encounter.scene_active_encounter(Scene[@scene.id]) || PF2Encounter.find(:scene_id => @scene.id).first : nil
        PF2Encounter.find(:scene_id => @scene.id).each { |one| one.npcs.each(&:delete) } rescue nil
        ActiveEffects.on(Character[@hero.id]).each(&:delete)
        (@abilities + [ @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def run(cmd_class, text, who = @gm)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def encounter
        PF2Encounter.scene_active_encounter(Scene[@scene.id]) || PF2Encounter.find(:scene_id => @scene.id).first
      end

      def npc(number)
        encounter.npcs.to_a.find { |one| one.number == number }
      end

      # The hero as they stand in the fight.
      def hero
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def advance
        run(PF2EncounterNextCmd, "encounter/next #{encounter.id}")
      end

      def current
        ActiveEffects.current_turn(encounter)
      end

      it "should run from the first turn to the end" do
        # A player cannot start one; the GM can.
        run(PF2InitiateCombatCmd, 'encounter', @hero)
        expect(@client.failures.pop).to eq t('pf2e.encounter_start_gm_only')

        run(PF2InitiateCombatCmd, 'encounter')
        # What the hero carries as they join is what they carry in the fight.
        potion = PF2Consumable.create(:name => 'Minor Healing Potion', :quantity => 1, :character => Character[@hero.id])

        # The hero joins on the statistic they name, in any case: `dex` is Dexterity.
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}=stealthy", @hero)
        expect(@client.failures.pop).to eq t('pf2e.bad_initiative_stat', :stat => 'stealthy')
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}=dex", @hero)
        run(PF2EncounterAddCmd, 'e/add 2 goblin warrior')

        expect(@client.failures).to eq []
        expect(Combatants.all(encounter).map(&:number)).to contain_exactly(1, 2, 3)

        # A goblin goes first: a tie between a creature and a character goes to the creature.
        advance
        expect(current).to eq 'Goblin Warrior #2'

        full = Pf2eHP.get_current_hp(hero)
        run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")
        struck = Pf2eHP.get_current_hp(hero)
        expect(struck).to be < full

        # Only the GM takes it back; taking it back and putting it back leaves it as the Strike did.
        run(PF2EncounterUndoCmd, 'e/undo', @hero)
        expect(@client.failures.pop).to eq t('pf2e.not_organizer')
        run(PF2EncounterUndoCmd, 'e/undo')
        expect(Pf2eHP.get_current_hp(hero)).to eq full
        run(PF2EncounterUndoCmd, "e/redo")
        expect(Pf2eHP.get_current_hp(hero)).to eq struck

        # The wound is the fight's: the hero's own sheet is untouched, and their sheet in the fight shows it.
        expect(Pf2eHP.get_current_hp(Character[@hero.id])).to eq full

        @client.said.clear
        run(PF2EncounterSheetCmd, 'e/sheet', @hero)
        expect(@client.failures).to eq []
        expect(@client.said.join("\n")).to include("#{Pf2eHP.get_current_hp(hero)}")

        advance
        advance
        expect(current).to eq @hero.name
        expect(@reminded.map(&:first)).to include(@hero.name)

        # Two Strikes: the second is the agile weapon's -4.
        run(PF2EncounterStrikeCmd, 'e/strike #2=fist', @hero)
        run(PF2EncounterStrikeCmd, 'e/strike #3=fist', @hero)
        expect(@client.said.join("\n")).to include('2nd attack')
        expect(TurnState.turn(hero)['attacks']).to eq 2

        run(PF2EncounterActCmd, 'e/act demoralize=#3', @hero)
        expect(Pf2e.condition_level(npc(3), 'Frightened')).to eq 1

        # Round two. The hero's counts start over as their turn does, and the goblin's fear eases at the
        # end of the goblin's own turn.
        advance
        expect(encounter.round).to eq 2
        advance
        advance
        expect(current).to eq @hero.name
        expect(TurnState.turn(hero)['attacks']).to eq 0
        # Their reminder is of the turn starting, not the one before.
        expect(@reminded.select { |name, _message| name == @hero.name }.last.last).to include(TurnState.summary(hero))
        expect(TurnState.summary(hero)).to include('0 of 3')
        expect(npc(3).pf2_conditions).to_not have_key('Frightened')

        # A potion drunk mid-fight is gone from what they carry there, and the GM can give it back. Their own
        # potion is untouched until the fight ends, and what they buy meanwhile is no part of it.
        run(Pf2egear::PF2EncounterUseCmd, 'e/use consumable=0', @hero)
        expect(hero.consumables.to_a).to eq []
        expect(PF2Consumable[potion.id]).not_to be_nil
        run(PF2EncounterUndoCmd, 'e/undo')
        expect(hero.consumables.to_a.map(&:quantity)).to eq [ 1 ]
        run(PF2EncounterUndoCmd, 'e/redo')
        dagger = PF2Weapon.create(:name => 'Dagger', :character => Character[@hero.id])
        @client.said.clear
        run(Pf2egear::PF2EncounterGearCmd, 'e/gear', @hero)
        expect(@client.said.join).not_to include('Dagger')

        @client.said.clear
        run(PF2EncounterHistoryCmd, 'e/history')
        expect(@client.said.join).to include("e/as #2=strike #{@hero.name}", 'e/strike #3=fist')

        run(PF2EncounterTrustCmd, "e/trust #{@hero.name}")
        run(PF2EncounterEndCmd, "encounter/end #{encounter.id}")

        # The potion drunk in the fight comes off their own inventory as it ends; the dagger they bought stays.
        expect(PF2Consumable[potion.id]).to be_nil
        expect(PF2Weapon[dagger.id]).not_to be_nil
        dagger.delete
        run(PF2EncounterUndoCmd, 'e/undo')
        expect(@client.failures.pop).to eq t('pf2e.no_encounter_here')

        # Two goblin warriors (level -1) for one 1st-level hero: 20 + 20 XP against a budget of 20 for one.
        # Staff see PF2e's recommendation, and pay what they decide.
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.name == @gm.name }
        id = encounter.id
        @client.said.clear
        run(PF2EncounterAwardCmd, "e/award #{id}")
        expect(@client.said.join).to include('Extreme: 40 XP of 40 for a party of 1 at level 1', 'Nobody has been paid')

        xp = Character[@hero.id].pf2_xp
        run(PF2EncounterAwardCmd, "e/award #{id}=#{@hero.name}=40/5 gp")
        expect(Character[@hero.id].pf2_xp).to eq xp + 40
        expect(PF2Encounter[id].awarded[@hero.name]).to eq('xp' => 40, 'money' => 500)

        run(PF2EncounterAwardCmd, "e/award #{id}=#{@hero.name}=40/5 gp", @hero)
        expect(@client.failures.pop).to eq t('dispatcher.not_allowed')

        expect(encounter.is_active).to be false
        expect(encounter.trusted).to eq []
        expect(@client.failures).to eq []
      end
    end
  end
end
