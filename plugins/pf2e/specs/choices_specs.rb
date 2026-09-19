require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a `ChoiceSet` offers. Ninety-odd of the rules on what we stock ask a question, and the rules
    # beside them read the answer, so a set that offers nothing is an item or a feat that does nothing.
    describe Choices do

      def set(fields)
        { 'source' => 'Something' }.merge(fields)
      end

      def listed(*values)
        set('choices' => values.map { |one| { 'value' => one } })
      end

      describe "a set that lists its answers" do
        it "should offer every one it lists" do
          expect(Choices.offer(listed('acid', 'cold', 'fire'), nil)).to eq %w{acid cold fire}
        end

        # Terrain Stalker asks again each time it is taken, and will not offer a terrain already chosen.
        def terrains
          set('choices' => [ { 'value' => 'rubble', 'when' => [ { 'not' => 'terrain-stalker:rubble' } ] },
                             { 'value' => 'snow' } ])
        end

        it "should offer a terrain the character has not taken" do
          expect(Choices.offer(terrains, nil)).to eq %w{rubble snow}
        end

        it "should leave out an answer whose own circumstances are unmet" do
          char = double
          allow(Effects).to receive(:facts).with(char).and_return([ 'terrain-stalker:rubble' ])

          expect(Choices.offer(terrains, char)).to eq [ 'snow' ]
        end

        it "should allow an answer it lists and refuse one it does not" do
          expect(Choices.allows?(listed('acid', 'fire'), nil, 'Fire')).to be true
          expect(Choices.allows?(listed('acid', 'fire'), nil, 'sonic')).to be false
        end
      end

      describe "a set that names a vocabulary" do
        before(:each) do
          allow(Global).to receive(:read_config).with('pf2e_skills')
            .and_return('Athletics' => { 'key_abil' => 'Strength' },
                        'Dragon Lore' => { 'key_abil' => 'Intelligence' })
        end

        it "should offer the whole vocabulary, slugged" do
          expect(Choices.offer(set('vocabulary' => 'saves'), nil)).to eq %w{fortitude reflex will}
        end

        it "should offer a vocabulary read off the catalogue rather than a list here" do
          expect(Choices.offer(set('vocabulary' => 'skills'), nil)).to eq [ 'athletics' ]
        end

        # A lore's name is the player's invention, so it is not a skill anyone can be offered.
        it "should keep lores out of the skills" do
          expect(Choices.offer(set('vocabulary' => 'skills'), nil)).to_not include 'dragon-lore'
        end

        it "should offer nothing for a vocabulary it does not have" do
          expect(Choices.offer(set('vocabulary' => 'planarRealms'), nil)).to eq []
        end

        it "should offer every kind of damage PF2e has" do
          expect(Choices.offer(set('vocabulary' => 'damageTypes'), nil)).to include 'fire', 'void', 'spirit'
        end
      end

      # The shape that makes this worth having: a set may *describe* its answers - "any skill feat of
      # 4th level or lower" - and a description of that sort is a predicate, which we already read.
      describe "a set that describes its answers" do
        before(:each) do
          allow(Global).to receive(:read_config).with('pf2e_feats')
            .and_return('Assurance' => { 'level' => 1, 'type' => [ 'skill' ] },
                         'Battle Medicine' => { 'level' => 1, 'type' => [ 'skill' ] },
                         'Toughness' => { 'level' => 1, 'type' => [ 'general' ] },
                         'Canny Acumen' => { 'level' => 7, 'type' => [ 'general' ] })
        end

        def describing(filter)
          set('filter' => filter, 'item_type' => 'feat')
        end

        it "should offer the entries the description reaches" do
          expect(Choices.offer(describing([ 'item:feat-type:skill' ]), nil))
            .to eq %w{assurance battle-medicine}
        end

        it "should read a comparison in the description" do
          expect(Choices.offer(describing([ 'item:feat-type:general', { 'lte' => [ 'item:level', 1 ] } ]), nil))
            .to eq [ 'toughness' ]
        end

        it "should offer nothing when it names a catalogue we do not have" do
          expect(Choices.offer(set('filter' => [ 'item:level:1' ], 'item_type' => 'deity'), nil)).to eq []
        end

        it "should allow an answer the description reaches" do
          expect(Choices.allows?(describing([ 'item:feat-type:skill' ]), nil, 'Assurance')).to be true
          expect(Choices.allows?(describing([ 'item:feat-type:skill' ]), nil, 'Toughness')).to be false
        end
      end

      describe "the facts a description may ask about" do
        it "should carry what kind of thing it is, and what it is called" do
          facts = Choices.facts_of('Battle Medicine', { 'level' => 1 }, 'feat')

          expect(facts).to include 'item:type:feat', 'item:slug:battle-medicine', 'item:level:1'
        end

        it "should carry a weapon's group and category" do
          facts = Choices.facts_of('Longsword', { 'group' => 'sword', 'category' => 'martial' }, 'weapon')

          expect(facts).to include 'item:group:sword', 'item:category:martial'
        end

        it "should carry every trait" do
          facts = Choices.facts_of('Longsword', { 'traits' => [ 'versatile P' ] }, 'weapon')

          expect(facts).to include 'item:trait:versatile-p'
        end

        # Level 1 when nothing says otherwise, so a comparison against level always has a number.
        it "should call a levelless thing first level" do
          expect(Choices.facts_of('Something', nil, 'feat')).to include 'item:level:1'
        end
      end

      describe "the answer a listed set records" do
        def aid
          set('choices' => [ -1, 1, 2, 3, 4 ].map { |one| { 'label' => format('%+d', one), 'value' => one } })
        end

        it "should read a negative number as itself" do
          expect(Choices.listed_answer(aid, '-1')).to eq '-1'
          expect(Choices.listed_answer(aid, '+1')).to eq '1'
        end

        it "should read a word by its slug" do
          expect(Choices.listed_answer(listed('acid', 'cold'), 'Cold')).to eq 'cold'
        end

        it "should read a choice by its label when nothing else matches" do
          bon_mot = set('choices' => [ { 'label' => 'Critical Success', 'value' => -3 },
                                       { 'label' => 'Success', 'value' => -2 } ])

          expect(Choices.listed_answer(bon_mot, 'Critical Success')).to eq '-3'
        end

        it "should read nothing it does not offer" do
          expect(Choices.listed_answer(aid, '+7')).to be_nil
        end
      end
    end
  end
end
