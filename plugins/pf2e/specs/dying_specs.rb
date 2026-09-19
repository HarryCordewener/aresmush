require "plugin_test_loader"

module AresMUSH

  # Taking a character to nothing, and picking them back up.
  #
  # Both paths read `char.pf2e_conditions`, which is not an attribute of anything - the reader is
  # `pf2_conditions`. So a DM's `damage` that drops someone to nothing raised NoMethodError and the
  # character was never put into Dying, and healing a character who was already at full damage raised
  # the same on the line that should have made them Wounded.
  describe Pf2eHP, :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Dying#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 12)
      @char.update(:hp => @hp, :pf2_conditions => {})
    end

    after(:each) do
      @hp.delete if @hp
      @char.delete if @char
    end

    def reread
      Character[@char.id]
    end

    it "should have a character with hit points to take away" do
      expect(Pf2eHP.get_max_hp(@char)).to be > 0
    end

    it "should not raise when damage takes a character to nothing" do
      expect { Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true) }.to_not raise_error
    end

    it "should put a character taken to nothing into Dying" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)

      expect(Pf2e.condition_level(reread, 'Dying')).to eq 1
    end

    # Dying goes up by one more for each point of Wounded already carried.
    it "should start Dying higher for a character who is already Wounded" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 1, 'status' => true } })

      Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
    end

    it "should not raise when healing a character who is at full damage" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)

      expect { Pf2eHP.modify_damage(reread, 5, true) }.to_not raise_error
    end

    it "should make a healed character Wounded and no longer Dying" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)
      Pf2eHP.modify_damage(reread, 5, true)

      expect(Pf2e.condition_level(reread, 'Wounded')).to eq 1
      expect(Pf2e.get_condition_value(reread, 'Dying')).to be_nil
    end

    it "should kill a character whose Dying reaches four" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 3, 'status' => true } })

      Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(reread.pf2_is_dead).to be true
    end

    # Doomed lowers the threshold a character dies at.
    it "should kill a Doomed character sooner" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 2, 'status' => true },
                                        'Doomed' => { 'value' => 1, 'status' => true } })

      Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(reread.pf2_is_dead).to be true
    end

    # A hit smaller than the temporary hit points is absorbed entirely - and the reduced pool has
    # to be written down, or the same temporary hit points soak every hit that comes.
    it "should record temporary hit points spent absorbing a hit" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 3, false, true)

      expect(Pf2eHP[@hp.id].temp_hp).to eq 2
    end

    it "should leave real hit points alone while temporary ones absorb the hit" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 3, false, true)

      expect(Pf2eHP[@hp.id].damage).to eq 0
    end

    it "should spend the temporary pool and carry the rest to real damage" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 8, false, true)

      expect(Pf2eHP[@hp.id].temp_hp).to eq 0
      expect(Pf2eHP[@hp.id].damage).to eq 3
    end

    it "should leave a character standing who is only hurt" do
      Pf2eHP.modify_damage(@char, 1, false, true)

      expect(reread.pf2_is_dead).to be_falsey
      expect(Pf2e.condition_level(reread, 'Dying')).to eq 0
    end
  end
end
