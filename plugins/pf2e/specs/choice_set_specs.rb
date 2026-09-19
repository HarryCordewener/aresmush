require "plugin_test_loader"

module AresMUSH

  # A feat that asks the player something, and the rules beside it that read the answer.
  #
  # Ninety-two of the rules we stock are questions of this sort - a resistance to the kind of damage you
  # chose, a bonus to the performance you named - and a rule reading an answer nobody supplied is worth
  # nothing. Foundry writes the answer as `{item|flags.system.rulesSelections.<flag>}`, and the answer
  # it reads is the choice already recorded with the feat.
  describe "choice sets", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Choice#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_level_tracker => {}, :pf2_derived => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
      }
      @skills = %w{Acrobatics Performance}.map { |name| Pf2eSkills.create_skill_for_char(name, @char) }
    end

    after(:each) do
      @skills.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    # The feat, and the choice recorded with it - which is what `advance/feat` writes.
    def take(feat, bucket, *chosen)
      tracker = { '5' => { 'feat_choices' => { feat => chosen } } }

      @char.update(:pf2_feats => { bucket => [ feat ] },
                   :pf2_level_tracker => chosen.any? ? tracker : {})
    end

    describe "a bonus that applies to the answer" do
      it "should apply when the player is doing the thing they chose" do
        take('Virtuosic Performer', 'skill', 'singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to be > plain
      end

      it "should not apply to a performance they did not choose" do
        take('Virtuosic Performer', 'skill', 'singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:dance' ]))
          .to eq plain
      end

      # Nothing is chosen until the player chooses, and a rule naming an answer nobody gave is ignored
      # rather than applied to everything.
      it "should apply to nothing while no answer is recorded" do
        take('Virtuosic Performer', 'skill')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to eq plain
      end

      it "should count an answer recorded in the player's own spelling" do
        take('Virtuosic Performer', 'skill', 'Singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to be > plain
      end
    end

    describe "a resistance to the kind of damage chosen" do
      it "should resist the kind the player chose" do
        take('Nephilim Resistance', 'ancestry', 'fire')

        expect(Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }).to include 'fire'
      end

      it "should resist nothing else" do
        take('Nephilim Resistance', 'ancestry', 'fire')

        expect(Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }).to_not include 'cold'
      end

      it "should resist nothing while no answer is recorded" do
        take('Nephilim Resistance', 'ancestry')

        expect(Pf2e::IWR.of(reread)['resistance']).to eq []
      end

      # An answer the set never offered is not an answer to it: this one is a skill, not a kind of damage.
      it "should ignore an answer the set could not have offered" do
        take('Nephilim Resistance', 'ancestry', 'acrobatics')

        expect(Pf2e::IWR.of(reread)['resistance']).to eq []
      end
    end

    # The other half: an answer that says where a value is written rather than what it is worth.
    describe "a rank written to the skill chosen" do
      it "should train the skill the player named" do
        take('Skill Training', 'general', 'Acrobatics')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2eSkills.get_skill_prof(reread, 'Acrobatics')).to eq 'trained'
      end

      it "should train nothing while no answer is recorded" do
        take('Skill Training', 'general')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2eSkills.get_skill_prof(reread, 'Acrobatics')).to eq 'untrained'
      end
    end
  end
end
