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

    # Five encounters played whole, through the commands a GM and four players type: a party built
    # through chargen and advancement, outfitted from the shops, two fights of moderate threat for their
    # level, the second carrying on from the first. Each player tries everything their sheet gives them -
    # their weapons, their class's actions, their spells, their items - and the scenario's report says
    # how each went.
    #
    # Set SCENARIO_OUT to a directory to keep each scenario's transcript and report there.
    describe "encounters played through", :dbtest => true do

      include ScenarioPlay

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Scenes).to receive(:add_to_scene)
        allow(Scenes).to receive(:create_log)
        allow(Global).to receive(:client_monitor).and_return(double(:notify_web_clients => nil, :emit_all_ooc => nil,
                                                                    :logged_in => {}, :find_client => nil))
      end

      after(:each) do
        @runner&.cleanup!
      end

      def play(level)
        @runner = ScenarioRunner.new("Level #{level}", level: level, seats: ScenarioParties::PARTIES[level],
                                                       waves: ScenarioParties::FIGHTS[level])
        heard_by(@runner)
        audited(@runner.audit)

        @runner.run!
        keep(@runner, "level-#{level}")
        @runner
      end

      ScenarioParties::PARTIES.each_key do |level|
        it "should play a level #{level} party through two encounters without an error" do
          runner = play(level)

          expect(runner.errors.map { |one| "#{one.who}: #{one.text} -> #{one.status}" }).to eq []
          expect(runner.audit.findings.map(&:to_s)).to eq []
          expect(runner.encounters.size).to eq 2
          runner.party.each { |char| expect(runner.tries.count { |one| one.who == char.name && one.outcome.ok? }).to be > 3 }
        end
      end
    end
  end
end
