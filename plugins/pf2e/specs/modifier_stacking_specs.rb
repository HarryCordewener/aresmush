require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # PF2e's bonus arithmetic. A figure is a base plus a list of modifiers, and the type on each
    # modifier decides which of them count - two item bonuses are the better one, not their sum.
    describe Modifiers do

      def mod(type, value, source = 'something')
        { 'source' => source, 'type' => type, 'value' => value }
      end

      def enabled(rows)
        rows.select { |row| row['enabled'] }.map { |row| row['source'] }
      end

      describe "untyped" do
        it "should count every one of them" do
          rows = Modifiers.stack([ mod('untyped', 1, 'a'), mod('untyped', 2, 'b') ])

          expect(enabled(rows)).to eq [ 'a', 'b' ]
          expect(Modifiers.total(rows)).to eq 3
        end
      end

      describe "the ordinary types" do
        it "should take the highest bonus of a type and switch the rest off" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('item', 2, 'spell') ])

          expect(enabled(rows)).to eq [ 'spell' ]
          expect(Modifiers.total(rows)).to eq 2
        end

        it "should leave the overridden modifier on the list, for the breakdown" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('item', 2, 'spell') ])

          expect(rows.size).to eq 2
          expect(rows.find { |row| row['source'] == 'ring' }['enabled']).to be false
        end

        it "should take the lowest penalty as well as the highest bonus" do
          rows = Modifiers.stack([ mod('status', 2, 'up'), mod('status', -1, 'small'),
                                   mod('status', -3, 'big') ])

          expect(enabled(rows)).to eq [ 'up', 'big' ]
          expect(Modifiers.total(rows)).to eq(-1)
        end

        it "should keep types apart, so an item bonus and a status bonus both count" do
          rows = Modifiers.stack([ mod('item', 1, 'ring'), mod('status', 1, 'blessing') ])

          expect(Modifiers.total(rows)).to eq 2
        end

        it "should count a zero as neither bonus nor penalty" do
          rows = Modifiers.stack([ mod('item', 0, 'nothing') ])

          expect(enabled(rows)).to eq []
        end

        it "should break a tie by the order it was given, so a total is not luck" do
          rows = Modifiers.stack([ mod('item', 2, 'first'), mod('item', 2, 'second') ])

          expect(enabled(rows)).to eq [ 'first' ]
        end
      end

      # This is what makes "use your best attribute for AC" fall out rather than being special-cased:
      # offer both attributes as ability modifiers and the better one applies alone.
      describe "attribute modifiers" do
        it "should take the best one and no other" do
          rows = Modifiers.stack([ mod('ability', 2, 'dex'), mod('ability', 4, 'cha') ])

          expect(enabled(rows)).to eq [ 'cha' ]
          expect(Modifiers.total(rows)).to eq 4
        end

        it "should take the least bad when every attribute is a penalty" do
          rows = Modifiers.stack([ mod('ability', -1, 'dex'), mod('ability', -3, 'str') ])

          expect(enabled(rows)).to eq [ 'dex' ]
          expect(Modifiers.total(rows)).to eq(-1)
        end

        it "should count a zero attribute modifier, which is a real score" do
          rows = Modifiers.stack([ mod('ability', 0, 'dex') ])

          expect(enabled(rows)).to eq [ 'dex' ]
        end
      end

      describe "a figure and its arithmetic" do
        it "should report the base, the total and the rows together" do
          result = Modifiers.breakdown(12, [ mod('item', 1, 'ring'), mod('status', -2, 'frightened') ])

          expect(result['base']).to eq 12
          expect(result['total']).to eq 11
          expect(result['modifiers'].size).to eq 2
        end

        it "should be the base alone when nothing modifies it" do
          expect(Modifiers.breakdown(12, [])['total']).to eq 12
        end
      end

      # Proficiency is the other half of every figure's base, and a rank spelled some way the table
      # does not know used to be `nil + level`.
      # A modifier's slug is the name other rules call it by: their AdjustModifier rules name ours as
      # well as their own, so the ones we create ourselves carry Foundry's spelling.
      describe "naming a modifier" do
        it "should slug an attribute modifier with the attribute's short name" do
          allow(Pf2e).to receive(:ability_mod).and_return(3)

          expect(Pf2e::Stat.ability_mod(double, 'Dexterity')['slug']).to eq 'dex'
        end

        it "should slug the save rune the way the rules name it" do
          expect(Pf2e::Stat::RUNE_SLUGS['power']).to eq 'resilient'
        end

        it "should slug what a rule says, in preference to the thing carrying it" do
          row = { 'key' => 'FlatModifier', 'selector' => 'hp', 'value' => 1, 'slug' => 'toughness-hp' }

          expect(Pf2e::Rules.contribute(row, { 'name' => 'Toughness' }, {})['slug']).to eq 'toughness-hp'
        end

        it "should slug from the thing carrying it when the rule does not say" do
          row = { 'key' => 'FlatModifier', 'selector' => 'hp', 'value' => 1 }

          expect(Pf2e::Rules.contribute(row, { 'name' => 'Cat Fall' }, {})['slug']).to eq 'cat-fall'
        end
      end

      # A rule that changes a modifier rather than adding one. Applied before anything is stacked, so the
      # comparison that decides which modifiers count is against the adjusted numbers.
      describe "adjusting a modifier" do
        def adjustment(fields)
          { 'source' => 'Something', 'slug' => nil, 'mode' => 'add', 'value' => 1,
            'suppress' => false, 'relabel' => nil, 'max' => nil, 'when' => nil,
            'held' => [] }.merge(fields)
        end

        def slugged(type, value, slug)
          mod(type, value, slug).merge('slug' => slug)
        end

        it "should change the modifier it names" do
          rows = Modifiers.adjust([ slugged('item', 1, 'ring') ],
                                  [ adjustment('slug' => 'ring', 'value' => 2) ])

          expect(rows.first['value']).to eq 3
        end

        it "should leave a modifier it does not name alone" do
          rows = Modifiers.adjust([ slugged('item', 1, 'ring') ],
                                  [ adjustment('slug' => 'cloak', 'value' => 2) ])

          expect(rows.first['value']).to eq 1
        end

        # A row with no slug reaches every modifier the statistic has, which is how most of their data
        # writes it.
        it "should change every modifier when it names none" do
          rows = Modifiers.adjust([ slugged('item', 1, 'ring'), slugged('status', 2, 'blessing') ],
                                  [ adjustment('value' => 1) ])

          expect(rows.map { |row| row['value'] }).to eq [ 2, 3 ]
        end

        it "should read every mode, since they are the same seven a write uses" do
          rows = Modifiers.adjust([ slugged('item', 2, 'ring') ],
                                  [ adjustment('mode' => 'upgrade', 'value' => 5) ])

          expect(rows.first['value']).to eq 5
        end

        # `suppress` drops the modifier rather than zeroing it, so it is not in the breakdown either.
        it "should drop a modifier it suppresses" do
          rows = Modifiers.adjust([ slugged('item', -2, 'no-crowbar'), slugged('item', 1, 'ring') ],
                                  [ adjustment('slug' => 'no-crowbar', 'suppress' => true) ])

          expect(rows.map { |row| row['slug'] }).to eq [ 'ring' ]
        end

        it "should cap how many modifiers one adjustment changes" do
          rows = Modifiers.adjust([ slugged('item', 1, 'a'), slugged('item', 1, 'b') ],
                                  [ adjustment('value' => 1, 'max' => 1) ])

          expect(rows.map { |row| row['value'] }).to eq [ 2, 1 ]
        end

        it "should rename what it relabels, so a breakdown says what changed it" do
          rows = Modifiers.adjust([ slugged('ability', 2, 'str') ],
                                  [ adjustment('slug' => 'str', 'value' => 2,
                                               'relabel' => 'Intimidating Prowess') ])

          expect(rows.first['source']).to eq 'Intimidating Prowess'
        end

        # The reason it happens first: a raised modifier has to be compared at its raised value.
        it "should decide stacking on the adjusted number" do
          rows = Modifiers.adjust([ slugged('item', 1, 'ring'), slugged('item', 2, 'spell') ],
                                  [ adjustment('slug' => 'ring', 'mode' => 'override', 'value' => 5) ])

          expect(Modifiers.total(Modifiers.stack(rows))).to eq 5
        end

        it "should leave everything alone when nothing adjusts it" do
          rows = Modifiers.adjust([ slugged('item', 1, 'ring') ], [])

          expect(rows.first['value']).to eq 1
        end

        # An adjustment may ask about the modifier it is adjusting rather than about the character, which
        # is how Unburdened Iron lessens armour's speed penalty: it names the penalty by slug and asks
        # how big it is.
        describe "asking about the modifier it adjusts" do
          it "should name it by slug" do
            rows = Modifiers.adjust([ slugged('item', -2, 'armor-speed-penalty') ],
                                    [ adjustment('value' => 1,
                                                 'when' => [ 'penalty:slug:armor-speed-penalty' ]) ])

            expect(rows.first['value']).to eq(-1)
          end

          it "should leave a modifier the predicate does not describe alone" do
            rows = Modifiers.adjust([ slugged('item', -2, 'shield-speed-penalty') ],
                                    [ adjustment('value' => 1,
                                                 'when' => [ 'penalty:slug:armor-speed-penalty' ]) ])

            expect(rows.first['value']).to eq(-2)
          end

          it "should ask how big it is" do
            small = [ slugged('item', -2, 'a') ]
            large = [ slugged('item', -10, 'b') ]
            only_large = [ adjustment('value' => 5, 'when' => [ { 'lte' => [ 'penalty:value', -5 ] } ]) ]

            expect(Modifiers.adjust(small, only_large).first['value']).to eq(-2)
            expect(Modifiers.adjust(large, only_large).first['value']).to eq(-5)
          end

          # A bonus is a bonus and a penalty is a penalty, which is what tells the two prefixes apart.
          it "should call a positive modifier a bonus and a negative one a penalty" do
            bonus = Modifiers.facts_of(slugged('item', 2, 'ring'))
            penalty = Modifiers.facts_of(slugged('item', -2, 'ring'))

            expect(bonus).to include 'bonus:slug:ring'
            expect(penalty).to include 'penalty:slug:ring'
          end
        end
      end

      describe "a proficiency rank we do not know" do
        it "should read it as untrained rather than raise" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))
          allow(Pf2e).to receive(:has_feat?).and_return(false)
          char = double(:pf2_level => 5)

          expect(Pf2e.get_prof_bonus(char, 'exprt')).to eq 0
        end

        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)
          allow(Pf2e).to receive(:has_feat?).and_return(false)

          expect(logger).to receive(:warn).with(/proficiency rank/)

          Pf2e.get_prof_bonus(double(:pf2_level => 5), 'exprt')
        end

        it "should read a missing rank as untrained without complaining" do
          allow(Pf2e).to receive(:has_feat?).and_return(false)

          expect(Pf2e.get_prof_bonus(double(:pf2_level => 5), nil)).to eq 0
        end
      end

      describe "a type we do not know" do
        it "should count it rather than lose it" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))

          rows = Modifiers.stack([ mod('cirmcumstance', 2, 'typo') ])

          expect(Modifiers.total(rows)).to eq 2
        end

        it "should say so in the log" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/unknown type/)

          Modifiers.stack([ mod('cirmcumstance', 2, 'typo') ])
        end
      end
    end
  end
end
