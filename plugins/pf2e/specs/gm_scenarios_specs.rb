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

    # Encounters played whole under each kind of GM who is not staff: an event runner - any approved
    # character - with Monster Core's creatures made elite and weak, and a Plotmaster with a creature of
    # their own making and one from another book. Each is two fights, played as the staff-run ones are,
    # with what that kind of GM may and may not do tried in each.
    #
    # Set SCENARIO_OUT to a directory to keep each scenario's transcript and report there.
    describe "encounters played under each kind of GM", :dbtest => true do

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

      def play(kind, level)
        @runner = ScenarioRunner.new("#{kind} level #{level}", level: level, seats: ScenarioParties::PARTIES[level],
                                                               waves: ScenarioParties::GM_FIGHTS[kind][level], gm_kind: kind)
        heard_by(@runner)
        audited(@runner.audit)

        @runner.run!
        keep(@runner, "gm-#{kind}-#{level}")
        @runner
      end

      ScenarioParties::GM_FIGHTS.each_pair do |kind, fights|
        fights.each_key do |level|
          it "should play a level #{level} party through two encounters run by a #{kind}" do
            runner = play(kind, level)

            expect(Gm.kind(Character[runner.gm.id])).to eq({ :runner => 'event runner', :plotmaster => 'Plotmaster' }[kind])
            expect(runner.errors.map { |one| "#{one.who}: #{one.text} -> #{one.status}" }).to eq []
            expect(runner.audit.findings.map(&:to_s)).to eq []
            expect(runner.encounters.size).to eq 2
          end
        end
      end
    end
  end
end
