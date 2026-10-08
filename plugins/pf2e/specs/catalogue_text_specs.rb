require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a player or GM reads from the catalogues is words: Foundry's enrichers - `@Damage[...]`,
    # `@Localize[...]`, a roll's `|options:` - are made plain when a catalogue is imported.
    describe "the catalogues' text" do
      MARKUP = /@(?:Localize|Damage|Check|UUID|Template)\[|\[\[\/|\|options:/

      root = File.expand_path('../../../game', __dir__)
      files = Dir[File.join(root, 'config', 'pf2e_*.yml')] + Dir[File.join(root, 'bestiary', '*.yml')]

      it "should be read from the catalogues there are" do
        expect(files.size).to be > 50
      end

      it "should hold none of Foundry's markup" do
        leaks = files.flat_map do |path|
          File.foreach(path).with_index(1).select { |line, _| line.match?(MARKUP) }
              .map { |line, number| "#{File.basename(path)}:#{number}: #{line[line =~ MARKUP, 60]}" }
        end

        expect(leaks).to eq []
      end

      # A rule's value is a formula the engine works out; a description, a note or an ability's text
      # is read by a player, and says what a formula comes to in words.
      FORMULA = /@actor\.|@item\.|ternary\(|\|shortLabel|\|immutable/
      PROSE_FIELD = /\A\s*(?:description|shortdesc|text|outcome_text|prompt):\s(.*)\z/
      PROSE_IN_FLOW = /"(?:text|description)": "((?:[^"\\]|\\.)*)"/

      it "should hold no roll formula in what a player reads" do
        leaks = files.flat_map do |path|
          File.foreach(path).with_index(1).flat_map do |line, number|
            prose = (found = line.chomp.match(PROSE_FIELD)) ? [ found[1] ] : line.scan(PROSE_IN_FLOW).flatten

            prose.select { |text| text.match?(FORMULA) }
                 .map { |text| "#{File.basename(path)}:#{number}: #{text[text =~ FORMULA, 60]}" }
          end
        end

        expect(leaks).to eq []
      end
    end
  end
end
