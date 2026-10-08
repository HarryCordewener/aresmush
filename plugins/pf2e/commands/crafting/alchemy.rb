module AresMUSH
  module Pf2e

    # `alchemy` - what an alchemist will make at their next preparations, and what their reagents allow.
    class PF2AlchemyViewCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.who, enactor)

        return client.emit_failure(t('pf2e.not_found')) unless char
        return client.emit_failure(t('pf2e.alchemy_not_alchemist')) unless Alchemy.alchemist?(char)

        planned = Alchemy.plan(char).map { |name, many| t('pf2e.alchemy_line', :item => name, :many => many) }
        lines = [ t('pf2e.alchemy_title', :name => char.name, :batches => Alchemy.batches(char),
                                          :items => Alchemy.batches(char) * Alchemy.per_batch,
                                          :left => Alchemy.left(char)) ]

        client.emit (lines + (planned.empty? ? [ t('pf2e.alchemy_nothing_planned') ] : planned)).join('%r')
      end
    end

    # `alchemy/prepare <item>[/<how many>]` - says what to make of the day's reagents. `alchemy/clear
    # [<item>]` takes it back off the list. What is on the list is made at the next rest.
    class PF2AlchemyPrepareCmd
      include CommandHandler

      attr_accessor :name, :quantity

      def parse_args
        named, _, quantity = cmd.args.to_s.rpartition('/')
        named = cmd.args.to_s if named.strip.empty?

        self.name = named.strip
        self.quantity = quantity.to_i.positive? ? quantity.to_i : 1
      end

      def required_args
        [ self.name ]
      end

      def handle
        done = Alchemy.prepare!(enactor, self.name, self.quantity)

        return if CharState.emit_error!(client, done)

        client.emit_success t('pf2e.alchemy_planned', :list => done.state.map { |name, many| "#{many} #{name}" }.join(', '))
      end
    end

    class PF2AlchemyClearCmd
      include CommandHandler

      attr_accessor :name

      def parse_args
        self.name = trim_arg(cmd.args)
      end

      def handle
        Alchemy.clear!(enactor, self.name)

        client.emit_success t('pf2e.alchemy_cleared')
      end
    end

    # `+e/alchemy <item>` - Quick Alchemy: a batch of reagents for one item, to hand until your next turn.
    class PF2EncounterAlchemyCmd
      include CommandHandler

      attr_accessor :name

      def parse_args
        self.name = trim_arg(cmd.args)
      end

      def required_args
        [ self.name ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        standing = CombatantStates.of(encounter, enactor)

        return client.emit_failure(t('pf2e.encounter_gear_not_in')) unless standing

        made = Alchemy.quick!(standing, self.name)

        return if CharState.emit_error!(client, made)

        message = t('pf2e.alchemy_quick', :name => enactor.name, :item => made.state)

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end
  end
end
