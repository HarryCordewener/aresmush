require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `rules:` - the rule elements a feat, an item or a condition carries, in Foundry's own vocabulary.
    # The thing with the effect carries the effect, so the engine never learns that Toughness exists,
    # and a row copied out of their packs needs no translation to be read here.
    describe Effects do

      def source(rows, badge = nil)
        Effects.source('Something', rows,
                       'id' => 'something',
                       'item' => badge ? { 'badge' => { 'value' => badge } } : {})
      end

      def flat(fields)
        { 'key' => 'FlatModifier' }.merge(fields)
      end

      def context(level = 5)
        { 'actor' => { 'level' => level, 'abilities' => { 'con' => { 'mod' => 3 } } } }
      end

      def modifiers(rows, domains, badge: nil, options: [], level: 5)
        Effects.modifiers([ source(rows, badge) ], domains, context(level), options)
      end

      it "should take a row whose selector the statistic answers to" do
        rows = modifiers([ flat('selector' => 'hp', 'value' => 4) ], [ 'hp' ])

        expect(rows.size).to eq 1
        expect(rows.first['value']).to eq 4
      end

      it "should skip a row whose selector it does not" do
        expect(modifiers([ flat('selector' => 'ac', 'value' => 4) ], [ 'hp' ])).to eq []
      end

      it "should read a selector naming several domains" do
        row = flat('selector' => [ 'ac', 'hp' ], 'value' => 1)

        expect(modifiers([ row ], [ 'hp' ]).size).to eq 1
      end

      it "should read a formula against the character" do
        rows = modifiers([ flat('selector' => 'hp', 'value' => '@actor.level') ], [ 'hp' ], :level => 7)

        expect(rows.first['value']).to eq 7
      end

      # A condition's value is its badge, which is Foundry's word for the number a condition carries,
      # so Frightened 3 and Frightened 1 are the same row.
      it "should read the source's own badge" do
        rows = modifiers([ flat('selector' => 'all', 'value' => '-@item.badge.value') ], [ 'all' ],
                         :badge => 3)

        expect(rows.first['value']).to eq(-3)
      end

      # Drained's own formula, verbatim from their data: a point costs a level's worth of hit points,
      # and at least one even for a character below first level.
      it "should read a formula over both roots, which is how Drained scales" do
        drained = flat('selector' => 'hp', 'value' => 'min(-1 * @actor.level,-1) * @item.badge.value')

        expect(modifiers([ drained ], [ 'hp' ], :badge => 2, :level => 5).first['value']).to eq(-10)
        expect(modifiers([ drained ], [ 'hp' ], :badge => 2, :level => 0).first['value']).to eq(-2)
      end

      it "should carry the type through so stacking can use it" do
        rows = modifiers([ flat('selector' => 'hp', 'type' => 'Status', 'value' => 1) ], [ 'hp' ])

        expect(rows.first['type']).to eq 'status'
      end

      # Untyped is the permissive reading, so a row that forgets to say counts rather than vanishing.
      it "should default to untyped, as Foundry does" do
        expect(modifiers([ flat('selector' => 'hp', 'value' => 1) ], [ 'hp' ]).first['type'])
          .to eq 'untyped'
      end

      it "should clamp a value that says how far it goes" do
        row = flat('selector' => 'hp', 'value' => '@actor.level', 'max' => 3)

        expect(modifiers([ row ], [ 'hp' ], :level => 9).first['value']).to eq 3
      end

      it "should name the attribute rather than the source when the row names one" do
        row = flat('selector' => 'ac', 'type' => 'ability', 'ability' => 'dex', 'value' => 2)

        expect(modifiers([ row ], [ 'ac' ]).first['source']).to eq 'Dex'
      end

      it "should take every matching row from every source" do
        two = [ source([ flat('selector' => 'hp', 'value' => 1), flat('selector' => 'hp', 'value' => 2) ]),
                source([ flat('selector' => 'hp', 'value' => 4) ]) ]

        expect(Effects.modifiers(two, [ 'hp' ], context).map { |row| row['value'] }).to eq [ 1, 2, 4 ]
      end

      it "should contribute nothing for a source with no rules" do
        expect(Effects.modifiers([ { 'name' => 'Plain' } ], [ 'hp' ], context)).to eq []
      end

      it "should keep the kinds apart, so damage dice are not read as modifiers" do
        dice = { 'key' => 'DamageDice', 'selector' => 'damage', 'diceNumber' => 1, 'dieSize' => 'd6' }

        expect(modifiers([ dice ], [ 'damage' ])).to eq []
        expect(Effects.damage_dice([ source([ dice ]) ], [ 'damage' ], context).size).to eq 1
      end

      describe "damage dice" do
        def dice(fields)
          { 'key' => 'DamageDice', 'selector' => 'strike-damage' }.merge(fields)
        end

        it "should carry how many and what size" do
          row = Effects.damage_dice([ source([ dice('diceNumber' => 2, 'dieSize' => 'd6') ]) ],
                                    [ 'strike-damage' ], context).first

          expect(row['dice']).to eq 2
          expect(row['die']).to eq 'd6'
        end

        it "should default to one die" do
          row = Effects.damage_dice([ source([ dice('dieSize' => 'd6') ]) ], [ 'strike-damage' ],
                                    context).first

          expect(row['dice']).to eq 1
        end

        it "should read a formula for how many" do
          row = Effects.damage_dice([ source([ dice('diceNumber' => 'floor(@actor.level/4)',
                                                    'dieSize' => 'd6') ]) ],
                                    [ 'strike-damage' ], context(9)).first

          expect(row['dice']).to eq 2
        end

        it "should carry the kind of damage and the category it is kept apart in" do
          row = Effects.damage_dice([ source([ dice('dieSize' => 'd6', 'damageType' => 'fire',
                                                    'category' => 'persistent') ]) ],
                                    [ 'strike-damage' ], context).first

          expect(row['damage_type']).to eq 'fire'
          expect(row['category']).to eq 'persistent'
        end
      end

      # A selector may name the item carrying the rule, which is how a rune reaches the weapon it is on
      # and nothing else. The item's own facts are what the interpolation reads, so the statistic's
      # domain is the resolved one.
      describe "a selector naming the item itself" do
        it "should resolve to the item's own id" do
          row = flat('selector' => '{item|id}-damage', 'value' => 1)
          sword = source([ row ]).merge('item' => { 'id' => 'sword7', '_id' => 'sword7' })

          expect(Effects.modifiers([ sword ], [ 'sword7-damage' ], context).size).to eq 1
        end

        it "should not reach another item's damage" do
          row = flat('selector' => '{item|id}-damage', 'value' => 1)
          sword = source([ row ]).merge('item' => { 'id' => 'sword7', '_id' => 'sword7' })

          expect(Effects.modifiers([ sword ], [ 'axe9-damage' ], context)).to eq []
        end

        it "should read the underscored spelling their data also uses" do
          row = flat('selector' => '{item|_id}-damage', 'value' => 1)
          sword = source([ row ]).merge('item' => { 'id' => 'sword7', '_id' => 'sword7' })

          expect(Effects.modifiers([ sword ], [ 'sword7-damage' ], context).size).to eq 1
        end
      end

      # Most item bonuses are conditional, and a row whose circumstances are unmet is reported rather
      # than counted - kept out of the stacking so it cannot override one that applies.
      describe "a row with circumstances" do
        def conditional
          flat('selector' => 'thievery', 'type' => 'item', 'value' => 2,
               'predicate' => [ 'action:pick-a-lock' ])
        end

        it "should be met when the circumstances are named" do
          expect(modifiers([ conditional ], [ 'thievery' ], :options => [ 'action:pick-a-lock' ])
                   .first['met']).to be true
        end

        it "should be unmet when they are not" do
          expect(modifiers([ conditional ], [ 'thievery' ]).first['met']).to be false
        end

        it "should still report the row and what it needs" do
          row = modifiers([ conditional ], [ 'thievery' ]).first

          expect(row['value']).to eq 2
          expect(row['when']).to eq [ 'action:pick-a-lock' ]
        end

        it "should be met when there are no circumstances to meet" do
          expect(modifiers([ flat('selector' => 'hp', 'value' => 1) ], [ 'hp' ]).first['met']).to be true
        end

        # A predicate on an item's own rule often asks about that item, so a source may carry its own
        # options alongside the ones the roller supplied.
        it "should test a source's own options too" do
          cloak = source([ conditional ]).merge('options' => [ 'action:pick-a-lock' ])

          expect(Effects.modifiers([ cloak ], [ 'thievery' ], context).first['met']).to be true
        end
      end

      # A rule we do not apply, or a field we do not read, is a sheet that is quietly wrong.
      describe "something we do not implement" do
        # Complained about when the source is assembled, not when a row is applied: the reader filters
        # to the kind it wants first, so a kind nobody wants would otherwise never be looked at.
        it "should say so for a kind nothing applies" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/which nothing applies/)

          # A token's light is Foundry's canvas, which nothing here draws.
          Effects.source('Something', [ { 'key' => 'TokenLight', 'selector' => 'hp' } ])
        end

        it "should contribute nothing for it" do
          allow(Global).to receive(:logger).and_return(double(:warn => nil))

          expect(Effects.modifiers([ source([ { 'key' => 'Aura', 'selector' => 'hp' } ]) ],
                                   [ 'hp' ], context)).to eq []
        end

        it "should say so for a field nothing reads" do
          logger = double
          allow(Global).to receive(:logger).and_return(logger)

          expect(logger).to receive(:warn).with(/fields nothing reads: nonsense/)

          Effects.source('Something', [ flat('selector' => 'hp', 'value' => 1, 'nonsense' => 'x') ])
        end
      end
    end
  end
end
