require "plugin_test_loader"

module AresMUSH

  # What armour costs the character wearing it.
  #
  # PF2e armour hampers Strength- and Dexterity-based skills until its wearer is strong enough for it,
  # and slows them until then too. The check penalty was not applied at all - a character in a
  # breastplate rolled Acrobatics as though unarmoured - and the speed penalty took no account of
  # strength. Both are Foundry's own arithmetic and their own predicates
  # (`character/document.ts:848`, `:933`), so a feat that waives one says so by naming its slug.
  describe "armour penalties", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Armor#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_derived => {}, :pf2_feats => {}, :pf2_movement => { 'base_speed' => 25 })
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
      }
      @skills = %w{Acrobatics Stealth Arcana}.map { |name|
        Pf2eSkills.create_skill_for_char(name, @char)
      }
      @items = []
    end

    after(:each) do
      @items.each(&:delete)
      @skills.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def wear(name)
      info = Global.read_config('pf2e_armor', name) || raise("no such armour: #{name}")
      item = Pf2egear.create_item(@char, 'armor', name, 1, info)
      item.update(:equipped => true)
      @items << item

      item
    end

    def strength(score)
      @abilities.find { |a| a.name == 'Strength' }.update(:base_val => score)
    end

    def bonus(skill, options = [])
      Pf2eSkills.get_skill_bonus(reread, skill, options)
    end

    describe "the check penalty" do
      it "should hamper a Dexterity-based skill" do
        plain = bonus('Acrobatics')

        wear('Breastplate')

        expect(bonus('Acrobatics')).to eq plain - 2
      end

      it "should not hamper a skill that reads some other attribute" do
        plain = bonus('Arcana')

        wear('Breastplate')

        expect(bonus('Arcana')).to eq plain
      end

      # Strong enough for the armour is the whole condition: the penalty is for struggling with it.
      it "should not hamper a character strong enough for the armour" do
        strength(16)
        plain = bonus('Acrobatics')

        wear('Breastplate')

        expect(bonus('Acrobatics')).to eq plain
      end

      # Flexible armour waives it for Acrobatics and Athletics however strong you are, and for nothing
      # else - which is what their predicate says.
      it "should not hamper Acrobatics in flexible armour" do
        plain = bonus('Acrobatics')

        wear('Chain Shirt')

        expect(bonus('Acrobatics')).to eq plain
      end

      it "should still hamper Stealth in that same flexible armour" do
        plain = bonus('Stealth')

        wear('Chain Shirt')

        expect(bonus('Stealth')).to eq plain - 1
      end

      it "should say what the penalty was for when it did not apply" do
        strength(16)
        wear('Breastplate')

        waived = Pf2eSkills.skill_breakdown(reread, 'Acrobatics')['conditional']

        expect(waived.map { |row| row['slug'] }).to include 'armor-check-penalty'
      end
    end

    describe "the speed penalty" do
      def speed
        Pf2e::Stat.total(reread, 'speed', 'land')
      end

      it "should slow a character in armour they are not strong enough for" do
        plain = speed

        wear('Breastplate')

        expect(speed).to eq plain - 5
      end

      # Five feet of it is what strength buys back, and it never makes anyone faster.
      it "should slow a strong character less" do
        strength(16)
        plain = speed

        wear('Breastplate')

        expect(speed).to eq plain
      end

      it "should still slow a strong character in the heaviest armour" do
        strength(18)
        plain = speed

        wear('Dragonplate (Avarice)')

        expect(speed).to eq plain - 5
      end
    end

    # Armored Stealth reduces the armour penalty to Stealth by one for each rank past trained. Its rule
    # adjusts the penalty rather than adding a bonus of its own, so the penalty has to exist to adjust -
    # and the reduction is a formula over the character's Stealth rank, so the rank has to be readable.
    describe "a feat that reduces the check penalty" do
      before(:each) do
        wear('Breastplate')
        @char.update(:pf2_feats => { 'skill' => [ 'Armored Stealth' ] })
      end

      # What the penalty came to, as the breakdown reports it: the adjustment changes the modifier
      # rather than adding one beside it, so there is one row either way.
      def penalty_on(skill)
        row = Pf2eSkills.skill_breakdown(reread, skill)['modifiers']
                        .find { |one| one['slug'] == 'armor-check-penalty' }

        row && row['value']
      end

      def stealth_at(rank)
        @skills.find { |s| s.name == 'Stealth' }.update(:prof_level => rank)
      end

      it "should reduce nothing for a character trained in Stealth" do
        stealth_at('trained')

        expect(penalty_on('Stealth')).to eq(-2)
      end

      it "should reduce it by one for an expert" do
        stealth_at('expert')

        expect(penalty_on('Stealth')).to eq(-1)
      end

      it "should take it away entirely for a master" do
        stealth_at('master')

        expect(penalty_on('Stealth')).to eq 0
      end

      it "should leave another skill hampered, since the feat is about Stealth" do
        stealth_at('master')

        expect(penalty_on('Acrobatics')).to eq(-2)
      end
    end
  end
end
