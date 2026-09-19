module AresMUSH
  module Pf2e

    # `effect/add <who>=<effect>[/<option>...]` - put someone under an effect.
    #
    # The options after the name are what the one applying it knows and the catalogue cannot: `rank 6`
    # for the rank a spell was cast at, `value 3` for a counter, and a word answering what the effect
    # asks - `fire` for which energy Resist Energy resists.
    class PF2EffectAddCmd
      include CommandHandler

      attr_accessor :targets, :effect, :options

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.targets = trimmed_list_arg(args.arg1)
        parts = args.arg2.to_s.split('/').map(&:strip)
        self.effect = parts.shift
        self.options = parts
      end

      def required_args
        [ self.targets, self.effect ]
      end

      def check_effect_exists
        found = ActiveEffects.find(self.effect)

        return t(found.key, **CharState.symbolize(found.args)) if found.err?

        @name = found.state

        nil
      end

      def handle
        encounter = enactor_room.scene ? PF2Encounter.scene_active_encounter(enactor_room.scene) : nil
        chars = ActiveEffects.targets(client, enactor, self.targets)

        return if chars.empty?

        unless Pf2e.can_damage_pc?(enactor, chars.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        chars.each do |char|
          ActiveEffects.apply(char, @name, :options => self.options, :applied_by => enactor.name,
                                           :encounter => encounter)
        end

        client.emit_success t('pf2e.effect_added', :effect => @name,
                                                   :targets => chars.map(&:name).sort.join(', '))
      end
    end
  end
end
