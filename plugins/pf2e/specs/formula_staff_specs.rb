require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `formulas/add` and `formulas/remove`: staff giving a character a formula, and taking it back.
    describe "staff giving formulas", :dbtest => true do

      class FormulaStaffClient
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

        @client = FormulaStaffClient.new
        @staff = Character.create(:name => "Staff#{rand(1000000)}")
        @char = Character.create(:name => "Crafter#{rand(1000000)}", :pf2_level => 5)
        allow_any_instance_of(Character).to receive(:has_permission?).and_return(false)
        allow_any_instance_of(Character).to receive(:has_permission?).with('manage_sheet') { |char, _| char.id == @staff.id }
      end

      after(:each) do
        Character[@char.id]&.grants&.each(&:delete)
        [ @char, @staff ].each { |one| Character[one.id]&.delete }
      end

      def run(cmd_class, text, who = @staff)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      it "should give a character the formula" do
        run(PF2FormulaAddCmd, "formulas/add #{@char.name}=consumables/Alchemist's Fire (Lesser)")

        expect(@client.failures).to eq []
        expect(Crafting.known?(Character[@char.id], 'consumables', "Alchemist's Fire (Lesser)")).to be true
      end

      it "should take it back" do
        run(PF2FormulaAddCmd, "formulas/add #{@char.name}=consumables/Alchemist's Fire (Lesser)")
        run(PF2FormulaRemoveCmd, "formulas/remove #{@char.name}=consumables/Alchemist's Fire (Lesser)")

        expect(@client.failures).to eq []
        expect(Crafting.known?(Character[@char.id], 'consumables', "Alchemist's Fire (Lesser)")).to be false
      end

      it "should say so when there is nobody by that name" do
        run(PF2FormulaAddCmd, "formulas/add Nobody#{rand(1000000)}=consumables/Alchemist's Fire (Lesser)")

        expect(@client.failures).to eq [ t('pf2e.not_found') ]
      end

      it "should be staff's alone" do
        run(PF2FormulaAddCmd, "formulas/add #{@char.name}=consumables/Alchemist's Fire (Lesser)", @char)

        expect(@client.failures).to eq [ t('dispatcher.not_allowed') ]
      end
    end
  end
end
