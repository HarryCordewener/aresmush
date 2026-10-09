require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Exploration between fights is an encounter of its own, in exploration mode: no initiative and no
    # turns; each character says what they are doing as they travel, and takes the time for what takes
    # minutes - Treat Wounds. A fight started from it carries on from it, and each character's initiative
    # comes from what they were doing.
    describe "exploring", :dbtest => true do

      class ExploreClient
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
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = ExploreClient.new
        @room = Room.create(:name => "Road#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @made = [ @room, @scene, @gm ]
        @aria = hero('Aria', 'Stealth' => 'expert')
        @bram = hero('Bram', 'Medicine' => 'trained')

        @logged = []
        allow(Scenes).to receive(:add_to_scene) { |_scene, message, *_rest| @logged << message.to_s }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == @gm.id }
        @dice = 0.5
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        @scene.encounters.each(&:delete) if Scene[@scene.id]
        @made.reverse.each { |one| one.class[one.id]&.delete }
      end

      def hero(name, skills)
        char = Character.create(:name => "#{name}#{rand(1000000)}", :room => @room, :pf2_level => 1,
                                :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                                :pf2_base_info => { 'charclass' => 'Fighter' },
                                :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                   :weapon_prof => { 'unarmed' => 'trained' }, :perception => 'trained')
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 10)
        char.update(:combat => combat, :hp => hp)
        abilities = Pf2e::ABILITIES.map { |one| Pf2eAbilities.create(:character => char, :name => one, :base_val => 14) }
        known = skills.map { |skill, rank| Pf2eSkills.create(:character => char, :name => skill, :prof_level => rank) }
        @made += [ char, combat, hp ] + abilities + known
        Scene[@scene.id].participants.add char
        Character[char.id]
      end

      def run(text, who = @gm)
        command = Command.new(text)
        Pf2e.get_cmd_handler(nil, command, nil).new(@client, command, Character[who.id]).on_command
      end

      def active
        PF2Encounter.scene_active_encounter(Scene[@scene.id])
      end

      def state_of(char, encounter = active)
        CombatantStates.of(PF2Encounter[encounter.id], Character[char.id])
      end

      def explore!
        run('e/explore')
        run('e/join', @aria)
        run('e/join', @bram)
      end

      it "should start an exploration in the scene, logged there" do
        run('e/explore')

        expect(@client.failures).to eq []
        expect(active.mode).to eq 'exploration'
        expect(@logged.join).to include('EXPLORING')
      end

      it "should take a character into it without rolling initiative" do
        explore!

        expect(@client.failures).to eq []
        expect(said_lines.grep(/joins the exploration/).size).to eq 2
        expect(said_lines.join).to_not include('initiative')
      end

      it "should have no turns to move through" do
        explore!
        run('e/next')

        expect(@client.failures.join).to include(t('pf2e.explore_no_turns'))
      end

      it "should record what a character is doing as they explore, and show it" do
        explore!
        run('e/act avoid notice', @aria)
        @client.said.clear
        run('e/view')

        expect(@client.failures).to eq []
        expect(state_of(@aria).exploration_activity).to eq 'Avoid Notice'
        expect(said_lines.join).to include('Exploring', 'Activity', 'Avoid Notice')
        expect(said_lines.join).to_not include('Init')
      end

      it "should refuse an exploration activity in a fight" do
        run('e/start')
        run('e/join', @aria)
        run('e/act avoid notice', @aria)

        expect(@client.failures.join).to include(t('pf2e.explore_only', :action => 'Avoid Notice'))
      end

      it "should treat wounds while exploring, with a Medicine check against DC 15" do
        explore!
        Pf2eHP.get_hp_obj(state_of(@aria)).update(:damage => 15)
        @dice = 0.75
        run("e/act treat wounds=#{@aria.name}", @bram)

        expect(@client.failures).to eq []
        expect(said_lines.join).to include('Medicine', 'DC 15')
        expect(Pf2eHP.get_hp_obj(state_of(@aria)).damage).to eq 3
      end

      # Treat Wounds that restores Hit Points ends the wounded condition.
      it "should end wounded with a successful Treat Wounds" do
        explore!
        Pf2e.set_condition(state_of(@aria), 'Wounded', 1)
        @dice = 0.75
        run("e/act treat wounds=#{@aria.name}", @bram)

        expect(Pf2e.condition_level(state_of(@aria), 'Wounded')).to eq 0
      end

      it "should refuse to treat wounds in a fight, which takes ten minutes" do
        run('e/start')
        run('e/join', @bram)
        run("e/act treat wounds=#{@bram.name}", @bram)

        expect(@client.failures.join).to include(t('pf2e.explore_only', :action => 'Treat Wounds'))
      end

      describe "a fight starting from it" do
        before(:each) do
          explore!
          @exploring = active
          Pf2eHP.get_hp_obj(state_of(@aria)).update(:damage => 4)
          run('e/act avoid notice', @aria)
          run('e/act scout', @bram)
          run('e/start')
        end

        def fight
          active
        end

        it "should end the exploration and start the fight, carrying on from it" do
          expect(@client.failures).to eq []
          expect(PF2Encounter[@exploring.id].is_active).to be false
          expect(fight.mode).to_not eq 'exploration'
          expect(fight.carries_on_from.to_s).to eq @exploring.id.to_s
        end

        # Everyone is already in it, so the call to stop and join would mislead.
        it "should tell the room everyone exploring is in it, rather than to join" do
          expect(said_lines.join).to include('Everyone exploring is in the fight')
          expect(said_lines.join).to_not include('join the encounter')
        end

        it "should bring everyone exploring into it, as they were" do
          names = Combatants.rows(fight).map { |row| row['name'] }

          expect(names).to contain_exactly(@aria.name, @bram.name)
          expect(Pf2eHP.get_hp_obj(state_of(@aria, fight)).damage).to eq 4
        end

        # Avoid Notice rolls Stealth for initiative; a scout gives everyone else +1.
        it "should roll each initiative from what they were doing" do
          rows = Combatants.rows(fight).to_h { |row| [ row['name'], row['init'].to_i ] }
          stealth = Pf2e.initiative_bonus(Character[@aria.id], 'Stealth')
          perception = Pf2e.initiative_bonus(Character[@bram.id], 'Perception')

          expect(rows[@aria.name]).to eq 10 + stealth + 1
          expect(rows[@bram.name]).to eq 10 + perception
          expect(said_lines.join).to include('Stealth')
        end
      end

      it "should refuse to start exploring while a fight is on" do
        run('e/start')
        run('e/explore')

        expect(@client.failures.join).to include(t('pf2e.explore_fight_on', :id => active.id))
      end

      it "should carry on from the fight it follows, named" do
        run('e/start')
        fought = active
        run('e/join', @aria)
        Pf2eHP.get_hp_obj(state_of(@aria)).update(:damage => 6)
        run('e/end')
        run("e/explore=#{fought.id}")
        run('e/join', @aria)

        expect(@client.failures).to eq []
        expect(Pf2eHP.get_hp_obj(state_of(@aria)).damage).to eq 6
      end

      def said_lines
        @client.said
      end
    end
  end
end
