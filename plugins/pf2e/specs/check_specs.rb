require "plugin_test_loader"

module AresMUSH

  # One check: what is being rolled, against what, and how it went.
  #
  # Every figure up to now was a number on a sheet. A roll is not a figure, and three kinds of rule
  # element in Foundry's data attach to the roll rather than the figure - a note shown with it, a rule
  # that turns a failure into a success, a circumstance declared for its duration. None can be read
  # without something to attach to.
  #
  # It also supplies circumstances nothing else can. Deafened's own rule is predicated on
  # `check:type:skill` and `check:statistic:base:perception`, because it penalises an auditory skill
  # check and a Perception check rather than every check - and those are facts about the roll.
  describe Pf2e::Check, :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Check#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :perception => 'expert')
      @char.update(:combat => @combat, :pf2_level => 10, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => {}, :pf2_feats => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @skill = Pf2eSkills.create(:name => 'Athletics', :character => @char, :prof_level => 'trained')
    end

    after(:each) do
      @skill&.delete
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    describe "the circumstances a check establishes" do
      it "should say which statistic is being rolled" do
        check = Pf2e::Check.of(reread, 'skill', 'Athletics')

        expect(check.options).to include 'check:statistic:athletics'
      end

      # `skill`, `perception`, `saving-throw`: the kind of check, which is what a rule about a kind of
      # check is written against.
      it "should say what kind of check it is" do
        expect(Pf2e::Check.of(reread, 'skill', 'Athletics').options).to include 'check:type:skill'
        expect(Pf2e::Check.of(reread, 'save', 'will').options).to include 'check:type:saving-throw'
        expect(Pf2e::Check.of(reread, 'perception').options).to include 'check:type:perception'
      end

      it "should call a lore a skill check, because that is what it is" do
        expect(Pf2e::Check.of(reread, 'lore', 'Dragon Lore').options).to include 'check:type:skill'
      end

      it "should carry the circumstances the roller named as well" do
        check = Pf2e::Check.of(reread, 'skill', 'Athletics', [ 'action:swim' ])

        expect(check.options).to include 'action:swim'
      end

      it "should carry what is true of the character as well" do
        check = Pf2e::Check.of(reread, 'skill', 'Athletics')

        expect(check.options).to include 'self:level:10'
      end

      # Every one of these answers a predicate that was in config and could never be met without it.
      it "should carry the character's own facts, which imported rules ask about" do
        @char.update(:pf2_base_info => { 'heritage' => 'Cliffscale Lizardfolk', 'charclass' => 'Ranger',
                                         'ancestry' => 'Lizardfolk' },
                     :pf2_feats => { 'general' => [ 'Fleet' ] },
                     :pf2_features => { 'charclass_features' => [ 'Hunt Prey' ] })

        options = Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics').options

        expect(options).to include 'heritage:cliffscale-lizardfolk', 'class:ranger',
                                   'ancestry:lizardfolk', 'feat:fleet', 'feature:hunt-prey'
      end

      it "should say what rank each skill is, which a feat asks about" do
        expect(Pf2e::Check.of(reread, 'skill', 'Athletics').options)
          .to include 'skill:athletics:rank:1'
      end

      it "should say what each attribute is worth" do
        expect(Pf2e::Check.of(reread, 'skill', 'Athletics').options).to include 'attribute:str:2'
      end

      # A check built on another statistic is that check, not the one underneath: rolling initiative off
      # Perception is an initiative check whose base statistic is Perception.
      it "should name an initiative check as one, and say what it is built on" do
        check = Pf2e::Check.of(reread, 'perception', nil, [], [ 'initiative' ])

        expect(check.options).to include 'check:statistic:initiative',
                                        'check:statistic:base:perception', 'check:type:initiative'
      end

      it "should name the skill an initiative check is rolled off" do
        check = Pf2e::Check.of(reread, 'skill', 'Athletics', [], [ 'initiative' ])

        expect(check.options).to include 'check:statistic:base:athletics'
      end

      it "should say a save's name the same way whichever spelling was used" do
        expect(Pf2e::Check.of(reread, 'save', 'fort').options)
          .to include 'check:statistic:fortitude'
      end
    end

    it "should be worth what the figure is worth" do
      expect(Pf2e::Check.of(reread, 'skill', 'Athletics').total)
        .to eq Pf2eSkills.get_skill_bonus(reread, 'Athletics')
    end

    # Deafened is the rule this was needed for. Their own row penalises `perception` and `skill-check`,
    # predicated on the check being an auditory skill check or a Perception-based initiative check, so
    # it reaches neither an ordinary skill check nor a Perception check that is not initiative.
    describe "Deafened, whose rule reads the check rather than the character" do
      before(:each) do
        @char.update(:pf2_conditions => { 'Deafened' => { 'status' => true } })
      end

      it "should leave an ordinary skill check alone" do
        plain = Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics').total

        @char.update(:pf2_conditions => {})

        expect(plain).to eq Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics').total
      end

      it "should penalise an auditory skill check" do
        with = Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics',
                              [ 'item:trait:auditory' ]).total
        without = Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics').total

        expect(with).to eq without - 2
      end

      # The check says it is an initiative check itself, so nobody has to say so - which is the whole
      # point of the roll carrying its own circumstances.
      it "should penalise a Perception check rolled for initiative" do
        plain = Pf2e::Check.of(Character[@char.id], 'perception').total
        initiative = Pf2e::Check.of(Character[@char.id], 'perception', nil, [], [ 'initiative' ]).total

        expect(initiative).to eq plain - 2
      end

      it "should penalise initiative through the command that rolls it" do
        deafened = Pf2e.initiative_bonus(Character[@char.id], 'Perception')

        @char.update(:pf2_conditions => {})

        expect(deafened).to eq Pf2e.initiative_bonus(Character[@char.id], 'Perception') - 2
      end
    end

    describe "how the roll went" do
      def check
        Pf2e::Check.of(reread, 'skill', 'Athletics')
      end

      it "should have no outcome without a DC to measure against" do
        expect(check.outcome(20, nil)).to be_nil
      end

      it "should read the outcome off the total and the DC" do
        expect(check.outcome(20, 20)).to eq Pf2e::Degree::SUCCESS
        expect(check.outcome(30, 20)).to eq Pf2e::Degree::CRITICAL_SUCCESS
      end

      it "should let the die's own face shift it" do
        expect(check.outcome(20, 20, 20)).to eq Pf2e::Degree::CRITICAL_SUCCESS
      end

      it "should have no adjustment when nothing the character carries changes an outcome" do
        expect(check.adjustments).to eq []
      end

      # Note is still unread, and asking through it is what makes reading the kind a change to one table.
      it "should have somewhere for a note to come from" do
        expect(check.notes).to eq []
      end
    end

    # Deafened is the case where both halves land on the same check: a penalty to the roll, and an
    # outcome dropped to a critical failure. Both are its own rules and both are predicated on the check.
    describe "a rule that changes the outcome" do
      before(:each) do
        @char.update(:pf2_conditions => { 'Deafened' => { 'status' => true } })
      end

      def auditory
        Pf2e::Check.of(Character[@char.id], 'perception', nil, [ 'item:trait:auditory' ])
      end

      it "should be found for the check it applies to" do
        expect(auditory.adjustments).to eq [ { 'all' => 'to-critical-failure' } ]
      end

      it "should turn a success into a critical failure" do
        expect(auditory.outcome(30, 20)).to eq Pf2e::Degree::CRITICAL_FAILURE
      end

      it "should leave a check it does not apply to alone" do
        plain = Pf2e::Check.of(Character[@char.id], 'perception')

        expect(plain.adjustments).to eq []
        expect(plain.outcome(30, 20)).to eq Pf2e::Degree::CRITICAL_SUCCESS
      end

      it "should leave another statistic alone" do
        other = Pf2e::Check.of(Character[@char.id], 'skill', 'Athletics', [ 'item:trait:auditory' ])

        expect(other.adjustments).to eq []
      end

      # The roll has to carry it out to the degree of success, or the rule is read and does nothing.
      it "should come back from a roll, so the degree of success can use it" do
        parsed = Pf2e.parse_roll_string(Character[@char.id], [ '1d20', 'perception' ],
                                        [ 'item:trait:auditory' ])

        expect(parsed['adjustments']).to eq [ { 'all' => 'to-critical-failure' } ]
      end

      it "should make the roll read as a critical failure however well it went" do
        parsed = Pf2e.parse_roll_string(Character[@char.id], [ '0d1', '40', 'perception' ],
                                        [ 'item:trait:auditory' ])
        shown = Pf2e.get_degree(parsed['list'], parsed['result'], parsed['total'], 15,
                                parsed['adjustments'])

        expect(shown).to match(/CRITICAL FAILURE/)
      end

      it "should leave a roll it does not apply to as it was" do
        parsed = Pf2e.parse_roll_string(Character[@char.id], [ '0d1', '40', 'perception' ])
        shown = Pf2e.get_degree(parsed['list'], parsed['result'], parsed['total'], 15,
                                parsed['adjustments'])

        expect(shown).to match(/CRITICAL SUCCESS/)
      end
    end
  end
end
