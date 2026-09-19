require "plugin_test_loader"

module AresMUSH

  # The figures on the sheet, assembled from a base and a list of typed modifiers.
  #
  # Every one of these used to be summed by hand in whichever model owned it, and nothing carried a
  # type, so nothing could say that two item bonuses are the better of the two rather than their
  # total. Conditions reached none of them: `pf2_conditions` was written, displayed, and read for
  # mechanics in exactly one place.
  describe Pf2e::Stat, :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Stat#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @combat = Pf2eCombat.create(:character => @char)

      @char.update(:hp => @hp, :combat => @combat, :pf2_level => 5, :pf2_conditions => {},
                   :pf2_movement => { 'base_speed' => 25 })

      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
      }
    end

    after(:each) do
      Array(@abilities).each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def score(ability, value)
      @abilities.find { |a| a.name == ability }.update(:base_val => value)
    end

    def condition(name, value = nil)
      held = { 'status' => true }
      held['value'] = value if value

      @char.update(:pf2_conditions => @char.pf2_conditions.merge(name => held))
    end

    describe "hit points" do
      it "should be the class and ancestry tables plus constitution per level" do
        expect(Pf2e::Stat.total(reread, 'hp')).to eq Pf2eHP.base_max_hp(reread)
      end

      # Drained takes level × its value off the maximum. The condition says so itself, as a formula,
      # which is why a per-level reduction needs no per-level code.
      it "should lose level times the value to Drained" do
        before = Pf2e::Stat.total(reread, 'hp')

        condition('Drained', 2)

        expect(Pf2e::Stat.total(reread, 'hp')).to eq before - 10
      end

      it "should show Drained in the breakdown rather than only in the total" do
        condition('Drained', 2)

        sources = Pf2e::Stat.of(reread, 'hp')['modifiers'].map { |row| row['source'] }

        expect(sources).to include 'Drained'
      end

      # Frightened is a penalty to checks and DCs. Hit points are neither.
      it "should not move for a condition that penalises checks" do
        before = Pf2e::Stat.total(reread, 'hp')

        condition('Frightened', 2)

        expect(Pf2e::Stat.total(reread, 'hp')).to eq before
      end
    end

    describe "a condition that penalises everything" do
      it "should reach a saving throw" do
        before = Pf2eCombat.get_save_bonus(reread, 'fortitude')

        condition('Frightened', 2)

        expect(Pf2eCombat.get_save_bonus(reread, 'fortitude')).to eq before - 2
      end

      it "should reach armour class" do
        before = Pf2eCombat.calculate_ac(reread)

        condition('Frightened', 1)

        expect(Pf2eCombat.calculate_ac(reread)).to eq before - 1
      end

      it "should reach perception" do
        before = Pf2eCombat.get_perception(reread)

        condition('Frightened', 3)

        expect(Pf2eCombat.get_perception(reread)).to eq before - 3
      end

      it "should reach the class DC" do
        @combat.update(:class_dc => 'expert', :key_abil => 'Strength')

        before = Pf2eCombat.get_class_dc(reread)

        condition('Frightened', 1)

        expect(Pf2eCombat.get_class_dc(reread)).to eq before - 1
      end
    end

    # Clumsy names `dex-based`, and every statistic that reads Dexterity picks it up without the
    # condition naming any of them.
    describe "a condition that penalises an attribute" do
      it "should reach the save that reads that attribute" do
        before = Pf2eCombat.get_save_bonus(reread, 'reflex')

        condition('Clumsy', 2)

        expect(Pf2eCombat.get_save_bonus(reread, 'reflex')).to eq before - 2
      end

      it "should leave a save that reads another attribute alone" do
        before = Pf2eCombat.get_save_bonus(reread, 'will')

        condition('Clumsy', 2)

        expect(Pf2eCombat.get_save_bonus(reread, 'will')).to eq before
      end
    end

    # A save has two spellings and one statistic, so both spellings have to reach the same domain.
    describe "a save named either way" do
      it "should give the same answer for fort and fortitude" do
        condition('Frightened', 2)

        expect(Pf2eCombat.get_save_bonus(reread, 'fort'))
          .to eq Pf2eCombat.get_save_bonus(reread, 'fortitude')
      end

      it "should reach a condition that names the save in full when asked for the shorthand" do
        long = Pf2e::Stat.of(reread, 'save', 'fort')['modifiers']

        expect(Pf2e::Stat.of(reread, 'save', 'fortitude')['modifiers']).to eq long
      end

      it "should give a save the same domains under either spelling" do
        expect(Pf2e::Domains.for('save', Pf2e.canonical_save('ref'), 'Dexterity'))
          .to include 'reflex'
      end
    end

    describe "two conditions at once" do
      # Both are status penalties, so the lowest of them applies and the other is switched off. Two
      # status penalties do not add.
      it "should take the worse of two status penalties rather than both" do
        before = Pf2eCombat.get_save_bonus(reread, 'reflex')

        condition('Frightened', 1)
        condition('Sickened', 3)

        expect(Pf2eCombat.get_save_bonus(reread, 'reflex')).to eq before - 3
      end

      it "should keep the overridden one on the list" do
        condition('Frightened', 1)
        condition('Sickened', 3)

        rows = Pf2e::Stat.of(reread, 'save', 'reflex')['modifiers']
        frightened = rows.find { |row| row['source'] == 'Frightened' }

        expect(frightened['enabled']).to be false
      end

      # A status penalty and a circumstance penalty are different types, so both count.
      it "should add penalties of different types" do
        before = Pf2eCombat.calculate_ac(reread)

        condition('Frightened', 1)
        condition('Off-Guard')

        expect(Pf2eCombat.calculate_ac(reread)).to eq before - 3
      end
    end

    # An archetype's class DC is the same figure as the character's own with different inputs, so it takes
    # the same modifiers: Frightened reduces it, because it is a DC.
    describe "an archetype's class DC" do
      def archetype
        { 'prof' => 'expert', 'key_abil' => 'Charisma' }
      end

      it "should be ten plus the archetype's proficiency and attribute" do
        score('Charisma', 18)

        expect(Pf2e::Stat.total(reread, 'class_dc', archetype)).to eq 10 + (4 + 5) + 4
      end

      it "should read the archetype's attribute rather than the character's own class attribute" do
        @combat.update(:key_abil => 'Strength', :class_dc => 'trained')
        score('Charisma', 18)
        score('Strength', 10)

        expect(Pf2e::Stat.total(reread, 'class_dc', archetype))
          .to be > Pf2e::Stat.total(reread, 'class_dc')
      end

      it "should take a penalty written against every check and DC" do
        before = Pf2e::Stat.total(reread, 'class_dc', archetype)

        condition('Frightened', 2)

        expect(Pf2e::Stat.total(reread, 'class_dc', archetype)).to eq before - 2
      end
    end

    # Spell DCs and spell attacks read the casting attribute, so Stupefied reaches them by naming the
    # attribute rather than by naming spellcasting.
    describe "spellcasting" do
      def caster(ability = 'Wisdom')
        { 'prof_level' => 'expert', 'spell_abil' => ability, 'tradition' => 'divine' }
      end

      it "should be ten plus proficiency plus the casting attribute" do
        score('Wisdom', 18)

        expect(Pf2e::Stat.total(reread, 'spell_dc', caster)).to eq 10 + 4 + 5 + 4
      end

      it "should lose the casting attribute's penalty to Stupefied" do
        before = Pf2e::Stat.total(reread, 'spell_dc', caster)

        condition('Stupefied', 2)

        expect(Pf2e::Stat.total(reread, 'spell_dc', caster)).to eq before - 2
      end

      it "should leave a Strength caster alone when Stupefied, which no class is" do
        before = Pf2e::Stat.total(reread, 'spell_dc', caster('Strength'))

        condition('Stupefied', 2)

        expect(Pf2e::Stat.total(reread, 'spell_dc', caster('Strength'))).to eq before
      end

      it "should reach a spell attack too" do
        before = Pf2e::Stat.total(reread, 'spell_attack', caster)

        condition('Stupefied', 3)

        expect(Pf2e::Stat.total(reread, 'spell_attack', caster)).to eq before - 3
      end

      it "should be the DC less ten, for the same caster" do
        expect(Pf2e::Stat.total(reread, 'spell_attack', caster))
          .to eq Pf2e::Stat.total(reread, 'spell_dc', caster) - 10
      end
    end

    describe "speed" do
      it "should be the ancestry's" do
        expect(Pf2e::Stat.total(reread, 'speed')).to eq 25
      end

      it "should lose ten feet to Encumbered" do
        condition('Encumbered')

        expect(Pf2e::Stat.total(reread, 'speed')).to eq 15
      end
    end

    # An attack is described rather than named, so a catalogue weapon and an unarmed attack go through
    # the same arithmetic instead of each assembling its own.
    describe "attacks" do
      def melee(traits = [])
        { 'name' => 'Fist', 'prof' => 'trained', 'traits' => traits, 'ranged' => false, 'rune' => 0 }
      end

      it "should read Strength for an ordinary melee attack" do
        score('Strength', 18)
        score('Dexterity', 10)

        expect(Pf2e::Stat.of(reread, 'attack', melee)['modifiers'].map { |r| r['source'] })
          .to include 'Strength'
      end

      # Finesse is not a comparison in the arithmetic: both attributes are offered and the stacking
      # rule takes the better, because attribute modifiers never stack with each other.
      it "should take the better attribute for a finesse attack" do
        score('Strength', 10)
        score('Dexterity', 18)

        counted = Pf2e::Stat.of(reread, 'attack', melee([ 'finesse' ]))['modifiers']
                            .select { |row| row['enabled'] }.map { |row| row['source'] }

        expect(counted).to include 'Dexterity'
        expect(counted).to_not include 'Strength'
      end

      it "should count only one of the two attributes it offered" do
        score('Strength', 18)
        score('Dexterity', 18)

        rows = Pf2e::Stat.of(reread, 'attack', melee([ 'finesse' ]))['modifiers']
        attributes = rows.select { |row| row['type'] == 'ability' }

        expect(attributes.size).to eq 2
        expect(attributes.count { |row| row['enabled'] }).to eq 1
      end

      it "should take a circumstance penalty from Prone" do
        before = Pf2e::Stat.total(reread, 'attack', melee)

        condition('Prone')

        expect(Pf2e::Stat.total(reread, 'attack', melee)).to eq before - 2
      end

      it "should take a penalty written against every check" do
        before = Pf2e::Stat.total(reread, 'attack', melee)

        condition('Frightened', 2)

        expect(Pf2e::Stat.total(reread, 'attack', melee)).to eq before - 2
      end

      # Prone's is a circumstance penalty and Frightened's a status penalty, so they are different
      # types and both apply.
      it "should add Prone and Frightened, which are different types" do
        before = Pf2e::Stat.total(reread, 'attack', melee)

        condition('Prone')
        condition('Frightened', 1)

        expect(Pf2e::Stat.total(reread, 'attack', melee)).to eq before - 3
      end
    end

    describe "the arithmetic it reports" do
      it "should name the attribute it counted" do
        sources = Pf2e::Stat.of(reread, 'save', 'fortitude')['modifiers'].map { |row| row['source'] }

        expect(sources).to include 'Constitution'
      end

      it "should total to the base plus what it enabled" do
        condition('Frightened', 2)

        result = Pf2e::Stat.of(reread, 'save', 'will')
        counted = result['modifiers'].select { |row| row['enabled'] }.sum { |row| row['value'] }

        expect(result['total']).to eq result['base'] + counted
      end
    end

    # A figure asks which feats, items and conditions carry effects, which is a config lookup per feat
    # and a sweep of the inventory. A sheet shows a great many figures, and the read block the sheet
    # commands open is what keeps that to one question.
    describe "reading the sources once" do
      it "should assemble them once for a whole block of figures" do
        expect(Pf2e::Effects).to receive(:conditions).once.and_return([])

        char = reread

        Pf2e::SheetReads.holding(char) do
          Pf2e::Stat.total(char, 'ac')
          Pf2e::Stat.total(char, 'perception')
          Pf2e::Stat.total(char, 'save', 'will')
        end
      end

      it "should still answer with no block open" do
        condition('Frightened', 1)

        expect(Pf2e::Stat.total(reread, 'save', 'will')).to be_a Integer
      end
    end

    # `sheet/why` is the whole reason an overridden modifier stays on the list, so it is worth proving
    # the page renders rather than finding out in game.
    describe "what a player is shown" do
      it "should render the breakdown" do
        condition('Frightened', 2)

        rendered = Pf2e::PF2StatBreakdownTemplate.new('Will', Pf2e::Stat.of(reread, 'save', 'will')).render

        expect(rendered).to match(/Will/)
        expect(rendered).to match(/Frightened/)
        expect(rendered).to match(/Wisdom/)
      end

      it "should mark the modifier the stacking rule switched off" do
        condition('Frightened', 1)
        condition('Sickened', 3)

        rendered = Pf2e::PF2StatBreakdownTemplate.new('Will', Pf2e::Stat.of(reread, 'save', 'will')).render

        expect(rendered).to match(/overridden/)
      end

      it "should sign a bonus and a penalty so the arithmetic reads" do
        condition('Frightened', 2)

        rendered = Pf2e::PF2StatBreakdownTemplate.new('Will', Pf2e::Stat.of(reread, 'save', 'will')).render

        expect(rendered).to match(/-2/)
      end
    end

    it "should refuse a kind of statistic it does not know" do
      expect { Pf2e::Stat.total(reread, 'vibes') }.to raise_error(ArgumentError, /vibes/)
    end
  end
end
