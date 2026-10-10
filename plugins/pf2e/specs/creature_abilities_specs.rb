require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a creature's ability deals and the save against it, from its stat block's words.
    describe CreatureAbilities do
      it "should read a Constrict's listed damage and save" do
        expect(CreatureAbilities.damage_save('(2d10+17) bludgeoning, DC 40 Fortitude')).to eq(
          'formula' => '2d10+17', 'type' => 'bludgeoning', 'dc' => 40, 'save' => 'fortitude')
      end

      it "should read it where the save is called basic" do
        expect(CreatureAbilities.damage_save('(1d8) bludgeoning, DC 17 basic Fortitude%rThe monster deals the listed amount.')).to eq(
          'formula' => '1d8', 'type' => 'bludgeoning', 'dc' => 17, 'save' => 'fortitude')
      end

      it "should read a breath's damage and the save its sentence names" do
        text = 'The fire scamp breathes flames in a 15-foot cone that deals 2d4 fire damage to each creature ' \
               'within the area (DC 17 Reflex save).'

        expect(CreatureAbilities.damage_save(text)).to eq('formula' => '2d4', 'type' => 'fire', 'dc' => 17, 'save' => 'reflex')
      end

      it "should leave an ability that lists its outcomes to the GM" do
        text = 'Deals 4d6 cold damage (DC 25 Fortitude save).%rCritical Success unaffected%rCritical Failure frozen'

        expect(CreatureAbilities.damage_save(text)).to be_nil
      end

      it "should find nothing in words that deal no damage" do
        expect(CreatureAbilities.damage_save('The kraken moves through the water up to 280 feet.')).to be_nil
      end
    end
  end
end
