require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The archetype feats whose effect is data alone - a proficiency, a choice, sneak attack dice, a
    # composition cantrip - checked against what each feat's text says it does.
    describe "archetype feat data" do

      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @dedication = YAML.load_file("game/config/pf2e_feat_dedication.yml")['pf2e_feats']
        @specialty = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']
        @archetype_specialty = YAML.load_file("game/config/pf2e_archetype_specialty.yml")['pf2e_archetype_specialty']
        @classes = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']
      end

      def feat(name)
        @feats.fetch(name)
      end

      def options(name)
        feat(name)['feat_choice']['options']
      end

      # `feat` and `orfeat` are feats the character must hold, so anything else there refuses the
      # feat to everyone.
      it "should name only real feats as feat prerequisites" do
        @dedication.each_pair do |name, details|
          prereq = details['prereq'] || {}

          (Array(prereq['feat']) + Array(prereq['orfeat'])).each do |required|
            expect(@feats).to have_key(required), "#{name} requires #{required.inspect}"
          end
        end
      end

      describe "prerequisites" do
        it "should ask for the save each feat raises from expert" do
          expect(feat('Evasiveness (Rogue)')['prereq']['combat_stats']).to eq 'Reflex/expert'
          expect(feat('Evasiveness (Swashbuckler)')['prereq']['combat_stats']).to eq 'Reflex/expert'
          expect(feat("Juggernaut's Fortitude")['prereq']['combat_stats']).to eq 'Fortitude/expert'
        end

        it "should ask for expert in some weapon for Diverse Weapon Expert" do
          expect(feat('Diverse Weapon Expert')['prereq']['combat_stats']).to eq 'Weapon/expert'
        end

        # A class granting no more Hit Points per level than 8 + Constitution, or 10 for Barbarian.
        it "should cap the class Hit Points for each Resiliency" do
          { 'Barbarian' => 10, 'Champion' => 8, 'Fighter' => 8, 'Monk' => 8, 'Ranger' => 8 }.each_pair do |cls, hp|
            expect(feat("#{cls} Resiliency")['prereq']['max_class_hp']).to eq(hp), cls
          end
        end
      end

      describe "proficiencies" do
        def raises(name)
          feat(name)['grants']['combat_stats']
        end

        it "should make Reflex master for Evasiveness" do
          expect(raises('Evasiveness (Rogue)')).to eq({ 'saves' => { 'reflex' => 'master' } })
          expect(raises('Evasiveness (Swashbuckler)')).to eq({ 'saves' => { 'reflex' => 'master' } })
        end

        it "should make Fortitude master for Juggernaut's Fortitude" do
          expect(raises("Juggernaut's Fortitude")).to eq({ 'saves' => { 'fortitude' => 'master' } })
        end

        it "should make Perception master for Master Spotter" do
          expect(raises('Master Spotter (Investigator)')).to eq({ 'perception' => 'master' })
          expect(raises('Master Spotter (Ranger)')).to eq({ 'perception' => 'master' })
        end

        it "should make simple and martial weapons expert and advanced trained" do
          expect(raises('Diverse Weapon Expert')).to eq(
            { 'weapon_prof' => { 'simple' => 'expert', 'martial' => 'expert', 'advanced' => 'trained' } })
        end

        it "should offer each save held at expert for Perfection's Path, raising it to master" do
          expect(options("Perfection's Path").keys).to eq %w(Fortitude Reflex Will)

          options("Perfection's Path").each_pair do |save, option|
            expect(option['prereq']).to eq({ 'combat_stats' => "#{save}/expert" })
            expect(option['grants']).to eq({ 'combat_stats' => { 'saves' => { save.downcase => 'master' } } })
          end
        end
      end

      # Expert to master, then trained to expert, then a skill feat for either skill.
      it "should give both Skill Mastery feats the same three steps" do
        first = feat('Skill Mastery (Rogue)')['feat_choice']
        second = first['then_choose']

        expect(feat('Skill Mastery (Investigator)')['feat_choice']).to eq first
        expect(first['from_skills']).to eq({ 'min_prof' => 'expert', 'max_prof' => 'expert' })
        expect(second['from_skills']).to eq({ 'min_prof' => 'trained', 'max_prof' => 'trained' })
        expect([ first['grants'], second['grants'] ]).to all(eq({ 'raise_skill' => [ 'chosen' ] }))
        expect(second['then_choose']['from_feats']).to eq({ 'feat_type' => 'Skill', 'assoc_skill' => 'from_prior_steps' })
      end

      it "should give 1d4 sneak attack, and 1d6 from 6th level" do
        expect(feat('Sneak Attacker')['grants']).to eq({ 'combat_stats' => { 'sneak_attack' => '1d4' } })
        expect(feat('Sneak Attacker')['at_level']).to eq({ 6 => { 'combat_stats' => { 'sneak_attack' => '1d6' } } })
      end

      it "should grant courageous anthem as a composition cantrip" do
        expect(feat('Anthemic Performance')['magic_stats']).to eq(
          { 'focus_cantrip' => { 'composition' => [ 'Courageous Anthem' ] } })
      end

      it "should offer the blessings the champion class offers" do
        blessing = @classes['Champion']['advance'].values
          .map { |entry| (entry || {})['charclass_choice'] }
          .find { |choice| choice && choice['choice_name'] == 'Blessing of the Devoted' }

        expect(options('Devout Blessing').keys.sort).to eq blessing['options'].keys.sort
      end

      # One option per cause the Champion Archetype offers, each the reaction that cause gives a
      # champion, and each open only to a character following that cause.
      it "should offer the reaction of the character's cause" do
        causes = @archetype_specialty['Champion Archetype'].keys

        expect(options("Champion's Reaction").keys.sort).to eq(
          causes.map { |cause| Array(@specialty['Champion'][cause]['chargen']['reaction']).first }.sort)

        causes.each do |cause|
          reaction = Array(@specialty['Champion'][cause]['chargen']['reaction']).first

          expect(options("Champion's Reaction")[reaction]).to eq({ 'prereq' => { 'specialize' => [ cause ] } })
        end
      end
    end

    describe "archetype feats taken during a level-up", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "ArchFeat#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Oracle', 'ancestry' => 'Human' })
        @combat = Pf2eCombat.create(:character => @char,
          :saves => { 'fortitude' => 'expert', 'reflex' => 'trained', 'will' => 'expert' })
        @char.update(:combat => @combat)
      end

      after(:each) do
        @combat.delete if @combat
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def take(feat_name, level)
        @char.update(:pf2_level => level - 1, :advancing => true)

        found = Pf2e.get_feat_details(feat_name)
        to_assign = {}
        advancement = {}

        Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'charclass', :to_assign => to_assign, :advancement => advancement)

        advancement
      end

      # What advance/done does with the level's grants.
      def finish(advancement)
        Advancement::Apply.all(@char, { 'grants' => advancement['grants'] }, :charclass => 'Oracle', :client => nil)

        Pf2eCombat[@combat.id]
      end

      it "should make Reflex master once the level is done" do
        @combat.update(:saves => @combat.saves.merge('reflex' => 'expert'))

        combat = finish(take('Evasiveness (Rogue)', 12))

        expect(combat.saves['reflex']).to eq 'master'
      end

      it "should end a sneak attacker who joined at 6th on 1d6" do
        combat = finish(take('Sneak Attacker', 6))

        expect(combat.sneak_attack).to eq '1d6'
      end

      it "should start one who joined at 4th on 1d4" do
        combat = finish(take('Sneak Attacker', 4))

        expect(combat.sneak_attack).to eq '1d4'
      end

      it "should offer Perfection's Path only for the saves held at expert" do
        @char.update(:pf2_level => 11, :advancing => true)
        block = Pf2e.feat_choice_def(Pf2e.get_feat_details("Perfection's Path")[1])

        expect(Pf2e.choice_options(@char, "Perfection's Path", block)).to eq %w(Fortitude Will)
      end

      it "should offer Champion's Reaction only for the character's cause" do
        @char.update(:pf2_level => 5, :advancing => true,
                     :pf2_archetypeinfo => { 'archetype1' => 'Champion Archetype', 'archetype_specialty1' => 'Redeemer' })
        block = Pf2e.feat_choice_def(Pf2e.get_feat_details("Champion's Reaction")[1])

        expect(Pf2e.choice_options(@char, "Champion's Reaction", block)).to eq [ 'Glimpse of Redemption' ]
      end
    end
  end
end
