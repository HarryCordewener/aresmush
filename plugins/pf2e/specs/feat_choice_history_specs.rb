require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # What a character chose for a feat or a class - Assurance's skill, a cleric's domain - outlasts the
    # draft it was chosen in: approval and a level-up record it in the ledger with everything else the
    # draft held, and a rollback takes a level's choices back with that level.
    describe "the choices a character made", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Chooser#{rand(1000000)}")
        @builder = AutoBuilder.new(@char)
      end

      after(:each) do
        Character[@char.id]&.delete
      end

      def char
        Character[@char.id]
      end

      def scholar_cleric
        @builder.build_level_one('Cleric', ancestry: 'Human', heritage: 'Versatile', background: 'Scholar')
      end

      it "should keep a background feat's choice once the character is approved" do
        scholar_cleric
        chosen = Pf2e.choice_for(char, 'Assurance')

        @builder.advance_to(1)

        expect(chosen).to_not be_nil
        expect(Pf2e.choice_for(char, 'Assurance')).to eq chosen
      end

      it "should keep a class feat's choice once the character is approved" do
        scholar_cleric
        chosen = Pf2e.choice_for(char, 'Domain Initiate')

        @builder.advance_to(1)

        expect(chosen).to_not be_nil
        expect(Pf2e.choice_for(char, 'Domain Initiate')).to eq chosen
      end

      it "should keep them through a level-up that makes none" do
        scholar_cleric
        chosen = Pf2e.choice_for(char, 'Domain Initiate')

        @builder.advance_to(3)

        expect(char.pf2_level).to eq 3
        expect(Pf2e.choice_for(char, 'Domain Initiate')).to eq chosen
      end

      it "should be what a rule that names the choice reads" do
        scholar_cleric
        @builder.advance_to(1)

        assurance = Effects.with_selections(char, { 'name' => 'Assurance',
                                                    'rules' => Global.read_config('pf2e_feats', 'Assurance')['rules'] })

        expect(assurance['item']['flags']['system']['rulesSelections']['assurance']).to_not be_nil
      end

      describe "made during a level-up" do
        before(:each) do
          scholar_cleric
          @builder.advance_to(3)
          @builder.clear
          @builder.run 'advance'
          @builder.run 'advance/feat skill=Assurance'
          @builder.run "advance/option Assurance=#{other_skill}"
          6.times { break if @builder.resolve_outstanding(:advance).zero? }
          @builder.run 'advance/done'
        end

        def other_skill
          @other ||= (char.skills.to_a.reject { |one| one.prof_level == 'untrained' }.map(&:name) -
                      [ Pf2e.choice_for(char, 'Assurance') ]).reject { |name| name.include?('Lore') }.first
        end

        it "should be recorded at that level" do
          expect(@builder.failures).to eq []
          expect(char.pf2_level).to eq 4
          expect(Pf2e.choice_labels_for(char, 'Assurance')).to include other_skill
          expect(Pf2e::Ledger.explain_for(char, :kind => 'make_choice', :key => 'Assurance')
                   .map { |row| row['effective_level'] }).to include 4
        end

        it "should go back with the level when it is rolled back" do
          expect(Pf2e.rollback_to_level(char, 3, char)).to be_nil

          expect(Pf2e.choice_labels_for(char, 'Assurance')).to_not include other_skill
          expect(Pf2e.choice_labels_for(char, 'Assurance').size).to eq 1
        end
      end
    end
  end
end
