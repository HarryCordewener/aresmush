require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a player is told is counted in words that agree with the count: one round, three rounds.
    describe "counted words" do
      {
        'pf2e.effect_lasts_rounds' => [ {}, '1 round left', '3 rounds left' ],
        'pf2e.effect_lasts_rests' => [ {}, 'for one more night', 'for 3 more nights' ],
        'pf2e.act_healed' => [ { :target => 'Aria' }, '  Aria recovers 1 Hit Point.', '  Aria recovers 3 Hit Points.' ],
        'pf2e.consumable_heals' => [ { :target => 'Aria', :item => 'potion' }, '  Aria regains 1 Hit Point from the potion.',
                                     '  Aria regains 3 Hit Points from the potion.' ],
        'pf2e.fast_healing' => [ { :name => 'Aria', :source => 'Troll Blood' }, 'Aria regains 1 hit point from Troll Blood.',
                                 'Aria regains 3 hit points from Troll Blood.' ]
      }.each_pair do |key, (args, one, three)|
        it "should say #{key} in the singular and the plural" do
          expect(t(key, **args.merge(:count => 1))).to eq one
          expect(t(key, **args.merge(:count => 3))).to eq three
        end
      end
    end
  end
end
