require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The creatures a GM brings to an encounter, beyond the bestiary's as written: one made elite or weak,
    # as it comes in or once it is fighting, and one of the GM's own making.
    describe "an encounter's creatures", :dbtest => true do

      class CreaturesClient
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

        @client = CreaturesClient.new
        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Aria#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @hero, :armor_prof => { 'unarmored' => 'trained' },
                                    :weapon_prof => { 'unarmed' => 'trained' })
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:combat => @combat, :hp => @hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [], :pf2_baseinfo_locked => true,
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @scene.participants.add @hero

        # Every die shows three quarters of its faces: a d20 is 15, a d6 is 5.
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
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

      def npc(number)
        encounter.npcs.to_a.find { |one| one.number == number }
      end

      def hero
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def heard
        @client.said.join("\n")
      end

      # Goblin Warrior: level -1, AC 16, 6 hit points, Dogslicer +7 for 1d6 slashing.
      describe "made elite or weak as it comes in" do
        it "should be elite when it is added as elite" do
          run(PF2EncounterAddCmd, 'e/add elite goblin warrior')

          expect(@client.failures).to eq []
          expect(npc(2).adjustment).to eq 'elite'
          expect(npc(2).stat_block['ac']).to eq 18
          expect(npc(2).max_hp).to eq 16
          expect(npc(2).pf2_level).to eq 1
        end

        it "should be weak when it is added as weak" do
          run(PF2EncounterAddCmd, 'e/add 2 weak skeleton guard')

          expect([ npc(2), npc(3) ].map(&:adjustment)).to eq %w{weak weak}
          expect(npc(2).stat_block['ac']).to eq 14
        end

        it "should still be found by its own name where no adjustment is named" do
          run(PF2EncounterAddCmd, 'e/add goblin warrior')

          expect(npc(2).adjustment).to be_nil
          expect(npc(2).stat_block['ac']).to eq 16
        end

        # Hellbreakers has an Elite Ort of its own, beside its Ort.
        it "should be the bestiary's own creature where one is called that" do
          run(PF2EncounterAddCmd, 'e/add elite ort')

          expect(@client.failures).to eq []
          expect(npc(2).creature).to eq 'Elite Ort'
          expect(npc(2).adjustment).to be_nil
        end

        it "should keep the name the GM gives it" do
          run(PF2EncounterAddCmd, 'e/add elite goblin warrior=Grik')

          expect(npc(2).name).to eq 'Grik'
          expect(npc(2).adjustment).to eq 'elite'
        end
      end

      describe "made elite or weak once it is fighting" do
        before(:each) do
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          run(PF2EncounterAddCmd, 'e/add goblin warrior')
          @client.said.clear
        end

        it "should take the adjustment" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')

          expect(@client.failures).to eq []
          expect(npc(2).adjustment).to eq 'elite'
          expect(npc(3).adjustment).to be_nil
        end

        it "should keep the hit points it has lost" do
          Harm.damage(npc(2), 4)

          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')

          expect(npc(2).hp_left).to eq 12
        end

        it "should be down where becoming weak leaves it nothing" do
          run(PF2EncounterAddCmd, 'e/add Rat=ac 15 hp 12 level 1')
          Harm.damage(npc(4), 5)

          run(PF2EncounterAdjustCmd, 'e/adjust #4=weak')

          expect(npc(4).max_hp).to eq 2
          expect(npc(4).hp_left).to eq 0
        end

        it "should adjust several at once" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2,#3=weak')

          expect([ npc(2), npc(3) ].map(&:adjustment)).to eq %w{weak weak}
        end

        it "should be taken off again" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')
          run(PF2EncounterAdjustCmd, 'e/adjust #2=normal')

          expect(npc(2).adjustment).to be_nil
          expect(npc(2).stat_block['ac']).to eq 16
        end

        it "should tell the GM, and not the room" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')

          expect(@client.said).to eq [ t('pf2e.adjust_ok', :who => 'Goblin Warrior #2', :adjustment => 'elite') ]
        end

        it "should strike as adjusted" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')
          @client.said.clear

          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

          # Dogslicer +7 and 1d6 slashing, two more of each: 15 on the die and 9, 5 on the die and 2.
          expect(heard).to include('24')
          expect(heard).to include('7 slashing')
        end

        it "should count for the encounter's difficulty at its adjusted level" do
          before = Difficulty.shown(encounter)

          run(PF2EncounterAdjustCmd, 'e/adjust #2,#3=elite')

          expect(Difficulty.shown(encounter)).to_not eq before
        end

        it "should show in the GM's scan and stat block" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')
          @client.said.clear

          run(PF2EncounterScanCmd, 'e/scan')
          run(PF2EncounterCreatureCmd, 'e/creature #2')

          expect(heard).to match(/Goblin Warrior #2\s*%bElite 1/)
          expect(heard).to include('Elite Creature 1')
        end

        it "should be taken back with the change before it" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')
          run(PF2EncounterUndoCmd, 'e/undo')

          expect(npc(2).adjustment).to be_nil
        end

        it "should be the GM's to do" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite', @hero)

          expect(@client.failures).to eq [ t('pf2e.not_organizer') ]
          expect(npc(2).adjustment).to be_nil
        end

        it "should refuse an adjustment there is not" do
          run(PF2EncounterAdjustCmd, 'e/adjust #2=mighty')

          expect(@client.failures).to eq [ t('pf2e.adjust_unknown', :adjustment => 'mighty', :options => 'elite, weak, normal') ]
        end

        it "should refuse to adjust a character" do
          run(PF2EncounterAdjustCmd, "e/adjust #{@hero.name}=elite")

          expect(@client.failures).to eq [ t('pf2e.adjust_not_creature', :who => @hero.name) ]
        end
      end

      describe "of the GM's own making" do
        def add(description)
          run(PF2EncounterAddCmd, "e/add Bandit=#{description}")
        end

        it "should fight with the Strike it was given" do
          add('ac 16 hp 20 fort 6 ref 8 will 4 perception 5 level 1; strike shortsword +9 1d6+4 piercing (agile, finesse)')
          full = Pf2eHP.get_current_hp(hero)
          @client.said.clear

          run(PF2EncounterAsCmd, "e/as #2=strike #{@hero.name}")

          expect(@client.failures).to eq []
          expect(heard).to include('Shortsword', '24')
          expect(Pf2eHP.get_current_hp(hero)).to eq full - 9
        end

        it "should resist what it was given to resist, and be hurt more by what it is weak to" do
          add('ac 16 hp 40; resist slashing 3; weak fire 5; immune poison')

          expect(Harm.damage(npc(2), 10, 'slashing')['amount']).to eq 7
          expect(Harm.damage(npc(2), 10, 'fire')['amount']).to eq 15
          expect(Harm.damage(npc(2), 10, 'poison')['amount']).to eq 0
        end

        it "should use the ability it was given, with its damage and its save" do
          add('ac 16 hp 40; ability Tail Sweep: Each creature within reach takes 2d6 bludgeoning damage (DC 30 basic Reflex save).')
          full = Pf2eHP.get_current_hp(hero)
          @client.said.clear

          run(PF2EncounterAsCmd, "e/as #2=act tail sweep=#{@hero.name}")

          expect(@client.failures).to eq []
          expect(heard).to include('Tail Sweep', 'Reflex')
          expect(Pf2eHP.get_current_hp(hero)).to be < full
        end

        it "should be made elite like any other" do
          add('ac 16 hp 40 level 3; strike jaws +10 1d8+4 piercing')

          run(PF2EncounterAdjustCmd, 'e/adjust #2=elite')

          expect(npc(2).stat_block['ac']).to eq 18
          expect(npc(2).max_hp).to eq 55
        end

        it "should come in elite when it is added as elite" do
          run(PF2EncounterAddCmd, 'e/add elite Bandit=ac 16 hp 40 level 3')

          expect(npc(2).name).to start_with 'Bandit'
          expect(npc(2).adjustment).to eq 'elite'
        end

        it "should say which part of a description it could not read, and add nothing" do
          add('ac 16 hp 40; strike jaws +10')

          expect(@client.failures).to eq [ t('pf2e.described_strike', :words => 'jaws +10', :parts => Described::PARTS.keys.join(', ')) ]
          expect(encounter.npcs.to_a).to eq []
        end

        it "should show the GM the stat block it was given" do
          add('ac 16 hp 40 level 3; resist slashing 3; strike jaws +10 1d8+4 piercing')
          @client.said.clear

          run(PF2EncounterCreatureCmd, 'e/creature #2')

          expect(heard).to include('Resistances slashing 3', 'Melee Jaws +10, 1d8+4 piercing')
        end
      end
    end
  end
end
