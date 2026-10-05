require "plugin_test_loader"
require_relative "../../pf2e/specs/support/auto_builder"

module AresMUSH
  module Pf2emagic

    # A caster's focus pool: one point for each focus spell they know that costs one, up to three.
    # Cantrips - a bard's compositions, a witch's hex cantrips - cost nothing and add nothing.
    #
    # The maximum is counted from the spells whenever it is asked for. Only what is left of it is
    # stored.
    describe "focus pool", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Pool#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      def as(charclass, specialize: nil, feats: {})
        base = @char.pf2_base_info.merge('charclass' => charclass)
        base['specialize'] = specialize if specialize

        @char.update(:pf2_base_info => base, :pf2_feats => feats)
        @char = Character[@char.id]
      end

      def magic
        PF2Magic[@magic.id]
      end

      def max
        Pf2emagic.focus_pool_max(magic)
      end

      def remaining
        magic.focus_pool['current'].to_i
      end

      def left(points)
        @magic.update(:focus_pool => { 'current' => points })
      end

      def know(type, spells, kind: 'spell', granted_by: 'Test')
        Entries.grant_focus!(Character[@char.id], type, spells, :kind => kind, :granted_by => granted_by)
      end

      # Through the grant path every class, feat and choice uses.
      def grant(type, spells)
        PF2Magic.update_magic(Character[@char.id], @char.pf2_base_info['charclass'], { 'focus_spell' => { type => spells } }, nil)
      end

      describe :focus_pool_max do
        it "should count each focus spell that costs a point" do
          know('domain', [ 'Soothing Words', 'Unity' ])

          expect(max).to eq 2
        end

        it "should not count a focus cantrip" do
          know('composition', [ 'Courageous Anthem' ], :kind => 'cantrip')

          expect(max).to eq 0
        end

        # Rallying Anthem is rank 2, and a cantrip all the same.
        it "should not count a composition cantrip filed among the spells" do
          know('composition', [ 'Rallying Anthem' ])

          expect(max).to eq 0
        end

        it "should count a spell two sources grant once" do
          know('domain', [ 'Soothing Words' ], :granted_by => 'Domain Family')
          know('domain', [ 'Soothing Words' ], :granted_by => 'Cleric')

          expect(max).to eq 1
        end

        it "should stop at three" do
          know('domain', [ 'Soothing Words', 'Unity', "Healer's Blessing", 'Rebuke Death' ])

          expect(max).to eq 3
        end

        it "should be nothing without magic" do
          expect(Pf2emagic.focus_pool_max(nil)).to eq 0
        end
      end

      describe "a granted focus spell" do
        it "should keep a full pool full" do
          as('Cleric')
          know('domain', [ 'Soothing Words' ])
          left(1)
          grant('domain', [ 'Unity' ])

          expect(max).to eq 2
          expect(remaining).to eq 2
        end

        it "should leave spent points spent" do
          as('Cleric')
          know('domain', [ 'Soothing Words' ])
          left(0)
          grant('domain', [ 'Unity' ])

          expect(remaining).to eq 0
        end

        it "should file a composition cantrip as a cantrip, whatever key granted it" do
          as('Bard')
          grant('composition', [ 'Rallying Anthem' ])

          expect(Entries.focus_cantrips(magic, 'composition')).to eq [ 'Rallying Anthem' ]
          expect(Entries.focus_spells(magic, 'composition')).to eq []
        end
      end

      it "should fill the pool at daily preparations" do
        know('domain', [ 'Soothing Words', 'Unity' ])
        left(0)

        Pf2e.daily_refresh_focus_pool(magic)

        expect(remaining).to eq 2
      end

      # A Refocus restores one point, or the whole pool for a feat that says it refills.
      describe :do_refocus do
        def refocus(features: [])
          @char.update(:pf2_features => @char.pf2_features.merge('charclass_features' => features))
          @magic.update(:tradition => @magic.tradition.merge(@char.pf2_base_info['charclass'] => [ 'divine', 'trained' ]))

          Pf2emagic.do_refocus(Character[@char.id], Character[@char.id])
        end

        def three_spells
          know('domain', [ 'Soothing Words', 'Unity', "Healer's Blessing" ])
        end

        it "should restore one point" do
          as('Cleric')
          three_spells
          left(0)

          expect(refocus).to be_nil
          expect(remaining).to eq 1
        end

        it "should refill the pool for a feat that says it does" do
          as('Cleric', :feats => { 'charclass' => [ 'Domain Focus' ] })
          three_spells
          left(0)
          refocus

          expect(remaining).to eq 3
        end

        it "should refill the pool for Revelation's Focus" do
          as('Oracle', :feats => { 'charclass' => [ "Revelation's Focus" ] })
          know('revelation', [ 'Ancestral Touch', 'Ancestral Defense' ])
          left(0)
          refocus

          expect(remaining).to eq 2
        end

        # Major and Extreme Curse raise the most cursebound an oracle can be, and nothing else.
        it "should restore one point to an oracle with Extreme Curse" do
          as('Oracle')
          know('revelation', [ 'Ancestral Touch', 'Ancestral Defense', 'Ancestral Form' ])
          left(0)
          refocus(:features => [ 'Major Curse', 'Extreme Curse' ])

          expect(remaining).to eq 1
        end

        it "should refuse a character with only focus cantrips" do
          as('Bard')
          know('composition', [ 'Courageous Anthem' ], :kind => 'cantrip')

          expect(refocus).not_to be_nil
          expect(remaining).to eq 0
        end
      end

      # Every class that starts with a focus spell costing a point starts with one point.
      describe "a first-level character built through the real commands" do
        %w{Bard Champion Cleric Druid Oracle Sorcerer Witch Wizard}.each do |charclass|
          it "should give a #{charclass} one focus point" do
            built = Pf2e::AutoBuilder.new(@char).build_level_one(charclass)
            held = Character[built.id].magic

            expect(Pf2emagic.focus_pool_max(held)).to eq 1
            expect(held.focus_pool['current']).to eq 1
          end
        end

        # The Cloistered doctrine grants Domain Initiate, whose domain is picked with cg/option.
        it "should give a Cloistered Cleric the initial spell of the domain they pick" do
          built = Pf2e::AutoBuilder.new(@char).build_level_one('Cleric')
          magic = Character[built.id].magic

          expect(built.pf2_base_info['specialize']).to eq 'Cloistered'
          expect(Entries.focus_spells(magic, 'domain')).to eq [ 'Soothing Words' ]
        end

        # Player Core: Patron's Puppet or Phase Familiar, picked with cg/option.
        it "should give a Witch the hex she picks at first level" do
          built = Pf2e::AutoBuilder.new(@char).build_level_one('Witch')
          magic = Character[built.id].magic

          expect(Entries.focus_spells(magic, 'hex')).to eq [ "Patron's Puppet" ]
        end
      end
    end
  end
end
