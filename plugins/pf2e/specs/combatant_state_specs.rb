require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A character as they stand in one encounter, apart from their own neutral sheet.
    describe CombatantStates, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3, :pf2_conditions => {})
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp)
        @first = PF2Encounter.create(:organizer => 'GM', :round => 1)
        @encounters = [ @first ]
      end

      after(:each) do
        @encounters.each { |one| PF2Encounter[one.id]&.delete }
        Pf2eEffect.find(:character_id => @hero.id).each(&:delete)
        @hp.delete
        @hero.delete
      end

      def hero
        Character[@hero.id]
      end

      def joined(encounter)
        Combatants.join(encounter, @hero.name, 10, :holder => hero)
        CombatantStates.of(encounter, hero)
      end

      def second(from: nil)
        found = PF2Encounter.create(:organizer => 'GM', :round => 1, :carries_on_from => from&.id)
        @encounters << found
        found
      end

      it "should answer the sheet from the character and the fight from itself" do
        state = joined(@first)

        expect(state.name).to eq @hero.name
        expect(state.pf2_level).to eq 3

        state.update(:pf2_conditions => { 'Prone' => {} }, :pf2_level => 4)

        expect(Pf2eCombatantState[state.id].pf2_conditions).to have_key('Prone')
        expect(hero.pf2_conditions).to eq({})
        expect(hero.pf2_level).to eq 4
      end

      it "should take damage in the encounter and leave the character's own hit points whole" do
        state = joined(@first)

        Pf2eHP.modify_damage(state, 7)

        expect(Pf2eCombatantState[state.id].damage).to eq 7
        expect(Pf2eHP[@hp.id].damage).to eq 0
      end

      it "should start with every weapon loaded, whatever was shot in the encounter before" do
        state = joined(@first)
        TurnState.write(state, Loading::KEY => [ 'Heavy Crossbow' ])

        expect(Loading.held(joined(second(:from => @first)))).to eq []
      end

      it "should start fresh where the encounter carries on from nothing" do
        Pf2eHP.modify_damage(joined(@first), 7)

        expect(joined(second).damage).to eq 0
      end

      it "should start as they left the encounter this one carries on from, effects and all" do
        state = joined(@first)
        Pf2eHP.modify_damage(state, 7)
        ActiveEffects.apply(state, 'Effect: Adamantine Body', :encounter => @first)

        carried = joined(second(:from => @first))

        expect(carried.damage).to eq 7
        expect(ActiveEffects.on(carried).map(&:name)).to eq [ 'Effect: Adamantine Body' ]
        expect(ActiveEffects.on(Pf2eCombatantState[state.id]).size).to eq 1
      end

      it "should start fresh when they were not in the encounter carried on from" do
        expect(joined(second(:from => @first)).damage).to eq 0
      end

      it "should find nobody to change where no encounter is running" do
        client = double('client', :emit_failure => nil, :emit_ooc => nil)
        allow(Combatants).to receive(:encounter_here).and_return(nil)

        expect(ActiveEffects.targets(client, hero, [ @hero.name ])).to eq []
        expect(client).to have_received(:emit_failure).with(t('pf2e.no_encounter_here'))
      end

      it "should end a condition timed to a turn on the character as they stand in the encounter" do
        state = joined(@first)
        state.update(:pf2_conditions => { 'Off-Guard' => { 'expires' => Turns.expiry('turn-end', @hero.name, 1) } })

        ended = Turns.conditions_ended(PF2Encounter[@first.id], 'turn-end', @hero.name, 1)

        expect(ended.map { |one| one['args']['condition'] }).to eq [ 'Off-Guard' ]
        expect(Pf2eCombatantState[state.id].pf2_conditions).to eq({})
      end

      describe "when a character is deleted" do
        before(:each) do
          joined(@first)
          @second = Character.create(:name => "Second#{rand(1000000)}", :pf2_level => 3)
          @second.update(:hp => Pf2eHP.create(:character => @second, :ancestry_hp => 8, :charclass_hp => 10))
          Combatants.join(@first, @second.name, 5, :holder => Character[@second.id])
          @first.update(:round => 1)
          History.recording(PF2Encounter[@first.id], 'GM: damage') do
            Pf2eHP.modify_damage(CombatantStates.of(PF2Encounter[@first.id], Character[@second.id]), 1)
          end
          @state = CombatantStates.of(PF2Encounter[@first.id], Character[@second.id])
        end

        it "should take them out of every encounter they are in" do
          Character[@second.id].delete

          expect(Combatants.all(PF2Encounter[@first.id]).map(&:label)).to eq [ @hero.name ]
          expect(Pf2eCombatantState[@state.id]).to be_nil
        end

        it "should leave the encounter working without them" do
          Character[@second.id].delete

          expect(Difficulty.shown(PF2Encounter[@first.id])).to start_with('Trivial')
          expect { Turns.turn_started(PF2Encounter[@first.id], @hero.name, 1) }.not_to raise_error
        end

        it "should not bring them back when a change from before is taken back" do
          Character[@second.id].delete

          expect(History.undo(PF2Encounter[@first.id]).ok?).to be true
          expect(Combatants.all(PF2Encounter[@first.id]).map(&:label)).to eq [ @hero.name ]
          expect(PF2Encounter[@first.id].states.to_a.map(&:character_id)).to eq [ @hero.id ]
        end
      end

      it "should keep their state when they join the same encounter again" do
        state = joined(@first)

        expect(joined(@first).id).to eq state.id
      end

      it "should move what a character carries into a running encounter, and leave every sheet neutral" do
        @hp.update(:damage => 5)
        hero.update(:pf2_conditions => { 'Frightened' => { 'value' => 1 } })
        @first.update(:is_active => true, :participants => [ [ 10.0, @hero.name ] ])

        refused = CombatantStates.neutralize_all!(:characters => [ hero ], :encounters => [ PF2Encounter[@first.id] ])

        expect(refused).to eq({})

        state = CombatantStates.of(@first, hero)

        expect(state.damage).to eq 5
        expect(state.pf2_conditions).to have_key('Frightened')
        expect(Pf2eHP[@hp.id].damage).to eq 0
        expect(hero.pf2_conditions).to eq({})
      end
    end
  end
end
