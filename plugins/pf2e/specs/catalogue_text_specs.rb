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
    end
  end
end
