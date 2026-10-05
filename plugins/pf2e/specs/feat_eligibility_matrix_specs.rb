require "plugin_test_loader"
require_relative "support/feat_matrix"

module AresMUSH
  module Pf2e

    # Whether a character may take a feat, across every kind of prerequisite the feat data uses.
    #
    # Each row of PREREQS names a prerequisite, a feat carrying it, a character who fails that
    # prerequisite and the single change that should satisfy it. The matrix then asserts three
    # things per row: the failing character is refused, the satisfied character is allowed, and no
    # other row's mutation lets the failing character through.
    #
    # That last assertion is what makes this a matrix. A gate can be wrong in two directions, and
    # refusing correctly is only half of it: a gate that accepts when an unrelated axis moves is a
    # gate that is reading the wrong thing. Checking every mutation against every prerequisite
    # catches a check that passes for the wrong reason.
    describe "feat eligibility" do
      include FeatMatrix

      # Synthetic feats, one per prerequisite kind, so a row tests the checker and not the shipped
      # data's choice of example. The shipped data is walked separately in
      # feat_data_integrity_specs.rb.
      def feat_config
        {
          'Levelled' => { 'feat_type' => [ 'General' ], 'prereq' => { 'level' => 5 } },
          'Strong' => { 'feat_type' => [ 'General' ], 'prereq' => { 'ability' => [ 'Strength/16' ] } },
          'Skilled' => { 'feat_type' => [ 'General' ], 'prereq' => { 'skill' => [ 'Athletics/expert' ] } },
          'Chained' => { 'feat_type' => [ 'General' ], 'prereq' => { 'feat' => [ 'Levelled' ] } },
          'EitherFeat' => { 'feat_type' => [ 'General' ], 'prereq' => { 'orfeat' => [ 'Levelled', 'Strong' ] } },
          'EitherSkill' => { 'feat_type' => [ 'General' ], 'prereq' => { 'orskill' => [ 'Athletics/expert', 'Arcana/expert' ] } },
          'Broad' => { 'feat_type' => [ 'General' ], 'prereq' => { 'anyskills' => [ 'expert/2' ] } },
          'Specialised' => { 'feat_type' => [ 'General' ], 'prereq' => { 'specialize' => [ 'Cloistered' ] } },
          'NotSpecialised' => { 'feat_type' => [ 'General' ], 'prereq' => { 'specialize' => [ '!Warpriest' ] } },
          'Heir' => { 'feat_type' => [ 'General' ], 'prereq' => { 'heritage' => 'Skilled Heritage' } },
          'NotHeir' => { 'feat_type' => [ 'General' ], 'prereq' => { 'heritage' => '!Versatile Human' } },
          'Marked' => { 'feat_type' => [ 'General' ], 'prereq' => { 'special' => [ 'Blood Tie' ] } },
          'Faithful' => { 'feat_type' => [ 'General' ], 'prereq' => { 'ordeity' => [ 'Althea' ] } },
          'Aligned' => { 'feat_type' => [ 'General' ], 'prereq' => { 'oralign' => [ 'LG' ] } },
          'Casting' => { 'feat_type' => [ 'General' ], 'prereq' => { 'caster' => 'spells' } },
          'Arcanist' => { 'feat_type' => [ 'General' ], 'prereq' => { 'tradition' => 'Wizard' } },
          'InnatelyPrimal' => { 'feat_type' => [ 'General' ], 'prereq' => { 'innate_tradition' => [ 'primal' ] } },
          'Focused' => { 'feat_type' => [ 'General' ], 'prereq' => { 'has_focus_pool' => true } },
          'Devoted' => { 'feat_type' => [ 'General' ], 'prereq' => { 'focus_spell' => [ 'Lay on Hands' ] } },
          'Healer' => { 'feat_type' => [ 'General' ], 'prereq' => { 'divine_font' => [ 'heal' ] } },
          'Watchful' => { 'feat_type' => [ 'General' ], 'prereq' => { 'combat_stats' => 'Perception/expert' } },
          'Evasive' => { 'feat_type' => [ 'General' ], 'prereq' => { 'combat_stats' => 'Reflex/expert' } },
          'Armed' => { 'feat_type' => [ 'General' ], 'prereq' => { 'combat_stats' => 'Weapon/expert' } },
          'Hardy' => { 'feat_type' => [ 'General' ], 'prereq' => { 'max_class_hp' => 8 } },
          'Unknowable' => { 'feat_type' => [ 'General' ], 'prereq' => { 'combat_stats' => 'Luck/expert' } },
          'TraditionSkilled' => { 'feat_type' => [ 'General' ], 'prereq' => { 'tradition_skill' => [ 'Sorcerer Archetype/master' ] } },
          'Riposting' => { 'feat_type' => [ 'General' ], 'prereq' => { 'feature' => [ 'Opportune Riposte' ] } },
          'Armament' => { 'feat_type' => [ 'General' ], 'prereq' => { 'feature' => [ 'Blessed Armament' ] } },
          'Sanctified' => { 'feat_type' => [ 'General' ], 'prereq' => { 'sanctification' => [ 'holy', 'unholy' ] } },
          'Stanced' => { 'feat_type' => [ 'General' ], 'prereq' => { 'stances' => 2 } },
          'Dispeller' => { 'feat_type' => [ 'General' ], 'prereq' => { 'repertoire_spell' => [ 'Dispel Magic' ] } },
          'Bonded' => { 'feat_type' => [ 'General' ], 'prereq' => { 'familiar' => true } },
          'Leafy' => { 'feat_type' => [ 'General' ], 'prereq' => { 'specialize' => [ 'Leaf' ] } },

          # Order Explorer's shape: a choice of another specialty that makes the character a member.
          'Explorer' => { 'feat_type' => [ 'General' ],
                          'feat_choice' => { 'from' => 'other_specialties', 'joins_specialty' => true } },
          # Crossblooded Evolution's: another specialty, without membership.
          'Crossing' => { 'feat_type' => [ 'General' ], 'feat_choice' => { 'from' => 'other_specialties' } },

          # Held, never taken: a stance to count, and a feat that gives a familiar.
          'Crane Poise' => { 'feat_type' => [ 'General' ], 'traits' => [ 'stance' ] },
          'Tiger Poise' => { 'feat_type' => [ 'General' ], 'traits' => [ 'monk', 'stance' ] },
          'Pact' => { 'feat_type' => [ 'General' ], 'familiar' => true },

          # Gates that are not prereq entries: the feat's own type decides who may take it.
          'FighterOnly' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Fighter' ] },
          'ElfOnly' => { 'feat_type' => [ 'Ancestry' ], 'assoc_ancestry' => [ 'Elf' ] },
          'LineageBound' => { 'feat_type' => [ 'Ancestry', 'Lineage' ], 'assoc_ancestry' => [ 'Human' ],
                              'traits' => [ 'versatile human' ] }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(feat_config)
        allow(Global).to receive(:read_config).with('pf2e', 'prof_progression')
          .and_return(%w(untrained trained expert master legendary))
        matrix_focus([])
        allow(Global).to receive(:read_config).with('pf2e_magic', 'tradition_skills')
          .and_return('arcane' => 'Arcana', 'divine' => 'Religion', 'occult' => 'Occultism', 'primal' => 'Nature')
        allow(Global).to receive(:read_config).with('pf2e_class', 'Fighter', 'HP').and_return(10)
        allow(Global).to receive(:read_config).with('pf2e_class', 'Wizard', 'HP').and_return(6)
      end

      # feat => the mutation that satisfies its prerequisite. Everything else stays at the axis
      # defaults in FeatMatrix::AXES, which is a level 1 Fighter holding nothing.
      PASSES = {
        'Levelled' => { :level => 5 },
        'Strong' => { :abilities => { 'Strength' => 16 } },
        'Skilled' => { :skills => { 'Athletics' => 'expert' } },
        'Chained' => { :feats => { 'charclass' => [ 'Levelled' ] } },
        'EitherFeat' => { :feats => { 'charclass' => [ 'Strong' ] } },
        'EitherSkill' => { :skills => { 'Arcana' => 'expert' } },
        'Broad' => { :skills => { 'Crafting' => 'expert', 'Society' => 'master' } },
        'Specialised' => { :specialize => 'Cloistered' },
        'Heir' => { :heritage => 'Skilled Heritage' },
        'NotHeir' => { :heritage => 'Skilled Heritage' },
        'Marked' => { :specials => [ 'Blood Tie' ] },
        'Faithful' => { :deity => 'Althea' },
        'Aligned' => { :alignment => 'LG' },
        'Casting' => { :traditions => { 'Wizard' => [ 'arcane', 'trained' ] } },
        'Arcanist' => { :traditions => { 'Wizard' => [ 'arcane', 'trained' ] } },
        'InnatelyPrimal' => { :innate => [ { 'name' => 'Tanglefoot', 'level' => 'cantrip', 'tradition' => 'primal' } ] },
        'Focused' => { :focus_pool => 1 },
        'Healer' => { :divine_font => 'heal' },
        'Watchful' => { :perception => 'expert' },
        'Evasive' => { :saves => { 'reflex' => 'expert' } },
        'Armed' => { :weapon_prof => { 'martial' => 'expert' } },
        # The default Fighter gains 10 Hit Points a level; a Wizard gains 6.
        'Hardy' => { :charclass => 'Wizard' },
        # The skill follows the archetype's tradition, so both have to move.
        'TraditionSkilled' => { :traditions => { 'Sorcerer Archetype' => [ 'divine', 'trained' ] },
                                :skills => { 'Religion' => 'master' } },
        'Riposting' => { :features => [ 'Opportune Riposte' ] },
        # A class option is recorded as "Feature (Option)", and the option is what is named.
        'Armament' => { :features => [ 'Blessing of the Devoted (Blessed Armament)' ] },
        'Sanctified' => { :sanctification => 'Unholy' },
        'Stanced' => { :feats => { 'charclass' => [ 'Crane Poise', 'Tiger Poise' ] } },
        'Dispeller' => { :repertoire => { 'Sorcerer' => { '3' => [ 'Dispel Magic' ] } } },
        'Bonded' => { :feats => { 'charclass' => [ 'Pact' ] } },
        # A specialty joined through a choice counts, as the one taken at chargen does.
        'Leafy' => { :choices => { 'Explorer' => [ 'Leaf' ] } },
        'ElfOnly' => { :ancestry => 'Elf' }
      }.freeze

      # Feats the default character already qualifies for, with the mutation that should take the
      # permission away.
      DENIES = {
        'NotSpecialised' => { :specialize => 'Warpriest' },
        'LineageBound' => { :level => 2 },
        'FighterOnly' => { :charclass => 'Wizard' }
      }.freeze

      # Where one row's mutation legitimately satisfies another row's prerequisite. Declared, so
      # the cross product below can treat everything undeclared as a fault.
      #
      # These are the real interactions between the prerequisite kinds, and reading the table is
      # the quickest way to see them:
      #
      #   feat => the other rows whose mutation also satisfies it
      OVERLAPS = {
        # `orfeat` names Levelled and Strong, so either feat satisfies it.
        'EitherFeat' => %w(Chained),
        # `orskill` names Athletics or Arcana at expert.
        'EitherSkill' => %w(Skilled),
        # `caster` asks whether the character casts from a tradition. A class tradition counts and
        # so do innate spells. A focus pool on its own does not, and neither does a divine font.
        'Casting' => %w(Arcanist InnatelyPrimal TraditionSkilled),
        # A tradition is what `tradition` asks for, and Casting's mutation grants one.
        'Arcanist' => %w(Casting),
        # Both heritage rows are satisfied by a heritage that is Skilled and is not Versatile.
        'Heir' => %w(NotHeir),
        'NotHeir' => %w(Heir)
      }.freeze

      describe "a prerequisite that is not met" do
        PASSES.each_key do |feat|
          it "should refuse #{feat}" do
            expect(matrix_allows?(matrix_char, feat)).to be false
          end
        end
      end

      describe "a prerequisite that is met" do
        PASSES.each_pair do |feat, mutation|
          it "should allow #{feat} once #{mutation.keys.first} moves" do
            expect(matrix_allows?(matrix_char(mutation), feat)).to be true
          end
        end
      end

      describe "a feat the default character qualifies for" do
        DENIES.each_key do |feat|
          it "should allow #{feat}" do
            expect(matrix_allows?(matrix_char, feat)).to be true
          end
        end

        DENIES.each_pair do |feat, mutation|
          it "should refuse #{feat} once #{mutation.keys.first} moves" do
            expect(matrix_allows?(matrix_char(mutation), feat)).to be false
          end
        end
      end

      # The cross product. Moving one axis must not open a feat that depends on another, or the
      # check is reading something it has no business reading. Declared overlaps are skipped, and
      # every other pair has to stay refused.
      describe "every mutation against every prerequisite" do
        PASSES.each_key do |feat|
          allowed = Array(OVERLAPS[feat])

          PASSES.each_pair do |other_feat, other_mutation|
            next if feat == other_feat
            next if allowed.include?(other_feat)

            it "should still refuse #{feat} when only #{other_feat}'s #{other_mutation.keys.first} moves" do
              expect(matrix_allows?(matrix_char(other_mutation), feat)).to be false
            end
          end
        end
      end

      # `tradition_skill` reads the skill from the tradition, which the single mutation above cannot
      # show going wrong in either direction.
      describe "a skill that follows an archetype's tradition" do
        def sorcerer(tradition, skill, prof = 'master')
          matrix_char(:traditions => { 'Sorcerer Archetype' => [ tradition, 'trained' ] },
                      :skills => { skill => prof })
        end

        it "should refuse the right rank in another tradition's skill" do
          expect(matrix_allows?(sorcerer('divine', 'Arcana'), 'TraditionSkilled')).to be false
        end

        it "should refuse the tradition's skill below the rank asked for" do
          expect(matrix_allows?(sorcerer('divine', 'Religion', 'expert'), 'TraditionSkilled')).to be false
        end

        it "should allow a higher rank than the one asked for" do
          expect(matrix_allows?(sorcerer('occult', 'Occultism', 'legendary'), 'TraditionSkilled')).to be true
        end

        it "should count a tradition this level is granting" do
          char = matrix_char(:skills => { 'Nature' => 'master' }, :advancing => true)
          allow(char).to receive(:pf2_advancement)
            .and_return('magic_stats' => { 'Sorcerer Archetype' => { 'tradition' => { 'primal' => 'trained' } } })

          expect(matrix_allows?(char, 'TraditionSkilled')).to be true
        end
      end

      describe "a class feature" do
        it "should count a feature the level-up in progress grants" do
          char = matrix_char(:advancing => true)
          allow(char).to receive(:pf2_advancement).and_return('charclass_feature' => [ 'Opportune Riposte' ])

          expect(matrix_allows?(char, 'Riposting')).to be true
        end

        it "should count an option the level-up in progress picks" do
          char = matrix_char(:advancing => true)
          allow(char).to receive(:pf2_advancement)
            .and_return('charclass_feature option' => { 'Blessing of the Devoted' => 'Blessed Armament' })

          expect(matrix_allows?(char, 'Armament')).to be true
        end

        # The Champion archetype's Devout Blessing is a feat choice rather than a class option.
        it "should count a feat choice resolved to it" do
          expect(matrix_allows?(matrix_char(:choices => { 'Devout Blessing' => [ 'Blessed Armament' ] }), 'Armament')).to be true
        end

        it "should not count another option of the same feature" do
          char = matrix_char(:features => [ 'Blessing of the Devoted (Blessed Shield)' ])

          expect(matrix_allows?(char, 'Armament')).to be false
        end
      end

      describe "stances" do
        it "should refuse fewer than asked for" do
          expect(matrix_allows?(matrix_char(:feats => matrix_holding('Crane Poise')), 'Stanced')).to be false
        end

        it "should count a stance feat the level-up in progress takes" do
          char = matrix_char(:feats => matrix_holding('Crane Poise'), :advancing => true)
          allow(char).to receive(:pf2_advancement).and_return('feats' => { 'charclass' => [ 'Tiger Poise' ] })

          expect(matrix_allows?(char, 'Stanced')).to be true
        end
      end

      describe "a specialty joined through a choice" do
        it "should not count one chosen without joining it" do
          expect(matrix_allows?(matrix_char(:choices => { 'Crossing' => [ 'Leaf' ] }), 'Leafy')).to be false
        end

        it "should count one picked during the level-up in progress" do
          char = matrix_char(:advancing => true)
          allow(char).to receive(:pf2_to_assign).and_return('feat_choices' => { 'Explorer' => [ 'Leaf' ] })

          expect(matrix_allows?(char, 'Leafy')).to be true
        end
      end

      describe "a sanctification" do
        it "should refuse a character with none" do
          expect(matrix_allows?(matrix_char(:sanctification => 'Unsanctified'), 'Sanctified')).to be false
        end
      end

      # A witch's familiar is a class feature, not the Familiar feat.
      describe "a familiar" do
        it "should count a Familiar class feature" do
          expect(matrix_allows?(matrix_char(:features => [ 'Familiar' ]), 'Bonded')).to be true
        end

        it "should not count a feature that only mentions one" do
          expect(matrix_allows?(matrix_char(:features => [ 'Familiar Master' ]), 'Bonded')).to be false
        end
      end

      describe "a combat stat" do
        it "should refuse a factor it does not know rather than letting it through" do
          expect(matrix_allows?(matrix_char(:saves => { 'reflex' => 'legendary' }), 'Unknowable')).to be false
        end

        it "should read the save it names and not another" do
          expect(matrix_allows?(matrix_char(:saves => { 'fortitude' => 'master' }), 'Evasive')).to be false
        end

        it "should count an unarmed attack as a weapon" do
          expect(matrix_allows?(matrix_char(:weapon_prof => { 'unarmed' => 'expert' }), 'Armed')).to be true
        end

        it "should not count a weapon below the rank asked for" do
          expect(matrix_allows?(matrix_char(:weapon_prof => { 'simple' => 'trained' }), 'Armed')).to be false
        end
      end

      # A declared overlap has to be real. Without this the table above could hide a gate that
      # never refuses anything.
      describe "a declared overlap" do
        OVERLAPS.each_pair do |feat, others|
          others.each do |other_feat|
            it "should really let #{other_feat}'s mutation satisfy #{feat}" do
              expect(matrix_allows?(matrix_char(PASSES[other_feat]), feat)).to be true
            end
          end
        end
      end
    end
  end
end
