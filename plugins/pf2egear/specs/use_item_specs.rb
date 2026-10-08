require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # `use`: a consumable is used one at a time, and the last one used is gone.
    describe "using an item", :dbtest => true do

      class UseItemClient
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

        @client = UseItemClient.new
        @room = Room.create(:name => "Larder#{rand(1000000)}")
        @char = Character.create(:name => "Drinker#{rand(1000000)}", :room => @room)
        @potion = PF2Consumable.create(:name => 'Healing Potion (Minor)', :quantity => 2, :character => @char)

        allow_any_instance_of(Room).to receive(:emit)
        allow(Login).to receive(:update_notification_count)
      end

      after(:each) do
        Character[@char.id].login_notices.each(&:delete)
        [ PF2Consumable[@potion.id], Character[@char.id], @room ].each { |one| one&.delete }
      end

      def use
        PF2UseItemCmd.new(@client, Command.new('use consumables=0'), Character[@char.id]).on_command
      end

      it "should use one at a time" do
        use

        expect(@client.failures).to eq []
        expect(PF2Consumable[@potion.id].quantity).to eq 1
      end

      it "should be gone once the last is used" do
        use
        use

        expect(@client.failures).to eq []
        expect(PF2Consumable[@potion.id]).to be_nil
        expect(@client.said.join).to include(t('pf2egear.item_destroyed', :name => 'Healing Potion (Minor)'))
      end
    end
  end
end
