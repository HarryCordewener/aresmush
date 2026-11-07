require "plugin_test_loader"

module AresMUSH
  module Pf2e

    describe "routing spell healing" do
      before(:each) do
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ sides / 2 ] * amount }
        allow(Harm).to receive(:heal)
        allow(Acting).to receive(:deal)
        @out = Acting.report
      end

      { :living => [ 'self:mode:living' ],
        :dar => [ 'self:mode:living', Effects::VOID_HEALING ],
        :undead => [ 'self:mode:undead' ] }.each do |kind, facts|
        context "for #{kind}" do
          before(:each) do
            @target = double(:holder => kind, :label => kind.to_s)
            @scene = Acting::Scene.new(nil, nil, @target, nil, false)
            allow(Effects).to receive(:facts).with(kind).and_return(facts)
          end

          { 'Gentle Breeze' => 10, 'Healing Well' => 16 }.each do |spell, amount|
            it "should only heal compatible recipients of #{spell}" do
              mechanics = Acting.spell_mechanics(spell).last
              formulas = Acting.spell_damage(mechanics, mechanics['rank'])

              Acting.heal_or_hurt(@scene, mechanics, formulas, nil, @out)

              expect(Acting).not_to have_received(:deal)
              if kind == :living
                expect(Harm).to have_received(:heal).with(kind, amount)
              else
                expect(Harm).not_to have_received(:heal)
                expect(@out['lines']).to eq []
              end
            end
          end

          it "should only heal compatible recipients of void healing-only formulas" do
            mechanics = { 'traits' => [ 'void' ] }
            formulas = [ [ '1d8', 'void', nil, [ 'healing' ] ] ]

            Acting.heal_or_hurt(@scene, mechanics, formulas, nil, @out)

            expect(Acting).not_to have_received(:deal)
            if kind == :living
              expect(Harm).not_to have_received(:heal)
              expect(@out['lines']).to eq []
            else
              expect(Harm).to have_received(:heal).with(kind, 4)
            end
          end

          %w{Heal Harm}.each do |spell|
            it "should preserve #{spell}'s dual-kind formula" do
              mechanics = Acting.spell_mechanics(spell).last
              formulas = Acting.spell_damage(mechanics, 1)
              heals = (spell == 'Heal') == (kind == :living)

              Acting.heal_or_hurt(@scene, mechanics, formulas, Degree::FAILURE, @out)

              if heals
                expect(Harm).to have_received(:heal).with(kind, 4)
                expect(Acting).not_to have_received(:deal)
              else
                expect(Harm).not_to have_received(:heal)
                expect(Acting).to have_received(:deal).with(@scene, @target,
                  [ hash_including('amount' => 4) ], @out, :critical => false)
              end
            end
          end

          [ nil, 1, 2, 3 ].each do |actions|
            it "should route Harm with #{actions || 'omitted'} actions at that cost" do
              base = Acting.spell_mechanics('Harm').last
              named = Acting.variant(base, Acting.said(actions ? [ "actions #{actions}" ] : [], false))
              chosen = named.equal?(base) ? Acting.way_for(base, @target) : Acting.way_for(base, @target, named['time']) || named
              formula = actions == 2 && kind != :living ? '1d8+8' : '1d8'

              expect(chosen['damage'].first['formula']).to eq formula
              expect(chosen['time'].to_i).to eq(actions || 1)
            end
          end

          [ nil, 1 ].each do |actions|
            it "should keep Lay on Hands target selection with #{actions || 'omitted'} actions" do
              mechanics = Acting.spell_mechanics('Lay on Hands').last
              chosen = Acting.way_for(mechanics, @target, actions)

              expect(chosen['name']).to eq(kind == :living ? 'Lay on Hands (Healing)' : 'Lay on Hands (Vs. Undead)')
            end
          end
        end
      end

      context "when healing is incompatible" do
        before(:each) do
          @target = double(:holder => :dar, :label => 'Dar')
          @scene = Acting::Scene.new(nil, nil, @target, nil, false)
          allow(Effects).to receive(:facts).with(:dar).and_return([ 'self:mode:living', Effects::VOID_HEALING ])
          @mechanics = { 'traits' => [ 'vitality' ], 'basic' => true }
          @healing = [ '10', 'untyped', nil, [ 'healing' ] ]
        end

        it "should keep damage, dual-kind and legacy formulas while dropping healing-only ones" do
          formulas = [ @healing, [ '1d8', 'fire', nil, [ 'damage' ] ],
                       [ '6', 'vitality', nil, [ 'damage', 'healing' ] ],
                       [ '8', 'cold', nil, nil ], [ '2', 'acid', nil, [] ] ]

          Acting.heal_or_hurt(@scene, @mechanics, formulas, Degree::SUCCESS, @out)

          expect(Harm).not_to have_received(:heal)
          expect(Acting).to have_received(:deal).with(@scene, @target,
            [ hash_including('type' => 'fire', 'amount' => 2),
              hash_including('type' => 'vitality', 'amount' => 3),
              hash_including('type' => 'cold', 'amount' => 4),
              hash_including('type' => 'acid', 'amount' => 1) ], @out, :critical => false)
        end

        it "should not roll an area's healing until a compatible target receives it" do
          once = { 'spell' => 'Gentle Breeze', 'rolled' => {}, 'at' => 0 }
          living = double(:holder => :living, :label => 'Living')
          allow(Effects).to receive(:facts).with(:living).and_return([ 'self:mode:living' ])

          Acting.heal_or_hurt(@scene, @mechanics, [ @healing ], nil, @out, once)
          expect(once['rolled']).to eq({})
          Acting.heal_or_hurt(Acting::Scene.new(nil, nil, living, nil, false), @mechanics, [ @healing ], nil, @out, once)

          expect(Harm).to have_received(:heal).with(:living, 10)
          expect(Acting).not_to have_received(:deal)
          expect(once['rolled'].size).to eq 1
        end

        it "should not roll or report healing-only formulas as unresolved damage" do
          allow(Acting).to receive(:spell_rows).and_call_original

          Acting.heal_or_hurt(@scene, @mechanics.merge('basic' => false), [ @healing ], Degree::FAILURE, @out)

          expect(Acting).not_to have_received(:spell_rows)
          expect(Acting).not_to have_received(:deal)
          expect(Harm).not_to have_received(:heal)
          expect(@out['lines']).to eq []
        end
      end
    end
  end
end
