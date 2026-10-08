require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Actions: what one is, whose it is, and using one - which, for an action that puts an effect on its
    # user, puts them under it.
    describe "actions", :dbtest => true do

      class ActionClient
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
          "ActionClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = ActionClient.new
        @room = Room.create(:name => "Hall#{rand(1000000)}")
        @char = Character.create(:name => "Doer#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 12)
        @char.update(:combat => @combat, :hp => @hp, :pf2_level => 3, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12) }

        allow_any_instance_of(Room).to receive(:emit)
      end

      after(:each) do
        ActiveEffects.on(Character[@char.id]).each(&:delete)
        (@abilities + [ @hp, @combat, @char, @room ]).each { |one| one&.delete }
      end

      def reread
        Character[@char.id]
      end

      def run(cmd_class, text)
        cmd_class.new(@client, Command.new(text), reread).on_command
      end

      # Whatever `action/use` is dispatched to: it is `+e/act` by another name.
      def use(text)
        run(Pf2e.get_cmd_handler(@client, Command.new(text), reread), text)
      end

      def barbarian!
        @char.update(:pf2_base_info => { 'charclass' => 'Barbarian' },
                     :pf2_features => { 'charclass_features' => [ 'Rage' ], 'archetype_features' => [] })
      end

      describe "the catalogue" do
        it "should have their actions and the feats that are actions" do
          expect(Actions.catalogue.size).to be > 1000
        end

        it "should say what an action puts on whoever uses it" do
          expect(Actions.info('Rage')['self_effect']).to eq 'Effect: Rage'
        end

        it "should say what it costs" do
          expect(Actions.cost('Rage')).to eq 'one action'
        end
      end

      # What an outcome does is game config (`pf2e_action_consequences.yml`), so a GM can change what
      # Trip does without editing the importer.
      describe "what an outcome does" do
        it "should read Trip's consequences from config" do
          expect(Actions.consequences('trip')['success']).to eq [ { 'on' => 'target', 'condition' => 'Prone' } ]
        end

        it "should read a variant's by the action and the variant" do
          expect(Actions.consequences('administer-first-aid', 'stabilize')['success'].first['remove']).to eq [ 'Dying' ]
        end

        it "should key every entry on an action the catalogue holds" do
          slugs = Actions.catalogue.values.map { |one| (one['check'] || {})['slug'] }.compact
          strays = (Global.read_config('pf2e_action_consequences') || {}).keys.map { |key| key.split(':').first } - slugs

          expect(strays).to eq []
        end

        it "should not also carry them in the imported catalogue" do
          carrying = Actions.catalogue.select { |_name, one| (one['check'] || {}).key?('consequences') }

          expect(carrying.keys).to eq []
        end
      end

      describe "whose it is" do
        it "should be everyone's for a basic action" do
          expect(Actions.usable(reread, 'Take Cover').ok?).to be true
        end

        it "should not be a fighter's to Rage" do
          expect(Actions.usable(reread, 'Rage').code).to eq :not_yours
        end

        # The Rage class feature is what gives it.
        it "should be a barbarian's, who has the feature it comes from" do
          barbarian!

          expect(Actions.usable(reread, 'Rage').ok?).to be true
        end

        it "should be the owner's of a feat that is an action" do
          expect(Actions.usable(reread, 'Mountain Stance').ok?).to be false

          @char.update(:pf2_feats => { 'class' => [ 'Mountain Stance' ] })

          expect(Actions.usable(reread, 'Mountain Stance').ok?).to be true
        end

        # A class, heritage or background can hand over an action by name: an investigator's Devise a
        # Stratagem, written however the class data capitalises it.
        it "should be the character's when their class gives it them by name" do
          expect(Actions.usable(reread, 'Devise a Stratagem').ok?).to be false

          @char.update(:pf2_actions => { 'actions' => [ 'Devise A Stratagem' ], 'reactions' => [ 'Clue In' ] })

          expect(Actions.usable(reread, 'Devise a Stratagem').ok?).to be true
          expect(Actions.usable(reread, 'Clue In').ok?).to be true
        end
      end

      it "should do nothing outside an encounter" do
        use("action/use take cover")

        expect(@client.failures).to eq [ t('pf2e.no_encounter_here') ]
      end

      # In an encounter, on the user as they stand in it.
      describe "using one" do
        before(:each) do
          @scene = Scene.create(:room => @room)
          @room.update(:scene => @scene)
          @encounter = PF2Encounter.create(:scene => @scene, :organizer => 'GM', :round => 1, :is_active => true)
          Combatants.join(@encounter, @char.name, 10, :holder => reread)

          allow(Scenes).to receive(:add_to_scene)
        end

        after(:each) do
          @encounter&.delete
          @scene&.delete
        end

        def standing
          CombatantStates.of(@encounter, reread)
        end

        it "should put its effect on the one who uses it" do
          barbarian!

          use("action/use rage")

          expect(@client.failures).to eq []
          expect(ActiveEffects.on(standing).map(&:name)).to eq [ 'Effect: Rage' ]
          expect(ActiveEffects.on(reread)).to eq []
        end

        # Rage's temporary hit points are its effect's, and come with it.
        it "should bring everything the effect does" do
          barbarian!

          use("action/use rage")

          expect(standing.temp_hp).to eq 3 + 1
        end

        it "should refuse an action the character does not have, and put nothing on them" do
          use("action/use rage")

          expect(@client.failures.join).to include 'Rage'
          expect(ActiveEffects.on(standing)).to eq []
        end

        it "should let anyone use a basic action and take on its effect" do
          use("action/use take cover")

          expect(ActiveEffects.on(standing).map(&:name)).to eq [ 'Effect: Cover' ]
        end

        # A raised shield's bonus is the shield's own, and a broken one gives none.
        describe "Raise a Shield" do
          before(:each) do
            @shield = PF2Shield.create(:name => 'Steel Shield', :state => standing, :equipped => true, :ac_bonus => 2,
                                       :hp => 20, :hardness => 5)
          end

          after(:each) { @shield.delete }

          it "should add the shield's circumstance bonus to AC while it is raised" do
            ac = Stat.total(standing, 'ac')

            use("action/use raise a shield")

            expect(Stat.total(standing, 'ac')).to eq ac + 2
          end

          it "should add nothing while it is not raised" do
            expect(Stat.of(standing, 'ac')['modifiers'].map { |row| row['slug'] }).to_not include('raised-shield')
          end

          it "should add nothing from a broken shield" do
            @shield.update(:damage => 10)
            ac = Stat.total(standing, 'ac')

            use("action/use raise a shield")

            expect(Stat.total(standing, 'ac')).to eq ac
          end
        end

        it "should announce an action with no effect of its own" do
          use("action/use stride")

          expect(@client.failures).to eq []
          expect(ActiveEffects.on(standing)).to eq []
        end

        it "should be the same command as +e/act" do
          expect(Pf2e.get_cmd_handler(nil, Command.new('action/use rage'), nil)).to eq PF2EncounterActCmd
        end
      end

      # What a character can use, by mode of play.
      describe "what is available" do
        def available(mode = nil)
          Actions.available(reread, mode)
        end

        it "should list everyone's actions for anyone" do
          expect(available).to include 'Take Cover', 'Stride'
        end

        it "should not list what the character does not have" do
          expect(available).to_not include 'Rage'
        end

        it "should list what their features give them" do
          barbarian!

          expect(available).to include 'Rage'
        end

        it "should leave out what is passive, since it is not used" do
          passive = Actions.catalogue.find { |_name, info|
            info['type'] == 'passive' && info['for'] == 'everyone' && !Actions.activity?(info)
          }

          expect(passive).to_not be_nil
          expect(available).to_not include passive.first
        end

        # Foundry files an exploration activity as passive, because it costs no actions.
        it "should list an activity, which is used though it costs no actions" do
          expect(Actions.cost('Avoid Notice')).to eq 'activity'
          expect(available).to include 'Avoid Notice'
        end

        it "should keep exploration to exploration activities" do
          expect(available('exploration')).to include 'Avoid Notice'
          expect(available('exploration')).to_not include 'Stride'
        end

        it "should keep combat to what is not exploration or downtime" do
          expect(available('combat')).to include 'Stride'
          expect(available('combat')).to_not include 'Avoid Notice', 'Earn Income'
        end

        it "should keep downtime to downtime activities" do
          expect(available('downtime')).to include 'Earn Income'
        end

        it "should keep reactions to reactions" do
          expect(available('reactions').map { |name| Actions.info(name)['type'] }.uniq).to eq [ 'reaction' ]
        end

        # `action/available/combat` arrives as one switch, `available/combat`.
        it "should take the mode from a second switch or from the argument" do
          run(PF2ActionAvailableCmd, "action/available/exploration")
          run(PF2ActionAvailableCmd, "action/available downtime")

          expect(@client.failures).to eq []
          expect(@client.said.first).to include 'Exploration Actions', 'Avoid Notice'
          expect(@client.said.last).to include 'Downtime Actions', 'Earn Income'
        end

        it "should say what modes there are for one it does not know" do
          run(PF2ActionAvailableCmd, "action/available/naptime")

          expect(@client.failures.join).to include 'exploration'
        end

        it "should mark what puts an effect on the character" do
          run(PF2ActionAvailableCmd, "action/available combat")

          expect(@client.said.first).to include 'Take Cover*'
        end
      end

      describe "the display" do
        def shown(name)
          PF2ActionViewTemplate.new(reread, name).render
        end

        it "should offer the command that takes the effect on" do
          barbarian!

          expect(shown('Rage')).to include 'action/use Rage', 'Effect: Rage'
        end

        it "should not offer it to someone who does not have the action" do
          expect(shown('Rage')).to_not include 'action/use'
          expect(shown('Rage')).to include 'You do not have this action'
        end

        it "should show a feat's own text for a feat that is an action" do
          expect(shown('Mountain Stance')).to include 'implacable mountain', 'Stance: Mountain Stance'
        end

        it "should say how often it can be used" do
          often = Actions.catalogue.find { |_name, info| info['frequency'] && info['frequency']['per'] == 'day' }.first

          expect(shown(often)).to include 'once per day'
        end
      end
    end
  end
end
