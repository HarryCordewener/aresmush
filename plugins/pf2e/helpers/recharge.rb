module AresMUSH
  module Pf2e

    # An ability a creature cannot use again for a while: a breath it "can't use again for 1d4 rounds".
    # The rounds are rolled as it is used and the GM alone is told when it is back; using it before then
    # is the GM's to allow, and they are told that too.
    module Recharge

      KEY = 'recharge'.freeze

      # `can't use Flame Breath again for 1d4 rounds`
      def self.rounds_of(name, own)
        found = own['text'].to_s.match(/can['’]t use #{Regexp.escape(name)} again for (\d*d\d+|\d+) rounds?/i)

        found ? found[1] : nil
      end

      def self.ready(holder)
        TurnState.of(holder)[KEY] || {}
      end

      # The ability has been used: a warning where it was not back, and the round it will be.
      def self.used(scene, name, own, out)
        rounds = rounds_of(name, own)

        return unless rounds && scene.encounter

        holder = scene.actor.holder
        now = scene.encounter.round.to_i
        back = ready(holder)[name].to_i

        out['gm'] << Telling.event('pf2e.recharge_not_back', :actor => scene.actor.label, :action => name, :round => back) if back > now

        rolled = Pf2e.roll_formula(rounds)
        TurnState.write(holder, KEY => ready(holder).merge(name => now + rolled + 1))
        out['gm'] << Telling.event('pf2e.recharge_set', :actor => scene.actor.label, :action => name, :rounds => rolled,
                                                       :round => now + rolled + 1)
      end

      # A critical hit brings back what the creature's own words say it does: Draconic Momentum.
      MOMENTUM = /recharges? (?:their|its|his|her) (.+?) whenever (?:they|it|he|she) scores? a critical hit/i

      def self.critical_hit(scene, out)
        holder = scene.actor.holder

        return unless Actors.of(holder).creature?

        Array(holder.stat_block['actions']).filter_map { |one| one['text'].to_s[MOMENTUM, 1] }.each do |named|
          waiting = ready(holder).keys.find { |name| name.casecmp?(named) }

          next unless waiting

          TurnState.write(holder, KEY => ready(holder).except(waiting))
          out['gm'] << Telling.event('pf2e.recharge_back', :actor => scene.actor.label, :action => waiting)
        end
      end
    end
  end
end
