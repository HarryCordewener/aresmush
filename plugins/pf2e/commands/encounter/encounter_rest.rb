module AresMUSH
  module Pf2e

    # `+e/rest [<combatant>,<combatant>...]` - the GM says a night has passed for everyone in the encounter
    # here, or for those named: each gets a night's rest and the day's preparations (`Pf2e.rest`). As often
    # as the story needs; a mistaken one is taken back with `+e/undo`.
    class PF2EncounterRestCmd
      include CommandHandler

      attr_accessor :names

      def parse_args
        self.names = cmd.args.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        resting = resting(encounter)

        return if resting.nil?
        return client.emit_failure(t('pf2e.rest_nobody')) if resting.empty?

        resting.each { |one| Pf2e.rest(one.holder) }

        message = t('pf2e.rest_done', :name => enactor.name, :who => resting.map(&:label).join(', '))

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end

      # The characters named, or every character in the encounter. A creature does not prepare.
      def resting(encounter)
        return Combatants.all(encounter).reject(&:creature?).select(&:holder) if self.names.empty?

        found = self.names.map { |name| Combatants.find(encounter, name) }
        failed = found.find(&:err?)

        return nil if failed && CharState.emit_error!(client, failed)

        creature = found.map(&:state).find(&:creature?)

        if creature
          client.emit_failure t('pf2e.rest_creature', :ref => creature.ref)
          return nil
        end

        found.map(&:state)
      end
    end

    # `+e/refocus [<combatant>]` - Refocus: a Focus Point back, or more for those whose feats say so. The GM
    # may refocus anyone; a player refocuses themselves.
    class PF2EncounterRefocusCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        gm = Combatants.gm?(enactor, encounter)

        return client.emit_failure(t('pf2e.not_organizer')) if self.who && !gm

        found = Combatants.find(encounter, self.who || enactor.name)

        return if CharState.emit_error!(client, found)

        holder = found.state.holder
        before = holder.magic ? holder.magic.focus_pool['current'].to_i : 0
        refused = Pf2emagic.do_refocus(holder, gm)

        return client.emit_failure(refused) if refused

        after = Combatants.find(encounter, found.state.ref).state.holder.magic.focus_pool['current'].to_i
        restored = after - before

        client.emit_success t(restored == 1 ? 'pf2emagic.refocus_ok_one' : 'pf2emagic.refocus_ok_many', :points => restored)
      end
    end
  end
end
