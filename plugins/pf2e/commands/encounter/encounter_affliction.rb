module AresMUSH
  module Pf2e

    # `+e/affliction <who>=<affliction>/<stage>` - the GM puts someone's affliction at a stage, or ends it
    # with stage 0: a cure, an antidote, or a stage counted in days moving on.
    class PF2EncounterAfflictionCmd
      include CommandHandler

      attr_accessor :who, :name, :stage

      def parse_args
        who, _, rest = cmd.args.to_s.partition('=')
        name, _, stage = rest.rpartition('/')

        self.who = who.strip
        self.name = name.strip
        self.stage = stage.strip.match?(/\A\d+\z/) ? stage.strip.to_i : nil
      end

      def required_args
        [ self.who, self.name, self.stage ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        found = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, found)

        entry = Afflictions.on(found.state.holder).find { |one| one['name'].casecmp?(self.name) }

        return client.emit_failure(t('pf2e.affliction_none', :target => found.state.label, :name => self.name)) unless entry

        out = Acting.report
        Afflictions.stage(encounter, found.state, entry, self.stage, out)

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], Telling.lines(out['lines']).join('%r'), :room => enactor_room, :story => true)
      end
    end
  end
end
