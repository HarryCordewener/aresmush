require "plugin_test_loader"

module AresMUSH

  # What a property rune does.
  #
  # `etch/property` has always written a list of words onto an item and nothing read it, so a *flaming*
  # rune was decoration. A rune is the one piece of Foundry's mechanics that does not live in their packs
  # - the packs carry it as an item with no rules and the behaviour is a table in their code - so
  # `scripts/import_foundry_runes.py` reads that table into `pf2e_runes.yml` as `rules:` like every other
  # catalogue here, and a rune is a source of effects belonging to the weapon it is etched on.
  describe "property runes", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Rune#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :weapon_prof => { 'martial' => 'expert' })
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {}, :pf2_roll_options => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @items = []
    end

    after(:each) do
      @items.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def weapon(name = 'Longsword', runes: [], potency: 1)
      info = Global.read_config('pf2e_weapons', name) || raise("no such weapon: #{name}")
      item = Pf2egear.create_item(@char, 'weapons', name, 1, info)
      item.update(:equipped => true,
                  :runes => { 'fundamental' => { 'potency' => potency },
                              'property' => { 'list' => runes } })
      @items << item

      item
    end

    def damage(item, options = [])
      Pf2eCombat.damage_breakdown(reread, item.name, item, false, options)
    end

    describe "the catalogue" do
      it "should have been imported" do
        expect(Global.read_config('pf2e_runes').size).to be > 100
      end

      it "should carry what a flaming rune does, in the rule vocabulary the rest of config uses" do
        rules = Global.read_config('pf2e_runes', 'Flaming', 'rules')

        expect(rules.map { |row| row['key'] }.uniq).to eq [ 'DamageDice' ]
        expect(rules.first['damageType']).to eq 'fire'
      end

      # A rune belongs to the weapon it is etched on, so its selector names that weapon rather than
      # every attack the character has.
      it "should name the item it is etched on rather than a statistic" do
        Global.read_config('pf2e_runes').each_pair do |name, info|
          Array(info['rules']).each do |row|
            expect(row['selector']).to match(/\A\{item\|id\}-/), "#{name}: #{row['selector']}"
          end
        end
      end

      it "should say what kind of thing each rune goes on" do
        kinds = Global.read_config('pf2e_runes').values.map { |info| info['kind'] }.uniq

        expect(kinds.sort).to eq %w{armor weapon}
      end

      # Every rule a rune carries goes through the same reader as a feat's, so every field has to be one
      # that reader knows.
      it "should carry only fields the rules reader reads" do
        strays = Global.read_config('pf2e_runes').flat_map { |name, info|
          Array(info['rules']).flat_map { |row|
            kind = Pf2e::Rules::BY_KEY[row['key'].to_s]

            (row.keys.map(&:to_s) - (kind ? kind['fields'] : [])).map { |field| "#{name}: #{field}" }
          }
        }

        expect(strays).to eq []
      end
    end

    describe "a rune that adds damage" do
      it "should add its die to the weapon it is on" do
        plain = damage(weapon)['formula']
        flaming = damage(weapon(runes: [ 'Flaming' ]))['formula']

        expect(plain).to_not include 'fire'
        expect(flaming).to include '1d6 fire'
      end

      it "should not add it to another weapon" do
        weapon('Longsword', :runes => [ 'Flaming' ])
        dagger = weapon('Dagger')

        expect(damage(dagger)['formula']).to_not include 'fire'
      end

      # A flaming rune's persistent d10 is for a critical hit only, which the damage reader already knows
      # how to place - it is the same `critical` a feat's extra die uses.
      it "should keep a critical-only die out of the ordinary roll" do
        sword = weapon(:runes => [ 'Flaming' ])

        expect(damage(sword)['formula']).to_not include 'd10'
        expect(damage(sword)['critical']).to include 'd10'
      end

      # Giant Killing's die is for a giant, which is a circumstance about the target and off until the
      # player says otherwise.
      it "should hold a die back until the circumstance it names holds" do
        sword = weapon(:runes => [ 'Giant Killing' ])

        expect(damage(sword)['formula']).to_not include 'mental'
        expect(damage(sword, [ 'target:trait:giant' ])['formula']).to include 'mental'
      end

      it "should report the one it held back rather than hiding it" do
        sword = weapon(:runes => [ 'Giant Killing' ])

        expect(damage(sword)['conditional'].map { |row| row['source'] }).to include 'Giant Killing'
      end
    end

    # Shockwave's splash is worth the weapon's own number of damage dice, which is a formula reading the
    # weapon it is etched on.
    describe "a rune worth what the weapon rolls" do
      # The splash is worth `@item.baseDamage.dice`, which is the weapon's own dice before anything adds
      # to them - a staff rolls one, so the splash is one.
      it "should read the weapon's own dice" do
        staff = weapon('Bo Staff', :runes => [ 'Shockwave' ])

        expect(damage(staff)['formula']).to include '1 splash bludgeoning'
      end

      # And only where the rune says: shockwave is for a melee weapon dealing bludgeoning damage.
      it "should do nothing to a weapon the rune is not about" do
        sword = weapon('Longsword', :runes => [ 'Shockwave' ])

        expect(damage(sword)['formula']).to_not include 'bludgeoning'
      end
    end

    describe "a rune that changes the outcome" do
      # Keen: a natural 19 with a slashing or piercing weapon is a critical hit.
      def check
        Pf2e::Check.of(reread, 'attack', Pf2eCombat.attack_descriptor(reread, @sword))
      end

      before(:each) { @sword = weapon(:runes => [ 'Keen' ], :potency => 1) }

      it "should turn a near miss into a critical hit" do
        held = check

        expect(held.outcome(held.total + 1, held.total, 19)).to eq Pf2e::Degree::CRITICAL_SUCCESS
      end

      it "should leave a roll that was not a nineteen alone" do
        held = check

        expect(held.outcome(held.total + 1, held.total, 15)).to eq Pf2e::Degree::SUCCESS
      end

      it "should do nothing for a weapon it is not etched on" do
        @sword = weapon('Longsword')
        held = check

        expect(held.outcome(held.total + 1, held.total, 19)).to eq Pf2e::Degree::SUCCESS
      end
    end
  end
end
