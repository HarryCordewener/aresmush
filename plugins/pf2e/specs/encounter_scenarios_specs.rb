require "plugin_test_loader"
require_relative "support/auto_builder"
require_relative "support/scenario_runner"

module AresMUSH
  module Pf2e

    # Five encounters played whole, through the commands a GM and four players type: a party built
    # through chargen and advancement, outfitted from the shops, two fights of moderate threat for their
    # level, the second carrying on from the first. Each player tries everything their sheet gives them -
    # their weapons, their class's actions, their spells, their items - and the scenario's report says
    # how each went.
    #
    # Set SCENARIO_OUT to a directory to keep each scenario's transcript and report there.
    describe "encounters played through", :dbtest => true do

      Seat = ScenarioRunner::Seat

      def self.potion(level)
        { 1 => 'Healing Potion (Minor)', 6 => 'Healing Potion (Lesser)', 11 => 'Healing Potion (Moderate)',
          16 => 'Healing Potion (Greater)', 20 => 'Healing Potion (Major)' }[level]
      end

      # What a character of the level carries on their weapon and armour, by the levels the runes are.
      def self.runes(level)
        {
          1 => {},
          6 => { 'potency' => 1, 'striking' => 1, 'armor_potency' => 1 },
          11 => { 'potency' => 2, 'striking' => 1, 'armor_potency' => 1, 'resilient' => 1, 'property' => [ 'Flaming' ] },
          16 => { 'potency' => 2, 'striking' => 2, 'armor_potency' => 2, 'resilient' => 2, 'property' => [ 'Flaming', 'Frost' ] },
          20 => { 'potency' => 3, 'striking' => 3, 'armor_potency' => 3, 'resilient' => 3,
                  'property' => [ 'Flaming', 'Frost', 'Shock' ] }
        }[level]
      end

      def self.kit(level, weapons:, armor: nil, shields: nil, extra: [], alchemy: [])
        {
          'weapons' => weapons, 'armor' => armor, 'shields' => shields,
          'consumables' => [ [ potion(level), 2 ] ] + extra,
          'runes' => runes(level), 'alchemy' => alchemy
        }
      end

      SCENARIOS = {
        1 => {
          seats: [
            Seat.new(charclass: 'Fighter', ancestry: 'Khazad', heritage: 'Rock', background: 'Guard',
                     kit: kit(1, weapons: [ 'Longsword' ], armor: 'Chain Mail', shields: 'Steel Shield')),
            Seat.new(charclass: 'Cleric', ancestry: 'Human', heritage: 'Versatile', background: 'Acolyte',
                     kit: kit(1, weapons: [ 'Mace' ], armor: 'Hide', shields: 'Wooden Shield')),
            Seat.new(charclass: 'Rogue', ancestry: 'Goblin', heritage: 'Unbreakable', background: 'Criminal',
                     kit: kit(1, weapons: [ 'Rapier', 'Shortbow' ], armor: 'Studded Leather')),
            Seat.new(charclass: 'Wizard', ancestry: 'Sildanyar', heritage: 'Seer', background: 'Scholar',
                     kit: kit(1, weapons: [ 'Staff' ], armor: "Explorer's Clothing"))
          ],
          waves: [ [ [ 1, 'Bugbear Prowler' ], [ 1, 'Goblin Warrior' ] ],
                   [ [ 1, 'Boggard Warrior' ], [ 1, 'Giant Rat' ] ] ]
        },
        6 => {
          seats: [
            Seat.new(charclass: 'Barbarian', ancestry: 'Oruch', heritage: 'Battle-ready', background: 'Gladiator',
                     kit: kit(6, weapons: [ 'Greataxe' ], armor: 'Hide')),
            Seat.new(charclass: 'Bard', ancestry: 'Bassin', heritage: 'Gutsy', background: 'Entertainer',
                     kit: kit(6, weapons: [ 'Rapier' ], armor: 'Leather')),
            Seat.new(charclass: 'Ranger', ancestry: 'Egalrin', heritage: 'Skyborn', background: 'Hunter',
                     kit: kit(6, weapons: [ 'Longbow', 'Shortsword' ], armor: 'Leather')),
            Seat.new(charclass: 'Druid', ancestry: 'Kailli', heritage: 'Tunnel Kailli', background: 'Herbalist',
                     kit: kit(6, weapons: [ 'Sickle' ], armor: 'Hide', shields: 'Wooden Shield'))
          ],
          waves: [ [ [ 1, 'Frost Drake' ], [ 1, 'Gargoyle' ] ],
                   [ [ 1, 'Dullahan' ], [ 1, 'Dwarf Stonecaster' ] ] ]
        },
        11 => {
          seats: [
            Seat.new(charclass: 'Champion', ancestry: 'Human', heritage: 'Skilled', background: 'Squire',
                     kit: kit(11, weapons: [ 'Longsword' ], armor: 'Full Plate', shields: 'Steel Shield')),
            Seat.new(charclass: 'Sorcerer', ancestry: 'Ciith', heritage: 'Xalli', background: 'Fortune Teller',
                     kit: kit(11, weapons: [ 'Dagger' ], armor: "Explorer's Clothing")),
            Seat.new(charclass: 'Monk', ancestry: 'Sildanyar', heritage: 'Woodland', background: 'Martial Disciple',
                     kit: kit(11, weapons: [ 'Staff' ])),
            Seat.new(charclass: 'Investigator', ancestry: 'Arvek', heritage: 'Shortshanks', background: 'Detective',
                     kit: kit(11, weapons: [ 'Rapier', 'Hand Crossbow' ], armor: 'Leather'))
          ],
          waves: [ [ [ 1, 'Great Cyclops' ], [ 1, 'Frost Giant' ] ],
                   [ [ 1, 'Lich' ], [ 1, 'Greater Hell Hound' ] ] ]
        },
        16 => {
          seats: [
            Seat.new(charclass: 'Swashbuckler', ancestry: 'Egalrin', heritage: 'Stormtossed', background: 'Acrobat',
                     kit: kit(16, weapons: [ 'Rapier', 'Whip' ], armor: 'Leather')),
            Seat.new(charclass: 'Oracle', ancestry: 'Gnome', heritage: 'Sensate', background: 'Haunted',
                     kit: kit(16, weapons: [ 'Spear' ], armor: 'Studded Leather')),
            Seat.new(charclass: 'Alchemist', ancestry: 'Goblin', heritage: 'Irongut', background: 'Artisan',
                     kit: kit(16, weapons: [ 'Dagger' ], armor: 'Leather',
                              extra: [ [ "Alchemist's Fire (Greater)", 2 ], [ 'Elixir of Life (Greater)', 1 ] ],
                              alchemy: [ "Alchemist's Fire (Greater)", 'Elixir of Life (Greater)' ])),
            Seat.new(charclass: 'Witch', ancestry: 'Kailli', heritage: 'Shadow Kailli', background: 'Hermit (Occultism)',
                     kit: kit(16, weapons: [ 'Staff' ], armor: "Explorer's Clothing"))
          ],
          waves: [ [ [ 1, 'Ice Linnorm' ], [ 1, 'Crag Linnorm' ] ],
                   [ [ 1, 'Banshee' ], [ 1, 'Caldera Oni' ] ] ]
        },
        20 => {
          seats: [
            Seat.new(charclass: 'Fighter', ancestry: 'Oruch', heritage: 'Winter', background: 'Laborer',
                     kit: kit(20, weapons: [ 'Greatsword', 'Longbow' ], armor: 'Full Plate')),
            Seat.new(charclass: 'Wizard', ancestry: 'Gnome', heritage: 'Umbral', background: 'Astrologer',
                     kit: kit(20, weapons: [ 'Staff' ], armor: "Explorer's Clothing")),
            Seat.new(charclass: 'Cleric', ancestry: 'Khazad', heritage: 'Death Warden', background: 'Blessed',
                     kit: kit(20, weapons: [ 'Warhammer' ], armor: 'Breastplate', shields: 'Steel Shield')),
            Seat.new(charclass: 'Rogue', ancestry: 'Bassin', heritage: 'Twilight', background: 'Charlatan',
                     kit: kit(20, weapons: [ 'Shortsword', 'Shortbow' ], armor: 'Studded Leather'))
          ],
          waves: [ [ [ 1, 'Grim Reaper' ], [ 1, 'Kraken' ] ],
                   [ [ 1, 'Tor Linnorm' ], [ 1, 'Magma Worm' ] ] ]
        }
      }.freeze

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        allow(Scenes).to receive(:add_to_scene)
        allow(Scenes).to receive(:create_log)
        allow(Global).to receive(:client_monitor).and_return(double(:notify_web_clients => nil, :emit_all_ooc => nil,
                                                                    :logged_in => {}, :find_client => nil))
      end

      after(:each) do
        @runner&.cleanup!
      end

      def play(level)
        scenario = SCENARIOS[level]
        @runner = ScenarioRunner.new("Level #{level}", level: level, seats: scenario[:seats], waves: scenario[:waves])
        runner = @runner

        allow_any_instance_of(Room).to receive(:emit) { |_room, message| runner.heard(message) }
        allow_any_instance_of(Room).to receive(:emit_ooc) { |_room, message| runner.heard(message) }
        allow(Login).to receive(:emit_ooc_if_logged_in) { |who, message| runner.heard(message, who&.name) }
        allow(Login).to receive(:emit_if_logged_in) { |who, message| runner.heard(message, who&.name) }
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == runner.gm&.id }

        runner.run!
        keep(runner, level)
        runner
      end

      def keep(runner, level)
        dir = ENV['SCENARIO_OUT']

        return unless dir

        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "level-#{level}-transcript.md"), runner.lines.join("\n"))
        File.write(File.join(dir, "level-#{level}-report.md"), runner.report)
      end

      SCENARIOS.each_key do |level|
        it "should play a level #{level} party through two encounters without an error" do
          runner = play(level)

          expect(runner.errors.map { |one| "#{one.who}: #{one.text} -> #{one.status}" }).to eq []
          expect(runner.encounters.size).to eq 2
          runner.party.each { |char| expect(runner.tries.count { |one| one.who == char.name && one.outcome.ok? }).to be > 3 }
        end
      end
    end
  end
end
