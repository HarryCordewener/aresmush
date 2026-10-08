require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A rule that names a choice nobody has made reaches nothing. Assurance's adjustment names the skill
    # chosen for it, so a character who holds the feat before choosing has a rule with nothing to select.
    describe "a rule whose choice is unmade" do

      def assurance
        {
          'rules' => [
            { 'key' => 'AdjustModifier', 'selector' => '{item|flags.system.rulesSelections.assurance}',
              'suppress' => true, 'predicate' => [ 'substitute:assurance' ] },
            { 'key' => 'DamageAlteration', 'selectors' => [ '{item|flags.system.rulesSelections.assurance}' ],
              'mode' => 'override', 'property' => 'damage-type', 'value' => 'fire' },
            { 'key' => 'Note', 'selector' => '{item|flags.system.rulesSelections.assurance}', 'text' => 'noted' }
          ]
        }
      end

      it "should adjust no modifier" do
        expect(Rules.modifier_adjustments([ assurance ], [ 'athletics', 'skill-check' ], [])).to eq []
      end

      it "should alter no damage" do
        expect(Rules.damage_alterations([ assurance ], [ 'strike-damage' ], [])).to eq []
      end

      it "should add no note" do
        expect(Rules.notes([ assurance ], [ 'athletics' ], [])).to eq []
      end
    end
  end
end
