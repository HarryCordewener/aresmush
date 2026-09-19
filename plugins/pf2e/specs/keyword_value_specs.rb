require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Resolving a word in a roll string to a number.
    #
    # `roll` takes arbitrary words - a save, a skill, an ability, a shorthand - and every one of
    # them has to come back as something that can be added up.
    describe :get_keyword_value do

      def char
        strength = double(:shortname => 'STR', :name => 'Strength', :name_upcase => 'STRENGTH')

        double(:abilities => [ strength ], :pf2_level => 5, :is_admin? => false, :name => 'Someone')
      end

      # `char.abilities.select { }` returns an array, so a lookup needs `.first` - an array is
      # truthy, so a `return 0 if !obj` guard does not catch the miss and `obj.name` raises.
      it "should resolve an abbreviated ability" do
        allow(Pf2eAbilities).to receive(:get_score).with(anything, 'Strength').and_return(18)
        allow(Pf2eAbilities).to receive(:abilmod).with(18).and_return(4)

        expect(Pf2e.get_keyword_value(char, 'str')).to eq 4
      end

      it "should resolve an abbreviated ability whatever case it was typed in" do
        allow(Pf2eAbilities).to receive(:get_score).with(anything, 'Strength').and_return(18)
        allow(Pf2eAbilities).to receive(:abilmod).with(18).and_return(4)

        expect(Pf2e.get_keyword_value(char, 'STR')).to eq 4
      end

      it "should give nothing for an ability the character has no score for" do
        expect(Pf2e.get_keyword_value(char, 'dex')).to eq 0
      end

      it "should resolve a full ability name" do
        allow(Pf2eAbilities).to receive(:get_score).and_return(14)
        allow(Pf2eAbilities).to receive(:abilmod).with(14).and_return(2)

        expect(Pf2e.get_keyword_value(char, 'strength')).to eq 2
      end

      def a_check(total, adjustments = [])
        instance_double(Pf2e::Check, :total => total, :adjustments => adjustments)
      end

      # A save, a skill and Perception are checks rather than figures: a roll of one carries what kind
      # of check it is, which is what a rule about a kind of check is predicated on.
      it "should resolve a save through a check" do
        expect(Pf2e::Check).to receive(:of).with(anything, 'save', 'will', anything)
                                           .and_return(a_check(11))

        expect(Pf2e.get_keyword_value(char, 'Will')).to eq 11
      end

      # A term saying what the roller is doing reaches the check, so a bonus that applies only then can
      # be counted.
      it "should hand the circumstances to the check it makes" do
        expect(Pf2e::Check).to receive(:of).with(anything, 'save', 'will', [ 'action:brace' ])
                                           .and_return(a_check(11))

        expect(Pf2e.get_keyword_value(char, 'Will', [ 'action:brace' ])).to eq 11
      end

      it "should resolve perception through a check" do
        expect(Pf2e::Check).to receive(:of).with(anything, 'perception', nil, anything)
                                           .and_return(a_check(9))

        expect(Pf2e.get_keyword_value(char, 'perception')).to eq 9
      end

      # The check itself comes back with the number, so the roll can ask it what the outcome should be
      # once the die is known: a keen weapon turns a natural 19 into a critical hit, and nothing before
      # the roll can say whether that happened.
      it "should collect the check the word resolved to" do
        held = a_check(9, [ { 'all' => 'one-degree-better' } ])
        allow(Pf2e::Check).to receive(:of).and_return(held)
        collected = []

        Pf2e.get_keyword_value(char, 'perception', [], collected)

        expect(collected).to eq [ held ]
      end

      it "should give nothing for an attack keyword, which only picks the linked ability" do
        expect(Pf2e.get_keyword_value(char, 'melee')).to eq 0
      end

      it "should give nothing for a word it does not know" do
        allow(Global).to receive(:read_config).with('pf2e_skills').and_return({})

        expect(Pf2e.get_keyword_value(char, 'banana')).to eq 0
      end
    end
  end
end
