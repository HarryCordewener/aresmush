require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The data behind choosing another subclass: the bloodlines' gift spells and blood magic, the
    # orders' and muses' 1st-level feats, and the feats that choose one.
    describe "subclass data" do

      before(:all) do
        @specialty = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']
        @options = YAML.load_file("game/config/pf2e_specialty_options.yml")['pf2e_subclass']

        @feats = {}
        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @spells = {}
        Dir.glob("game/config/pf2e_spells_*.yml").each { |file| @spells.merge!(YAML.load_file(file)['pf2e_spells']) }
      end

      def bloodline(name)
        @specialty['Sorcerer'].fetch(name)
      end

      # Every block a bloodline's levels give, with the level it arrives at: chargen is level 1.
      def level_blocks(info)
        [ [ 1, info['chargen'] ] ] + (info['advance'] || {}).map { |level, block| [ level.to_i, block ] }
      end

      describe "sorcerous gifts that follow a bloodline's 1st-level choice" do
        it "should name a table covering every option of the choice" do
          %w(Draconic Elemental).each do |name|
            info = bloodline(name)
            table = @options.fetch(info['choice_spells'])

            expect(table.keys.sort).to eq(info['choose']['options'].keys.sort), name
          end
        end

        it "should name only spells the game has" do
          %w(Draconic Elemental).each do |name|
            @options[bloodline(name)['choice_spells']].each_pair do |option, ranks|
              ranks.each_value { |spell| expect(@spells).to have_key(spell), "#{name} #{option}: #{spell}" }
            end
          end
        end

        # A sorcerer gains a spell rank's gift at the level they gain the rank: 2 x rank - 1.
        it "should grant each rank the table holds at the level that rank arrives" do
          %w(Draconic Elemental).each do |name|
            info = bloodline(name)
            ranks = @options[info['choice_spells']].values.first.keys.map(&:to_s)

            granted = level_blocks(info).flat_map do |level, block|
              Array(((block || {})['magic_stats'] || {})['choice_repertoire']).map { |rank| [ rank.to_s, level ] }
            end

            expected = ranks.map { |rank| [ rank == '0' ? 'cantrip' : rank, [ 1, 2 * rank.to_i - 1 ].max ] }

            expect(granted.sort).to eq(expected.sort), name
          end
        end

        # The Legacy fire spells were granted to every elemental sorcerer whatever their influence.
        it "should grant an elemental sorcerer nothing at the ranks the influence decides" do
          stats = bloodline('Elemental')['chargen']['magic_stats']

          expect(stats['addrepertoire'] || {}).to_not include('cantrip', '1')
        end
      end

      describe "blood magic" do
        it "should name and describe each bloodline's" do
          @specialty['Sorcerer'].each_pair do |name, info|
            magic = info['blood_magic']

            expect(magic).to be_a(Hash), name
            expect(magic['name']).to be_present, name
            expect(magic['text']).to be_present, name
          end
        end

        it "should give Elemental Fury's damage type for each elemental influence" do
          magic = bloodline('Elemental')['blood_magic']

          expect(magic['damage_by_choice']).to eq(
            'Air' => 'slashing', 'Earth' => 'bludgeoning', 'Fire' => 'fire',
            'Metal' => 'piercing', 'Water' => 'bludgeoning', 'Wood' => 'bludgeoning'
          )
        end
      end

      # Order Explorer and Multifarious Muse grant "a 1st-level feat that lists that order (muse) as
      # a prerequisite". The grant looks it up, so each has to have exactly one.
      it "should give each order and muse one 1st-level feat that requires it" do
        { 'Druid' => %w(Animal Leaf Storm Untamed), 'Bard' => %w(Enigma Maestro Polymath Warrior) }.each_pair do |charclass, specialties|
          specialties.each do |specialty|
            found = @feats.select do |_name, details|
              prereq = details['prereq'] || {}

              prereq['level'] == 1 && Array(details['assoc_charclass']).include?(charclass) &&
                Array(prereq['specialize']).any? { |s| s.to_s.casecmp?(specialty) }
            end

            expect(found.size).to eq(1), "#{specialty}: #{found.keys.inspect}"
          end
        end
      end

      it "should give each order an initial order spell" do
        @specialty['Druid'].each_pair do |order, info|
          spells = Array(info.dig('chargen', 'magic_stats', 'focus_spell', 'order'))

          expect(spells.size).to eq(1), order
        end
      end

      describe "the feats that choose another subclass" do
        def choice(name)
          @feats.fetch(name)['feat_choice']
        end

        it "should let Order Explorer and Multifarious Muse join another specialty and gain its feat" do
          %w(Order\ Explorer Multifarious\ Muse).each do |name|
            expect(@feats[name]['repeatable']).to be(true), name
            expect(choice(name)).to include('from' => 'other_specialties', 'joins_specialty' => true,
                                            'grants_specialty_feat' => true)
          end
        end

        it "should let Order Magic choose an order explored and gain its spell" do
          expect(@feats['Order Magic']['repeatable']).to be true
          expect(choice('Order Magic')).to include('from' => 'chosen_specialties', 'from_choice' => 'Order Explorer',
                                                   'grants_specialty_focus' => true)
        end

        # Crossblooded Evolution gives no membership: it is not a prerequisite for any feat.
        it "should let Crossblooded Evolution choose another bloodline and its own choice" do
          block = choice('Crossblooded Evolution')

          expect(block).to include('from' => 'other_specialties', 'shares_blood_magic' => true)
          expect(block).to_not have_key('joins_specialty')
          expect(block['then_choose']).to include('from' => 'specialty_options', 'skip_if_empty' => true)
        end

        it "should let Greater Crossblooded Evolution choose three gift spells known at the highest rank" do
          block = choice('Greater Crossblooded Evolution')
          steps = [ block, block['then_choose'], block['then_choose']['then_choose'] ]

          steps.each do |step|
            expect(step).to include('from' => 'secondary_gift_spells', 'from_choice' => 'Crossblooded Evolution',
                                    'known_at' => 'highest_rank')
          end

          expect(steps.last).to_not have_key('then_choose')
        end
      end
    end
  end
end
