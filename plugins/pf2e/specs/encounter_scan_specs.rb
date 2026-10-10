require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `+e/scan` is the GM's table of everyone in the encounter as they stand: each character, and each
    # creature with its figures and what it resists. A creature's figures are the GM's alone.
    describe "an encounter's scan", :dbtest => true do

      class ScanClient
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

        @client = ScanClient.new
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
                     :pf2_features => { 'charclass_features' => [ 'Reactive Strike' ], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @scene.participants.add @hero

        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow(Login).to receive(:notify)
        allow(Login).to receive(:emit_ooc_if_logged_in)

        run(PF2InitiateCombatCmd, 'encounter')
        run(PF2InitJoinCmd, "encounter/join #{encounter.id}", @hero)
        run(PF2EncounterAddCmd, 'e/add skeleton guard')
        run(PF2EncounterAddCmd, 'e/add goblin warrior')
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

      # The scan's row for whoever's name starts it, as the words on it.
      def row(name)
        found = @client.said.join("\n").gsub(/%x(?:\d{1,3}|[a-z])|%b/i, ' ').split(/%r|\n/).find { |line| line.strip.start_with?(name) }

        found.to_s.split
      end

      def scan
        @client.said.clear
        run(PF2EncounterScanCmd, 'e/scan')
        @client.said.join("\n")
      end

      it "should list each character with the id they are targeted by" do
        scan

        expect(row('#1')).to include(@hero.name, 'Fighter')
      end

      it "should list each creature with its level and its figures" do
        scan

        # Skeleton Guard: AC 16, Perception +2, Fortitude +2, Reflex +8, Will +2, 4 hit points.
        expect(row('#2').join(' ')).to match(/Skeleton Guard.* Creature -1 .*4 \/ 4.* 16 \+2 \+2 \+8 \+2/)
      end

      it "should show a creature's figures as they stand" do
        Pf2e.set_condition(npc(2), 'Frightened', 2)
        Harm.damage(npc(2), 3)

        scan

        expect(row('#2').join(' ')).to match(/1 \/ 4.* 14 \+0 \+0 \+6 \+0/)
      end

      it "should say what a creature is immune to and resists under its row" do
        said = scan

        expect(said).to include('Immune death-effects, disease, paralyzed, poison, unconscious, bleed')
        expect(said).to include('Resist cold 5, electricity 5, fire 5, piercing 5, slashing 5')
      end

      it "should say what a creature is weak to" do
        Combatants.add_npc(encounter, :described => { 'name' => 'Straw Man', 'level' => 1, 'ac' => 15, 'hp' => 20, 'perception' => 4,
                                                      'traits' => [], 'saves' => { 'fortitude' => 6, 'reflex' => 4, 'will' => 2 },
                                                      'weaknesses' => { 'fire' => 5 } })

        expect(scan).to include('Weak fire 5')
      end

      it "should say nothing under a creature that resists nothing" do
        scan

        expect(@client.said.join("\n")).to_not match(/Goblin Warrior[^\n]*\n\s+(Immune|Weak|Resist)/)
      end

      it "should say who has a Reactive Strike" do
        scan

        expect(row('#1').last).to eq 'Y'
        expect(row('#3').last).to eq 'N'
      end

      it "should be the GM's alone" do
        run(PF2EncounterScanCmd, 'e/scan', @hero)

        expect(@client.failures).to eq [ t('pf2e.not_organizer') ]
        expect(@client.said).to eq []
      end

      describe "a creature's stat block" do
        it "should be the GM's to read from the bestiary" do
          run(PF2EncounterCreatureCmd, 'e/creature skeleton guard')

          expect(@client.said.join).to include('AC 16')
        end

        it "should not be a player's to read from the bestiary while they are in someone's encounter" do
          run(PF2EncounterCreatureCmd, 'e/creature ravener', @hero)

          expect(@client.failures).to eq [ t('pf2e.creature_gm_only') ]
          expect(@client.said).to eq []
        end

        it "should show a player a combatant's name and what it is under, without its figures" do
          Pf2e.set_condition(npc(2), 'Frightened', 1)

          run(PF2EncounterCreatureCmd, 'e/creature #2', @hero)

          expect(@client.said.join).to include('Frightened 1')
          expect(@client.said.join).to_not include('AC 16')
        end
      end
    end
  end
end
