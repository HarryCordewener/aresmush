require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The incapacitation trait: what could take a creature out of the fight goes one degree its way where
    # it is too strong to be taken out - above twice a spell's rank, or above the level of whatever else
    # is doing it.
    describe Incapacitation do

      def creature(level)
        double(:pf2_level => level)
      end

      it "should spare a creature of more than twice a spell's rank" do
        expect(Incapacitation.spares?(%w{incapacitation mental}, creature(7), :rank => 3)).to be true
      end

      it "should not spare a creature of twice a spell's rank or less" do
        expect(Incapacitation.spares?(%w{incapacitation mental}, creature(6), :rank => 3)).to be false
      end

      it "should spare a creature of higher level than whatever else is doing it" do
        expect(Incapacitation.spares?(%w{incapacitation}, creature(6), :source => creature(5))).to be true
        expect(Incapacitation.spares?(%w{incapacitation}, creature(5), :source => creature(5))).to be false
      end

      it "should have nothing to say of what lacks the trait" do
        expect(Incapacitation.spares?(%w{mental}, creature(20), :rank => 1)).to be false
      end

      it "should move a save one degree better, and a check against them one worse" do
        expect(Incapacitation.shift(true, :theirs)).to eq 1
        expect(Incapacitation.shift(true, :against)).to eq(-1)
        expect(Incapacitation.shift(false, :theirs)).to eq 0
      end
    end

    describe "incapacitation in a fight", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @room = Room.create(:name => "Field#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        # A doru casts Charm - rank 1, incapacitation - with a spell DC of 17.
        @doru = Combatants.add_npc(@encounter, :creature => 'Doru', :initiative => 20).state['npc']

        @dice = 0.05
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow(Scenes).to receive(:add_to_scene)
      end

      after(:each) do
        PF2Encounter[@encounter.id].npcs.each(&:delete)
        [ @encounter, @gm, @scene, @room ].each { |one| one&.delete }
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      # Charm cast by the doru at a creature of the level named, which rolls a 1: what it was told.
      def charmed(level)
        victim = Combatants.add_npc(encounter, :described => { 'name' => 'Victim', 'level' => level, 'ac' => 10, 'hp' => 50,
                                                                'perception' => 0, 'traits' => [],
                                                                'saves' => { 'fortitude' => 0, 'reflex' => 0, 'will' => 0 } },
                                               :initiative => 5).state['npc']
        doru = Combatants.find(encounter, "##{@doru.number}").state
        target = Combatants.find(encounter, "##{victim.number}").state
        scene = Acting::Scene.new(encounter, doru, target, @gm, true)

        Telling.lines(Acting.cast(scene, 'Charm', [ target ], []).state['lines']).join("\n")
      end

      # A stat block lists a spell with how it is cast: `Charm (At Will)`.
      it "should cast a spell its stat block lists with a note after its name" do
        victim = Combatants.add_npc(encounter, :described => { 'name' => 'Victim', 'level' => 1, 'ac' => 10, 'hp' => 50,
                                                                'perception' => 0, 'traits' => [],
                                                                'saves' => { 'fortitude' => 0, 'reflex' => 0, 'will' => 0 } },
                                               :initiative => 5).state['npc']
        doru = Combatants.find(encounter, "##{@doru.number}").state
        target = Combatants.find(encounter, "##{victim.number}").state
        scene = Acting::Scene.new(encounter, doru, target, @gm, true)

        told = Telling.lines(Acting.cast(scene, 'Charm (At Will)', [ target ], []).state['lines']).join("\n")

        expect(told).to include('casts Charm at rank 1', 'rolls Will')
      end

      # `Dominate (At Will) (See Dominate)`: how it is cast, and where the creature's own words on it are.
      it "should know a spell listed with more than one note after its name" do
        expect(Acting.spell_mechanics('Charm (At Will) (See Charm)').first).to eq 'Charm'
      end

      it "should leave a creature of twice the spell's rank or less with the outcome it rolled" do
        expect(charmed(2).gsub(/%x\w/, '')).to include('critical failure')
      end

      it "should give a creature above twice the spell's rank one degree better, and say why" do
        told = charmed(3)

        expect(told.gsub(/%x\w/, '')).to match(/vs DC 17 - failure/)
        expect(told).to include(t('pf2e.act_incapacitation', :target => 'Victim #2').strip)
      end
    end
  end
end
