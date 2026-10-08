require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Characters approved before choices were kept in the ledger lost the record of what they chose.
    # Where the choice left something on the sheet - a cleric's domain, in the focus spell it granted -
    # `ChoiceRecovery` records it again; where it left nothing - Assurance's skill - it says so, for staff
    # to set with `admin/set <character>/choice`.
    describe ChoiceRecovery, :dbtest => true do

      class RecoveryClient
        attr_reader :failures

        def initialize
          @failures = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        def emit_success(_message); end
        def emit_ooc(_message); end
        def emit(_message); end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Lost#{rand(1000000)}")
        @staff = Character.create(:name => "Staff#{rand(1000000)}")
        builder = AutoBuilder.new(@char)
        builder.build_level_one('Cleric', ancestry: 'Human', heritage: 'Versatile', background: 'Scholar')
        builder.advance_to(3)

        @domain = Pf2e.choice_for(char, 'Domain Initiate')
        @skill = Pf2e.choice_for(char, 'Assurance')

        # As a character approved before the fix stands: the choices were never written.
        Ledger.revert_matching!(char, 'make_choice', {}, :by => 'lost')
      end

      after(:each) do
        Character[@char.id]&.delete
        @staff.delete
      end

      def char
        Character[@char.id]
      end

      it "should start with the choices lost" do
        expect(@domain).to_not be_nil
        expect(Pf2e.choice_for(char, 'Domain Initiate')).to be_nil
      end

      it "should record a choice again from what it granted" do
        found = ChoiceRecovery.recover!(char)

        expect(found['recovered']).to include('Domain Initiate' => @domain)
        expect(Pf2e.choice_for(char, 'Domain Initiate')).to eq @domain
      end

      it "should name a choice that left nothing to read it from" do
        expect(ChoiceRecovery.recover!(char)['unresolved']).to include('Assurance')
        expect(Pf2e.choice_for(char, 'Assurance')).to be_nil
      end

      it "should leave a choice already recorded alone" do
        ChoiceRecovery.recover!(char)

        expect(ChoiceRecovery.recover!(char)['recovered']).to eq({})
      end

      it "should let staff set one it could not read" do
        allow_any_instance_of(Character).to receive(:has_permission?).and_return(true)
        client = RecoveryClient.new

        PF2AdminSetCmd.new(client, Command.new("admin/set #{char.name}/choice = Assurance: #{@skill}"), Character[@staff.id]).on_command

        expect(client.failures).to eq []
        expect(Pf2e.choice_for(char, 'Assurance')).to eq @skill
      end
    end
  end
end
