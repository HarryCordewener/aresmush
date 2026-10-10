require "plugin_test_loader"
require_relative "support/auto_builder"
require_relative "support/roll_audit"
require_relative "support/interaction_probes"
require_relative "support/gm_probes"
require_relative "support/exploration_play"
require_relative "support/creature_play"
require_relative "support/scenario_runner"
require_relative "support/scenario_parties"
require_relative "support/scenario_play"

module AresMUSH
  module Pf2e

    # Five parties against the creatures with the most to do, run by a GM who plays each by its stat
    # block: auras as the fight starts, a Grab the moment the Strike that lists it hits, crushing and
    # swallowing whoever is held, a breath on everyone whenever it is back, venoms, reactions, spells -
    # and players who Escape, or cut their way out. Every roll, hit and fall to nothing is audited.
    #
    # Set SCENARIO_OUT to a directory to keep each fight's transcript and report there.
    describe "encounters against creatures played by the book", :dbtest => true do

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
        @runner = ScenarioRunner.new("By the book #{level}", level: level, seats: ScenarioParties::PARTIES[level],
                                                             waves: ScenarioParties::BY_THE_BOOK[level])
        heard_by(@runner)
        audited(@runner.audit)

        @runner.run!
        keep(@runner, "book-#{level}")
        @runner
      end

      ScenarioParties::BY_THE_BOOK.each_key do |level|
        it "should play a level #{level} party against creatures using all they have" do
          runner = play(level)

          expect(runner.errors.map { |one| "#{one.who}: #{one.text} -> #{one.status}" }).to eq []
          expect(runner.audit.findings.map(&:to_s)).to eq []
          expect(runner.encounters.size).to eq 2
        end
      end
    end
  end
end
