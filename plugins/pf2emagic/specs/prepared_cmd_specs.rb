require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # `prepared` tells someone who casts no spells so, and a caster with nothing prepared that instead.
    describe PF2DisplayPreparedCmd do

      def run(magic)
        client = double('client')
        enactor = double('enactor', :is_approved? => true, :magic => magic)
        allow(client).to receive(:emit_failure) { |message| @said = message }

        PF2DisplayPreparedCmd.new(client, Command.new('prepared'), enactor).handle
      end

      it "should tell someone with no magic that they cast no spells" do
        run(nil)

        expect(@said).to eq t('pf2emagic.not_caster')
      end

      it "should tell someone who casts nothing that they cast no spells" do
        allow(Entries).to receive(:innate?).and_return(false)
        run(double('magic', :tradition => { 'innate' => {} }, :spells_prepared => {}, :slot_pairs => {},
                            :mastered_spells => {}))

        expect(@said).to eq t('pf2emagic.not_caster')
      end

      it "should tell a caster with nothing prepared so" do
        run(double('magic', :tradition => { 'Wizard' => [ 'arcane' ] }, :spells_prepared => {}, :slot_pairs => {},
                            :mastered_spells => {}))

        expect(@said).to eq t('pf2emagic.no_prepared_spells')
      end
    end
  end
end
