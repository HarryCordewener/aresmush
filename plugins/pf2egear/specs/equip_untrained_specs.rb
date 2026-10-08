require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # `equip`: armour or a weapon the wearer is untrained in can be equipped, and they are told what
    # it costs them, since nothing else on the way to a fight says so.
    describe "equipping what one is untrained in", :dbtest => true do

      class EquipClient
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

        @client = EquipClient.new
        @char = Character.create(:name => "Wearer#{rand(1000000)}", :pf2_base_info => { 'charclass' => 'Cleric' })
        @combat = Pf2eCombat.create(:character => @char,
                                    :armor_prof => { 'unarmored' => 'expert', 'light' => 'trained' },
                                    :weapon_prof => { 'simple' => 'trained', 'unarmed' => 'trained' })
        @char.update(:combat => @combat)
        @items = []
      end

      after(:each) do
        @items.each { |one| one.class[one.id]&.delete }
        @combat.delete
        @char.delete
      end

      def equip(category, name)
        @items << Pf2egear.create_item(Character[@char.id], category, name, 1,
                                       Global.read_config(Inventory.row(category)['config'], name))
        index = Inventory.held(Character[@char.id], category).count - 1

        PF2GearEquipCmd.new(@client, Command.new("equip #{category}=#{index}"), Character[@char.id]).on_command
      end

      it "should equip armour they are untrained in and say their proficiency adds nothing to AC" do
        equip('armor', 'Breastplate')

        expect(@client.failures).to eq []
        expect(@client.said).to include(t('pf2egear.equip_untrained_armor', :name => 'Breastplate', :kind => 'medium'))
      end

      it "should say the same of a weapon's attack rolls" do
        equip('weapons', 'Warhammer')

        expect(@client.said).to include(t('pf2egear.equip_untrained_weapon', :name => 'Warhammer'))
      end

      it "should say nothing more of what they are trained in" do
        equip('armor', 'Leather')
        equip('weapons', 'Mace')

        expect(@client.said.count).to eq 2
      end
    end
  end
end
