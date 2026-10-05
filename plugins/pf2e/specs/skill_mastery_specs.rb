require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Skill Mastery, the Investigator and Rogue archetypes' feat: one skill from expert to master,
    # another from trained to expert, and a skill feat for either of them whose prerequisites the
    # character meets. Three steps of one choice, each resolved the way advance/option resolves it.
    describe "Skill Mastery", :dbtest => true do

      def feat
        'Skill Mastery (Rogue)'
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Mastery#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' },
                     :pf2_archetypeinfo => { 'archetype1' => 'Rogue Archetype' },
                     :pf2_feats => { 'charclass' => [ 'Rogue Dedication' ] },
                     :pf2_level => 7, :advancing => true)

        { 'Athletics' => 'expert', 'Crafting' => 'expert', 'Stealth' => 'trained', 'Society' => 'trained' }
          .each_pair do |skill, prof|
            Pf2eSkills.create_skill_for_char(skill, @char)
            Pf2eSkills.update_skill_for_char(skill, @char, prof)
          end
      end

      after(:each) do
        @char.skills.each(&:delete) if @char
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def char
        Character[@char.id]
      end

      # Takes the feat during the level-up to 8th, as advance/feat would.
      def take
        found = Pf2e.get_feat_details(feat)
        to_assign = {}
        advancement = {}

        gained = Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)

        @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)
        gained[:after_save].each(&:call)
      end

      def options
        _key, block = Pf2e.validate_feat_choice(char, feat)

        Pf2e.choice_options(char, feat, block)
      end

      def pick(value)
        key, block = Pf2e.validate_feat_choice(char, feat)

        Pf2e.stage_feat_choice(char, key, block, value, nil)
      end

      it "should first offer the skills held at expert" do
        take

        expect(options).to eq %w(Athletics Crafting)
      end

      it "should then offer the skills held at trained" do
        take
        pick('Athletics')

        expect(options).to eq %w(Society Stealth)
      end

      it "should count the first raise before the level is done" do
        take
        pick('Athletics')

        expect(DraftSheet.of(char).skill_prof('Athletics')).to eq 'master'
      end

      # Quick Climb asks for master in Athletics, which only the first step made it.
      it "should last offer skill feats for either skill that the character now qualifies for" do
        take
        pick('Athletics')
        pick('Stealth')

        offered = options

        expect(offered).to include('Quick Climb', 'Shadow Mark')

        # Some feats hang off two skills - Slippery Prey is Acrobatics or Athletics - and count for
        # either of theirs.
        offered.each do |name|
          skills = Array(Pf2e.get_feat_details(name)[1]['assoc_skill'])

          expect(skills & %w(Athletics Stealth)).to_not be_empty, name
        end
      end

      it "should raise both skills once the level is done" do
        take
        pick('Athletics')
        pick('Stealth')
        pick('Quick Climb')

        Advancement::Apply.all(char, { 'grants' => char.pf2_advancement['grants'] }, :charclass => 'Fighter', :client => nil)

        expect(Pf2eSkills.get_skill_prof(char, 'Athletics')).to eq 'master'
        expect(Pf2eSkills.get_skill_prof(char, 'Stealth')).to eq 'expert'
        expect(char.pf2_advancement['feats']['skill']).to eq [ 'Quick Climb' ]
      end

      # Each taking picks again, so a skill picked before is still on offer if its rank fits.
      it "should offer a skill an earlier taking already raised" do
        @char.update(:pf2_to_assign => { 'feat_choices' => { feat => [ 'Crafting', 'Society' ] } })
        to_assign = char.pf2_to_assign

        found = Pf2e.get_feat_details(feat)
        advancement = {}
        Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)
        @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)

        expect(options).to eq %w(Athletics Crafting)
      end
    end
  end
end
