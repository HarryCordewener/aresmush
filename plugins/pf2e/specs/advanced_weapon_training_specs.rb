require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Advanced Weapon Training: "Choose a weapon group. You gain proficiency with all advanced
    # weapons in that group as if they were martial weapons of their weapon group."
    describe "advanced weapons counted as martial" do

      describe "the groups a choice offers" do
        before(:each) do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_weapons').and_return(
            'Sawtooth Saber' => { 'category' => 'advanced', 'group' => 'Sword' },
            'Longsword' => { 'category' => 'martial', 'group' => 'Sword' },
            'Tricky Pick' => { 'category' => 'advanced', 'group' => 'Pick' },
            'Club' => { 'category' => 'simple', 'group' => 'Club' }
          )
        end

        it "should list each group holding a weapon of the category, once" do
          expect(Pf2e.choice_weapon_group_pool(nil, 'category' => 'advanced')).to eq [ 'Pick', 'Sword' ]
        end

        it "should list every group when no category is named" do
          expect(Pf2e.choice_weapon_group_pool(nil, {})).to eq [ 'Club', 'Pick', 'Sword' ]
        end
      end

      describe "a Fighter's proficiency", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Advanced#{rand(1000000)}")
          @char.update(:pf2_base_info => { 'charclass' => 'Fighter' }, :pf2_level => 6)

          @combat = Pf2eCombat.create(:character => @char,
            :weapon_prof => { 'simple' => 'expert', 'martial' => 'expert', 'advanced' => 'trained' })
          @char.update(:combat => @combat)
        end

        after(:each) do
          @combat.delete if @combat
          @char.delete if @char
        end

        def trained_in(group)
          @char.update(:pf2_level_tracker => { '6' => { 'feat_choices' => { 'Advanced Weapon Training' => [ group ] } } })
        end

        def prof(weapon)
          Pf2eCombat.get_weapon_prof(Character[@char.id], weapon)
        end

        it "should give an advanced weapon in the chosen group the martial rank" do
          trained_in('Sword')

          expect(prof('Sawtooth Saber')).to eq 'expert'
        end

        it "should leave an advanced weapon in another group at the advanced rank" do
          trained_in('Sword')

          expect(prof('Tricky Pick')).to eq 'trained'
        end

        it "should leave the advanced rank alone without the choice" do
          expect(prof('Sawtooth Saber')).to eq 'trained'
        end

        # Fighter Weapon Mastery in Sword makes its martial weapons master and its advanced weapons
        # expert. A trained advanced sword is a martial sword, so it is master too.
        it "should follow the group's martial rank" do
          trained_in('Sword')
          @combat.update(:weapon_group_prof => { 'Sword' => { 'martial' => 'master', 'advanced' => 'expert' } })

          expect(prof('Sawtooth Saber')).to eq 'master'
        end
      end
    end
  end
end
