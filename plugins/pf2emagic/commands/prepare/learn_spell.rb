module AresMUSH
  module Pf2emagic
    # spell/learn [<place>/]<spell>: Learn a Spell into a spellbook or a book a feat keeps.
    class PF2LearnSpellCmd
      include CommandHandler

      attr_accessor :target, :spell_name

      def parse_args
        parts = trimmed_list_arg(cmd.args, "/") || []

        if parts.size > 1
          self.target = parts[0]
          self.spell_name = parts[1..].join("/")
        else
          self.spell_name = parts[0]
        end
      end

      def required_args
        [ self.spell_name ]
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        natural = Pf2e.roll_dice(1, 20).first
        outcome = Pf2emagic.learn_spell(enactor, self.target, self.spell_name, natural)

        return if Pf2e::CharState.emit_error!(client, outcome)

        result = outcome.state
        cost = Pf2egear.display_money(result['cost'])

        client.emit_ooc t('pf2emagic.learn_result', :spell => result['spell'], :skill => result['skill'],
                          :natural => result['natural'], :bonus => result['bonus'], :total => result['total'],
                          :dc => result['dc'], :degree => Pf2e::DEGREE_LABELS[result['degree']])

        if result['learned']
          client.emit_success t('pf2emagic.learn_learned', :spell => result['spell'], :target => result['target'], :cost => cost)
        else
          shorthand = Pf2emagic.learn_spell_rules(enactor)[:retry_after_days] ? t('pf2emagic.learn_failed_shorthand') : ''

          client.emit_failure t('pf2emagic.learn_failed', :spell => result['spell'], :cost => cost, :shorthand => shorthand)
        end
      end
    end
  end
end
