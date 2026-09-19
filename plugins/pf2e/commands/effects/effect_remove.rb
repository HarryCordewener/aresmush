module AresMUSH
  module Pf2e

    # `effect/remove <who>=<effect>` - end an effect early. Whatever it brought with it goes too, unless
    # the effect said it stays.
    class PF2EffectRemoveCmd
      include CommandHandler

      attr_accessor :targets, :effect

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.targets = trimmed_list_arg(args.arg1)
        self.effect = trim_arg(args.arg2)
      end

      def required_args
        [ self.targets, self.effect ]
      end

      def handle
        encounter = enactor_room.scene ? PF2Encounter.scene_active_encounter(enactor_room.scene) : nil
        chars = ActiveEffects.targets(client, enactor, self.targets)

        return if chars.empty?

        unless Pf2e.can_damage_pc?(enactor, chars.map(&:name), encounter&.id)
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        done = chars.reject { |char| CharState.emit_error!(client, ActiveEffects.remove_named(char, self.effect)) }

        return if done.empty?

        client.emit_success t('pf2e.effect_removed', :effect => self.effect,
                                                     :targets => done.map(&:name).sort.join(', '))
      end
    end
  end
end
