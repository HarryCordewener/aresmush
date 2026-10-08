require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # How the sheet lists a bucket of features. The fold only makes a bucket that has something in it,
    # so a character with no archetype has no 'archetype_features' key at all.
    describe Pf2eSheetTemplate do

      def rendered_for(features)
        char = double(:pf2_features => features, :pf2_archetypeinfo => {})
        template = Pf2eSheetTemplate.allocate

        template.instance_variable_set(:@char, char)
        template
      end

      it "should say None for a bucket the fold never made" do
        template = rendered_for('charclass_features' => [ 'Rage' ])

        expect(template.archetype_features).to eq 'None'
        expect(template.class_features).to eq 'Rage'
      end

      it "should say None for an empty bucket" do
        template = rendered_for('charclass_features' => [], 'archetype_features' => [])

        expect(template.class_features).to eq 'None'
        expect(template.archetype_features).to eq 'None'
      end

      it "should list what a bucket holds, in order" do
        template = rendered_for('charclass_features' => [ 'Rage', 'Bravery' ],
                                'archetype_features' => [ 'Basic Bard Spellcasting' ])

        expect(template.class_features).to eq 'Bravery, Rage'
        expect(template.archetype_features).to eq 'Basic Bard Spellcasting'
      end

      # The class table grants "Fifth Doctrine" and the doctrine says what it is; the sheet names it once.
      it "should name a feature once when a specialty's version of it is held too" do
        template = rendered_for('charclass_features' => [ 'Fifth Doctrine', 'Fifth Doctrine (Cloistered)', 'Divine Font' ])

        expect(template.class_features).to eq 'Divine Font, Fifth Doctrine (Cloistered)'
      end

      # A class with no subclass - a fighter - says so rather than leaving the field blank.
      it "should say N/A for a subclass never chosen" do
        template = rendered_for({})

        [ nil, '' ].each do |none|
          template.instance_variable_set(:@base_info, { 'charclass' => 'Fighter', 'specialize' => none })

          expect(template.subclass).to eq 'N/A'
        end
      end

      it "should cope with no features hash at all" do
        expect(rendered_for(nil).class_features).to eq 'None'
      end
    end

    # `sheet/<section>` shows that section and no other.
    describe "a sheet's sections" do

      # The template's own words, with every value it asks for stubbed.
      class SectionSheet
        LISTS = %i{abilities skills saves known_for spell_dcs}.freeze

        attr_reader :section

        def initialize(section)
          @section = section
        end

        def section_line(title)
          "== #{title}"
        end

        def method_missing(name, *_args)
          LISTS.include?(name) ? [] : ''
        end

        def respond_to_missing?(*)
          true
        end
      end

      def shown(section)
        erb = File.read(File.join(Pf2e.plugin_dir, 'templates', 'sheet_template.erb'))

        Erubis::Eruby.new(erb, :bufvar => '@output').evaluate(SectionSheet.new(section)).scan(/^== (.+)$/).flatten
      end

      it "should show only the section asked for" do
        expect(shown('skills')).to eq []
        expect(shown('info')).to eq [ 'Basic Information', 'Traits' ]
        expect(shown('languages')).to eq [ 'Languages' ]
        expect(shown('magic')).to eq [ 'Magic' ]
        expect(shown('combat')).to include('Stats', 'Conditions')
      end

      it "should show every section for all" do
        expect(shown('all')).to include('Basic Information', 'Abilities', 'Stats', 'Skills', 'Languages', 'Feats', 'Magic')
      end
    end
  end
end
