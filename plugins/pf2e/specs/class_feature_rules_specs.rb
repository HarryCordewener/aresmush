require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A class feature's rules apply as a feat's do. The class tables grant a feature as what it amounts to
    # at that level - "Sneak Attack 1d6" - and the catalogue holds Foundry's one item, "Sneak Attack", that
    # works the amount out itself.
    describe "a class feature's rules", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Rogue#{rand(1000000)}", :pf2_level => 1, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                                 :pf2_base_info => { 'charclass' => 'Rogue' },
                                 :pf2_features => { 'charclass_features' => [ 'Sneak Attack 1d6' ] })
        @combat = Pf2eCombat.create(:character => @char,
                                    :weapon_prof => { 'simple' => 'trained', 'martial' => 'trained', 'unarmed' => 'trained' })
        @char.update(:combat => @combat)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 16) }
        Paths.apply_all!(Character[@char.id])
      end

      after(:each) do
        Array(@items).each(&:delete)
        @abilities.each(&:delete)
        @combat.delete
        @char.delete
      end

      def char
        Character[@char.id]
      end

      def attack(name)
        weapon = Pf2egear.create_item(char, 'weapons', name, 1, Global.read_config('pf2e_weapons', name))
        weapon.update(:equipped => true)
        (@items ||= []) << weapon

        Pf2eCombat.attack_descriptor(char, weapon)
      end

      def precision(name, options)
        Damage.of(char, attack(name), options)['instances'].select { |one| one['category'] == 'precision' }
      end

      it "should name a granted feature by the item that works it out" do
        expect(Effects.feature_named('Sneak Attack 1d6')).to eq 'Sneak Attack'
        expect(Effects.feature_named('Precise Strike 3 (3d6)')).to eq 'Precise Strike'
        expect(Effects.feature_named('Incredible Movement (+10 feet)')).to eq 'Incredible Movement'
      end

      it "should add sneak attack's precision dice to a finesse Strike at an off-guard target" do
        found = precision('Rapier', [ 'target:condition:off-guard' ])

        expect(found.map { |one| one['dice'] }).to eq [ [ [ 1, 'd6' ] ] ]
      end

      it "should add none at a target that is not off-guard" do
        expect(precision('Rapier', [])).to eq []
      end

      it "should add none with a weapon that is neither agile nor finesse" do
        expect(precision('Longsword', [ 'target:condition:off-guard' ])).to eq []
      end

      # What a feature works out - sneak attack's dice - is the character's as they stand in a fight from
      # the moment they join it, before anything else has happened to them there.
      it "should add sneak attack to a Strike in an encounter the character has just joined" do
        attack('Rapier')
        encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(encounter, char.name, 10, :holder => char)
        state = CombatantStates.of(encounter, char)
        rapier = Pf2eCombat.attack_descriptor(state, state.weapons.to_a.first)

        found = Damage.of(state, rapier, [ 'target:condition:off-guard' ])['instances'].select { |one| one['category'] == 'precision' }

        expect(found.map { |one| one['dice'] }).to eq [ [ [ 1, 'd6' ] ] ]
        encounter.delete
      end

      it "should add more dice at a higher level, as the feature's own rule says" do
        char.update(:pf2_level => 5)
        Paths.apply_all!(char)

        expect(precision('Rapier', [ 'target:condition:off-guard' ]).map { |one| one['dice'] }).to eq [ [ [ 2, 'd6' ] ] ]
      end
    end
  end
end
