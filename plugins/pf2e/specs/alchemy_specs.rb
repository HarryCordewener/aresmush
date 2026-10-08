require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An alchemist's preparations: a list on the sheet, made into the day's items by a rest, with what is
    # left over spent on Quick Alchemy in an encounter.
    describe Alchemy, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Alch#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {},
                                 :pf2_reagents => { 'alchemist' => [ 3, 0, 3 ] }, :pf2_alchemy_plan => {},
                                 :pf2_formula_book => { 'consumables' => [ "Alchemist's Fire (Lesser)" ] },
                                 :pf2_features => { 'charclass_features' => [ 'Advanced Alchemy' ] })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @char.name, 10, :holder => Character[@char.id])
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        PF2Consumable.find(:character_id => @char.id).each(&:delete)
        (@abilities + [ @hp, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@char.id])
      end

      def prepare(name = "alchemist's fire (lesser)", many = 2)
        Alchemy.prepare!(char, name, many)
      end

      it "should take what they plan to make, and say what their reagents allow" do
        expect(prepare.ok?).to be true
        expect(Alchemy.plan(char)).to eq("Alchemist's Fire (Lesser)" => 2)

        expect(prepare("alchemist's fire (lesser)", 9).code).to eq :no_reagents
      end

      # What their reagents will make is their level and Intelligence, whether or not they have rested
      # since they gained them.
      it "should plan against what their reagents will make, before they have ever rested" do
        char.update(:pf2_reagents => { 'alchemist' => [ 0, 0, 0 ] }, :pf2_base_info => { 'charclass' => 'Alchemist' })

        expect(Alchemy.capacity(char)).to eq 5
        expect(prepare("alchemist's fire (lesser)", 10).ok?).to be true
        expect(prepare("alchemist's fire (lesser)", 1).code).to eq :no_reagents
      end

      it "should give an alchemist their level and Intelligence in batches at a rest" do
        char.update(:pf2_base_info => { 'charclass' => 'Alchemist' })

        Pf2e.rest(standing)

        expect(Alchemy.batches(standing)).to eq 5
      end

      # An alchemist is one by their class's Advanced Alchemy, whether or not anything recorded their reagents.
      it "should give an alchemist reagents at a rest though none were recorded" do
        char.update(:pf2_reagents => {}, :pf2_base_info => { 'charclass' => 'Alchemist' })
        standing.update(:pf2_reagents => {})

        Pf2e.rest(standing)

        expect(Alchemy.batches(standing)).to eq 5
        expect(Alchemy.left(standing)).to eq 5
      end

      it "should refuse what is not alchemical, what is too high a level, and what they cannot make" do
        expect(prepare('gecko potion', 1).code).to eq :not_alchemical
        expect(prepare("alchemist's fire (greater)", 1).code).to eq :too_high
        expect(prepare('acid flask (lesser)', 1).code).to eq :no_formula
      end

      it "should refuse anyone who is not an alchemist" do
        char.update(:pf2_reagents => {}, :pf2_features => { 'charclass_features' => [] })

        expect(prepare.code).to eq :not_alchemist
      end

      describe "at a rest" do
        before(:each) { prepare }

        it "should make what was prepared, to last until the next preparations" do
          made = Pf2e.rest(standing)

          fire = standing.consumables.to_a.find { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect(fire.quantity).to eq 2
          expect([ fire.granted_by, fire.expires ]).to eq [ 'advanced alchemy', 'rest' ]
          expect(made.map { |one| one['key'] }).to include('pf2e.alchemy_prepared')
        end

        it "should spend the reagents it took, leaving the rest for Quick Alchemy" do
          Pf2e.rest(standing)

          expect(Alchemy.left(standing)).to eq 2
        end

        it "should let what it made lapse at the next rest, and make it again" do
          Pf2e.rest(standing)
          Pf2e.rest(standing)

          fire = standing.consumables.to_a.select { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect(fire.map(&:quantity)).to eq [ 2 ]
        end
      end

      describe "Quick Alchemy" do
        it "should make one on the spot, spending a batch, until their next turn" do
          made = Alchemy.quick!(standing, "alchemist's fire (lesser)")

          expect(made.ok?).to be true
          fire = standing.consumables.to_a.find { |one| one.name == "Alchemist's Fire (Lesser)" }
          expect([ fire.quantity, fire.expires ]).to eq [ 1, 'turn' ]
          expect(Alchemy.left(standing)).to eq 2

          Turns.turn_started(PF2Encounter[@encounter.id], @char.name, 2)

          expect(standing.consumables.to_a).to eq []
        end

        it "should refuse once the day's reagents are gone" do
          3.times { Alchemy.quick!(standing, "alchemist's fire (lesser)") }

          expect(Alchemy.quick!(standing, "alchemist's fire (lesser)").code).to eq :no_reagents_left
        end
      end
    end
  end
end
