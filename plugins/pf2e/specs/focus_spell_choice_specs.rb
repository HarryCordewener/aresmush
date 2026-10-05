require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The choices that hand over a focus spell: a subclass's tier spell, a domain's spell, a witch's
    # lesson, and another mystery's revelation.
    describe "focus spell choices" do

      def domains
        {
          'Family' => { 'initial' => 'Soothing Words', 'advanced' => 'Unity' },
          'Healing' => { 'initial' => "Healer's Blessing", 'advanced' => 'Rebuke Death' },
          'Pain' => { 'initial' => 'Savor the Sting', 'advanced' => 'Retributive Pain' },
          'Cold' => { 'initial' => 'Winter Bolt', 'advanced' => 'Diamond Dust' }
        }
      end

      def lessons
        {
          'basic' => {
            'Lesson of Dreams' => { 'hex' => 'Veil of Dreams', 'spell' => 'Sleep' },
            'Lesson of the Elements' => { 'hex' => 'Elemental Betrayal', 'spell' => [ 'Air Bubble', 'Breathe Fire' ] }
          },
          'greater' => { 'Lesson of Snow' => { 'hex' => 'Personal Blizzard', 'spell' => 'Wall of Wind' } },
          'major' => { 'Lesson of Death' => { 'hex' => 'Curse of Death', 'spell' => 'Raise Dead' } }
        }
      end

      def spells
        {
          'Sleep' => { 'base_level' => 1, 'traits' => [ 'mental' ] },
          'Air Bubble' => { 'base_level' => 1, 'traits' => [ 'air' ] },
          'Wall of Wind' => { 'base_level' => 3, 'traits' => [ 'air' ] },
          'Raise Dead' => { 'base_level' => 6, 'traits' => [ 'healing' ] },
          'Ancestral Touch' => { 'base_level' => 1, 'traits' => [ 'focus', 'oracle' ], 'mystery' => [ 'ancestors' ] },
          'Ancestral Form' => { 'base_level' => 6, 'traits' => [ 'focus', 'oracle' ], 'mystery' => [ 'ancestors' ] },
          'Spray of Stars' => { 'base_level' => 1, 'traits' => [ 'focus', 'oracle' ], 'mystery' => [ 'cosmos' ] },
          'Interstellar Void' => { 'base_level' => 3, 'traits' => [ 'focus', 'oracle' ], 'mystery' => [ 'cosmos' ] },
          'Glimpse Weakness' => { 'base_level' => 1, 'traits' => [ 'focus', 'oracle' ] }
        }
      end

      def specialty
        {
          'Aberrant' => {
            'chargen' => { 'magic_stats' => { 'focus_spell' => { 'bloodline' => [ 'Tentacular Limbs' ] } } },
            'advanced_focus_spell' => { 'bloodline' => [ 'Aberrant Whispers' ] },
            'greater_focus_spell' => { 'bloodline' => [ 'Unusual Anatomy' ] }
          }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_magic', 'domains').and_return(domains)
        allow(Global).to receive(:read_config).with('pf2e_magic', 'lessons').and_return(lessons)
        allow(Global).to receive(:read_config).with('pf2e_spells').and_return(spells)
        allow(Global).to receive(:read_config).with('pf2e_magic', 'focus_type_by_source')
          .and_return('Cleric' => 'domain', 'Champion' => 'devotion', 'Oracle' => 'revelation', 'Witch' => 'hex')
        allow(Global).to receive(:read_config).with('pf2e_specialty', 'Sorcerer', 'Aberrant').and_return(specialty['Aberrant'])
        allow(Global).to receive(:read_config).with('pf2e_specialty', 'Oracle', 'Cosmos')
          .and_return('domains' => [ 'Darkness', 'Cold', 'Pain' ])
      end

      # instance_double raises if PF2Magic has no such method, so a reader that has drifted from
      # the model fails here rather than in front of a player.
      def someone(charclass, specialize: nil, holding: [])
        magic = instance_double(AresMUSH::PF2Magic)
        allow(Pf2emagic::Entries).to receive(:all_focus).with(magic).and_return(holding)
        allow(Pf2emagic::Entries).to receive(:focus_spells).and_return(holding)

        double(:name => 'Someone', :magic => magic, :advancing => false, :pf2_level => 12,
               :pf2_base_info => { 'charclass' => charclass, 'specialize' => specialize })
      end

      describe "a subclass's tier spell" do
        it "should find the greater spell under greater_focus_spell" do
          char = someone('Sorcerer', :specialize => 'Aberrant')

          expect(Pf2e.archetype_subclass_spell(char, nil, 'greater')).to eq [ 'bloodline', 'Unusual Anatomy' ]
        end

        it "should find the advanced spell under advanced_focus_spell" do
          char = someone('Sorcerer', :specialize => 'Aberrant')

          expect(Pf2e.archetype_subclass_spell(char, nil, 'advanced')).to eq [ 'bloodline', 'Aberrant Whispers' ]
        end

        it "should find the initial spell in the chargen block when no tier is named" do
          char = someone('Sorcerer', :specialize => 'Aberrant')

          expect(Pf2e.archetype_subclass_spell(char, nil, nil)).to eq [ 'bloodline', 'Tentacular Limbs' ]
        end
      end

      describe "held_domains" do
        it "should offer the domains whose initial spell is held and whose advanced spell is not" do
          char = someone('Cleric', :holding => [ 'Soothing Words', "Healer's Blessing", 'Rebuke Death' ])

          expect(Pf2e.choice_dynamic_options(char, 'held_domains')).to eq [ 'Family' ]
        end

        it "should grant the advanced spell as the class's focus type, naming the domain" do
          char = someone('Champion', :holding => [ 'Soothing Words' ])

          expect(Pf2e.choice_dynamic_grants(char, 'held_domains', 'Family')).to eq(
            'magic_stats' => { 'focus_spell' => { 'devotion' => [ 'Unity' ] }, 'focus_source' => 'Domain Family' })
        end
      end

      describe "mystery_domains" do
        it "should offer the mystery's domains the game has, less those whose initial spell is held" do
          char = someone('Oracle', :specialize => 'Cosmos', :holding => [ 'Savor the Sting' ])

          expect(Pf2e.choice_dynamic_options(char, 'mystery_domains')).to eq [ 'Cold' ]
        end

        it "should grant the initial spell as a revelation spell" do
          char = someone('Oracle', :specialize => 'Cosmos')

          expect(Pf2e.choice_dynamic_grants(char, 'mystery_domains', 'Cold')).to eq(
            'magic_stats' => { 'focus_spell' => { 'revelation' => [ 'Winter Bolt' ] }, 'focus_source' => 'Domain Cold' })
        end
      end

      describe "lessons" do
        def options(char, tiers)
          Pf2e.choice_dynamic_options(char, 'lessons', 'from' => 'lessons', 'tiers' => tiers)
        end

        it "should offer only the tiers the feat names" do
          expect(options(someone('Witch'), [ 'basic', 'greater' ])).not_to include('Lesson of Death')
          expect(options(someone('Witch'), [ 'basic', 'greater' ])).to include('Lesson of Snow')
        end

        it "should list a lesson once per familiar spell it lets you choose" do
          expect(options(someone('Witch'), [ 'basic' ])).to eq [
            'Lesson of Dreams', 'Lesson of the Elements (Air Bubble)', 'Lesson of the Elements (Breathe Fire)'
          ]
        end

        it "should leave out a lesson whose hex is held" do
          expect(options(someone('Witch', :holding => [ 'Veil of Dreams' ]), [ 'basic' ])).not_to include('Lesson of Dreams')
        end

        it "should grant the hex and put the familiar's spell in the spellbook at its rank" do
          grants = Pf2e.choice_dynamic_grants(someone('Witch'), 'lessons', 'Lesson of the Elements (Air Bubble)')

          expect(grants).to eq('magic_stats' => {
            'focus_spell' => { 'hex' => [ 'Elemental Betrayal' ] },
            'addspellbook' => { 1 => [ 'Air Bubble' ] },
            'focus_source' => 'Lesson of the Elements'
          })
        end
      end

      describe "another mystery's revelation" do
        it "should offer only revelations tagged for a mystery other than the oracle's own" do
          char = someone('Oracle', :specialize => 'Ancestors')
          pool = Pf2e.choice_spell_pool(char, 'traits' => [ 'oracle', 'focus' ], 'base_level' => [ 1, 3 ],
                                              'subclass' => 'other', 'focus_type' => 'revelation')

          expect(pool).to eq [ 'Interstellar Void', 'Spray of Stars' ]
        end
      end
    end
  end
end
