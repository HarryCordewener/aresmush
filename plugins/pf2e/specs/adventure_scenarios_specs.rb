require "plugin_test_loader"
require_relative "support/auto_builder"
require_relative "support/roll_audit"
require_relative "support/interaction_probes"
require_relative "support/exploration_play"
require_relative "support/scenario_runner"
require_relative "support/scenario_parties"
require_relative "support/scenario_play"

module AresMUSH
  module Pf2e

    # Five adventures played in a scene, at levels 1, 6, 11, 16 and 20: the GM starts the scene, the
    # party explores, fights, explores and recovers, fights again, and the GM stops the scene. Each fight
    # starts from the exploration before it, and the scene's own log is read back for what it kept.
    #
    # Set SCENARIO_OUT to a directory to keep each adventure's transcript, report and scene log there.
    describe "adventures played in a scene", :dbtest => true do

      include ScenarioPlay

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        # A pose reads with the engine's own words, which the game loads as it starts and a spec does not.
        # Stored straight into the translations, which another spec reloading them cannot undo.
        engine_words = YAML.load_file(File.join(AresMUSH.engine_path, 'locales', 'locale_en.yml'))['en']
        I18n.backend.store_translations(:en, engine_words)

        # The scene's log is written for real; only what it would tell web clients and a game's other
        # players is stubbed. A pose is logged when its event is handled, which here is at once.
        allow(Global).to receive(:client_monitor).and_return(double(:notify_web_clients => nil, :emit_all_ooc => nil,
                                                                    :logged_in => {}, :find_client => nil,
                                                                    :web_clients => []))
        allow(Global.dispatcher).to receive(:spawn)
        allow(Global.dispatcher).to receive(:queue_timer)
        allow(Global.dispatcher).to receive(:queue_event) do |event|
          Scenes::PoseEventHandler.new.on_event(event) if event.is_a?(PoseEvent)
        end
        allow(Scenes).to receive(:create_log)
        allow(Scenes).to receive(:build_pose_order_web_data).and_return({})
        allow(Scenes).to receive(:build_scene_pose_web_data).and_return({})
        allow(Scenes).to receive(:build_live_scene_web_data).and_return({})
        allow(Scenes).to receive(:create_new_pose_notification)
        allow(Scenes).to receive(:handle_word_count_achievements)
        allow(Login).to receive(:notify)
        allow(Login).to receive(:find_game_client).and_return(nil)
      end

      after(:each) do
        @runner&.cleanup!
      end

      def play(level)
        @runner = ScenarioRunner.new("Adventure #{level}", level: level, seats: ScenarioParties::PARTIES[level],
                                                           waves: ScenarioParties::ADVENTURES[level])
        heard_by(@runner)
        audited(@runner.audit)

        @runner.adventure!(ScenarioParties::ADVENTURES[level])
        @runner.audit.safely('scene log') { @runner.scene_checks! }
        keep(@runner, "adventure-#{level}", 'scene' => @runner.scene_log, 'shared' => @runner.shared_log)
        @runner
      end

      ScenarioParties::PARTIES.each_key do |level|
        it "should play a level #{level} party through exploring, two fights and the scene's end" do
          runner = play(level)

          expect(runner.errors.map { |one| "#{one.who}: #{one.text} -> #{one.status}" }).to eq []
          expect(runner.audit.findings.map(&:to_s)).to eq []
          expect(runner.explorations.size).to eq 2
          expect(runner.encounters.size).to eq 4
        end
      end
    end
  end
end
