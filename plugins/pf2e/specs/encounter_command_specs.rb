require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `encounter/next`, through the command a DM types.
    #
    # It raised on a name nothing defined after announcing the turn and before saving where the order
    # stood, so the order never moved: every `encounter/next` announced the same turn again. It is also
    # where time passes for an effect, so both are held here against the real command.
    describe "moving an encounter on", :dbtest => true do

      class TurnClient
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

        %w{emit_success emit emit_ooc}.each do |name|
          define_method(name) { |msg| @said << msg.to_s }
        end

        def to_s
          "TurnClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = TurnClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene) if @room.respond_to?(:scene=)
        @dm = Character.create(:name => "DM#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {},
                                 :pf2_derived => {}, :pf2_feats => {})
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @dm.name, :round => 0,
                                         :participants => [ [ 20.0, @hero.name ], [ 10.0, 'Goblin' ] ])

        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
        allow_any_instance_of(Room).to receive(:emit)
        allow(Scenes).to receive(:add_to_scene)
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
      end

      after(:each) do
        Pf2e::ActiveEffects.on(Character[@hero.id]).each(&:delete)
        [ @encounter, @hero, @dm, @scene, @room ].each { |one| one&.delete }
      end

      def advance
        PF2EncounterNextCmd.new(@client, Command.new("encounter/next #{@encounter.id}"), Character[@dm.id])
                           .on_command
        @encounter = PF2Encounter[@encounter.id]
      end

      it "should move the order on" do
        advance
        advance

        expect(@client.failures).to eq []
        expect(@encounter.round).to eq 1
        expect(Pf2e::ActiveEffects.current_turn(@encounter)).to eq 'Goblin'
      end

      it "should start a new round when the order comes round" do
        3.times { advance }

        expect(@encounter.round).to eq 2
        expect(Pf2e::ActiveEffects.current_turn(@encounter)).to eq @hero.name
      end

      # One round, ending as the turn it began on starts again.
      it "should end an effect whose time is up, and say so" do
        advance

        Pf2e::ActiveEffects.apply(Character[@hero.id], 'Effect: Adamantine Body', :encounter => @encounter)

        2.times { advance }

        expect(Pf2e::ActiveEffects.on(Character[@hero.id])).to eq []
      end
    end
  end
end
