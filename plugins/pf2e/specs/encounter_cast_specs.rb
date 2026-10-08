require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `+e/cast`, through the command a player types.
    #
    # A caster who names no class casts from the one they have, which the command works out from their
    # spellcasting entries. Nothing covered that, and it asked those entries for a key they do not carry,
    # so every class caster was told they had no magical ability.
    describe "casting in an encounter", :dbtest => true do

      class CastClient
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

        @client = CastClient.new
        @room = Room.create(:name => "Hall#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = Character.create(:name => "Cora#{rand(1000000)}", :room => @room, :pf2_level => 1,
                                 :pf2_conditions => {}, :pf2_traits => [], :pf2_derived => {},
                                 :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @combat = Pf2eCombat.create(:character => @hero)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 6)
        @magic = PF2Magic.create(:character => @hero,
                                 :tradition => { 'Sorcerer' => [ 'primal', 'trained' ] },
                                 :spell_abil => { 'Sorcerer' => 'Charisma' },
                                 :spells_per_day => { 'Sorcerer' => { '1' => 3 } },
                                 :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] } })
        @hero.update(:combat => @combat, :hp => @hp, :magic => @magic,
                     :pf2_base_info => { 'charclass' => 'Sorcerer' })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @hero, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1,
                                         :is_active => true)
        Combatants.join(@encounter, @hero.name, 10, :holder => Character[@hero.id])

        allow_any_instance_of(Room).to receive(:emit)
        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * 0.75).ceil, 1 ].max ] * amount.to_i }
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        (@abilities + [ @magic, @hp, @combat, @hero, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def rested
        PF2EncounterRestCmd.new(@client, Command.new('e/rest'), Character[@gm.id]).on_command
      end

      def cast(text)
        PF2EncounterCastCmd.new(@client, Command.new(text), Character[@hero.id]).on_command
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@hero.id])
      end

      def slots_left
        (standing.magic.spells_today['Sorcerer'] || {})['1']
      end

      it "should cast from their own casting class when they name none" do
        rested
        expect(slots_left).to eq 3

        cast('e/cast Charm')

        expect(@client.failures).to eq []
        expect(slots_left).to eq 2
      end

      it "should cast from the class they name" do
        rested

        cast('e/cast Charm/class Sorcerer')

        expect(@client.failures).to eq []
        expect(slots_left).to eq 2
      end

      # A character who casts as two classes casts the spell from the list that holds it.
      it "should cast from whichever of their classes knows the spell" do
        @magic.update(:tradition => { 'Sorcerer' => [ 'primal', 'trained' ], 'Bard' => [ 'occult', 'trained' ] },
                      :spell_abil => { 'Sorcerer' => 'Charisma', 'Bard' => 'Charisma' },
                      :spells_per_day => { 'Sorcerer' => { '1' => 3 }, 'Bard' => { '1' => 2 } },
                      :repertoire => { 'Sorcerer' => { '1' => [ 'Charm' ] }, 'Bard' => { '1' => [ 'Soothe' ] } })

        ordered = PF2EncounterCastCmd.new(@client, Command.new('e/cast Soothe'), Character[@hero.id])
        ordered.parse_args

        expect(ordered.casting_class(Character[@hero.id])).to eq 'Bard'
      end

      it "should say which class casts it, so the lookup cannot quietly answer nothing" do
        expect(PF2EncounterCastCmd.new(@client, Command.new('e/cast Charm'), Character[@hero.id])
                 .casting_class(Character[@hero.id])).to eq 'Sorcerer'
      end
    end
  end
end
