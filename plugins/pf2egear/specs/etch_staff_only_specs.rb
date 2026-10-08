require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # Runes are etched by staff, whose word is the only one that changes them; anyone else is refused
    # before anything about the item is looked at.
    describe "who may etch a rune", :dbtest => true do

      class StaffEtchClient
        attr_reader :failures

        def initialize
          @failures = []
        end

        def logged_in?
          true
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        def emit_success(_msg); end
        def emit(_msg); end
        def emit_ooc(_msg); end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = StaffEtchClient.new
        @char = Character.create(:name => "Etcher#{rand(1000000)}", :pf2_level => 10)
        @sword = Pf2egear.create_item(@char, 'weapons', 'Longsword', 1, Global.read_config('pf2e_weapons', 'Longsword'))
        @sword.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => { 'list' => [] } })
        @mail = Pf2egear.create_item(@char, 'armor', 'Chain Mail', 1, Global.read_config('pf2e_armor', 'Chain Mail'))
        @mail.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => { 'list' => [] } })
      end

      after(:each) do
        [ @sword, @mail, @char ].each { |one| one&.delete }
      end

      def etch(cmd_class, text)
        cmd_class.new(@client, Command.new(text), Character[@char.id]).on_command
      end

      {
        'potency' => [ PF2EtchPotencyCmd, 'etch/potency %s=weapons/0/2' ],
        'striking' => [ PF2EtchPowerCmd, 'etch/striking %s=weapons/0/1' ],
        'resilient' => [ PF2EtchPowerCmd, 'etch/resilient %s=armor/0/1' ],
        'property' => [ PF2EtchPropertyCmd, 'etch/property %s=weapons/0/Flaming' ]
      }.each_pair do |rune, (cmd_class, text)|
        it "should refuse a #{rune} rune from someone who is not staff" do
          before = [ PF2Weapon[@sword.id].runes, PF2Armor[@mail.id].runes ]

          etch(cmd_class, format(text, @char.name))

          expect(@client.failures).to eq [ t('pf2egear.rune_no_admin') ]
          expect([ PF2Weapon[@sword.id].runes, PF2Armor[@mail.id].runes ]).to eq before
        end

        it "should etch a #{rune} rune for staff" do
          allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

          etch(cmd_class, format(text, @char.name))

          expect(@client.failures).to eq []
        end
      end

      # A resilient rune goes on armour that has a potency rune at least as high.
      it "should refuse a resilient rune on armour with no potency rune" do
        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
        @mail.update(:runes => {})

        etch(PF2EtchPowerCmd, "etch/resilient #{@char.name}=armor/0/1")

        expect(@client.failures).to eq [ t('pf2egear.rune_power_gt_potency') ]
      end

      it "should say how the command is written, once, when it cannot be read" do
        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

        etch(PF2EtchPotencyCmd, 'etch/potency nonsense')

        expect(@client.failures).to eq [ t('pf2egear.rune_cmd_fail', :rune_type => 'potency') ]
      end
    end
  end
end
