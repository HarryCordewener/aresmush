module AresMUSH
  module Pf2emagic
    # prepare/<switch> for a feat that changes what a slot holds, the switch its data names:
    #
    #   prepare/splitslot <rank> = <spell>, <spell>          two spells, cast one
    #   prepare/spellcombination <rank> = <spell> + <spell>  two spells, cast together
    #   prepare/spellmastery [<rank> =] <spell>              a spell prepared at every rest
    #
    # Either separator works for either pair, since no spell's name holds one.
    class PF2PrepareSlotFeatCmd
      include CommandHandler

      attr_accessor :rank, :spells

      def parse_args
        if cmd.args.to_s.include?("=")
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)

          self.rank = trim_arg(args.arg1)
          self.spells = split_spells(args.arg2)
        else
          self.spells = split_spells(cmd.args)
        end
      end

      def split_spells(text)
        text.to_s.split(/\s*[,+]\s*/).map { |name| titlecase_arg(name) }.reject(&:blank?)
      end

      def required_args
        [ self.spells.presence ]
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        found = SlotFeats.for_switch(enactor, cmd.switch)

        unless found && enactor.magic
          client.emit_failure t('pf2emagic.slot_feat_not_held', :switch => cmd.switch)
          return
        end

        if found['kind'] == 'mastered_spells'
          master(found)
        else
          pair(found)
        end
      end

      def pair(found)
        outcome = SlotFeats.prepare_pair(enactor, found, self.rank, self.spells)

        return if Pf2e::CharState.emit_error!(client, outcome)

        made = outcome.state
        key = made['cast'] == 'both' ? 'slot_pair_combined_ok' : 'slot_pair_either_ok'

        client.emit_success t("pf2emagic.#{key}", :first => made['spells'][0], :second => made['spells'][1],
                              :rank => made['rank'], :cast_rank => made['cast_rank'], :feat => made['feat'])
      end

      def master(found)
        outcome = SlotFeats.master_spell(enactor, found, self.rank, self.spells.first)

        return if Pf2e::CharState.emit_error!(client, outcome)

        made = outcome.state
        key = made['replaced'] ? 'mastery_replaced_ok' : 'mastery_ok'

        client.emit_success t("pf2emagic.#{key}", :spell => made['spell'], :rank => made['rank'], :replaced => made['replaced'])
      end
    end

    # unprepare/<switch>: unprepare/splitslot [<rank>], unprepare/spellmastery <spell>.
    class PF2UnprepareSlotFeatCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = titlecase_arg(cmd.args)
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        found = SlotFeats.for_switch(enactor, cmd.switch)

        unless found && enactor.magic
          client.emit_failure t('pf2emagic.slot_feat_not_held', :switch => cmd.switch)
          return
        end

        if found['kind'] == 'mastered_spells'
          outcome = SlotFeats.forget_mastered(enactor, found, self.target)
          return if Pf2e::CharState.emit_error!(client, outcome)

          client.emit_success t('pf2emagic.mastery_removed_ok', :spell => outcome.state['spell'])
        else
          outcome = SlotFeats.unprepare_pair(enactor, found, self.target)
          return if Pf2e::CharState.emit_error!(client, outcome)

          removed = outcome.state
          client.emit_success t('pf2emagic.slot_pair_removed_ok', :first => removed['spells'][0],
                                :second => removed['spells'][1], :rank => removed['rank'])
        end
      end
    end
  end
end
