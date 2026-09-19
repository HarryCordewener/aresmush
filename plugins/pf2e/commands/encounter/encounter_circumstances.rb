module AresMUSH
  module Pf2e

    # What the other app's map shows and this game cannot see, said on its behalf: a target's cover and
    # concealment, set by the GM or a player the GM has trusted with it for this encounter. Every attack
    # and check against the target reads it until someone changes it.
    module SetsCircumstance

      def self.set(client, enactor, field, levels, target, level)
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_trusted')) unless Combatants.trusted?(enactor, encounter)

        wanted = level.to_s.strip.downcase
        wanted = 'standard' if field == :cover && wanted == 'cover'

        unless wanted == 'none' || levels.key?(wanted)
          return client.emit_failure(t('pf2e.bad_option', :element => field.to_s,
                                                          :options => ([ 'none' ] + levels.keys).join(', ')))
        end

        found = Combatants.find(encounter, target)

        return if CharState.emit_error!(client, found)

        held = (encounter.send(field) || {}).dup
        key = found.state.number.to_s
        wanted == 'none' ? held.delete(key) : held[key] = wanted

        encounter.update(field => held)

        message = t("pf2e.#{field}_set", :target => found.state.label, :level => wanted, :name => enactor.name)
        enactor.room.emit message
        PF2Encounter.send_to_encounter(encounter, message)
      end
    end

    # `+e/cover <target>=<none|lesser|standard|greater>`
    class PF2EncounterCoverCmd
      include CommandHandler

      attr_accessor :target, :level

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.target = trim_arg(args.arg1)
        self.level = trim_arg(args.arg2)
      end

      def required_args
        [ self.target, self.level ]
      end

      def handle
        SetsCircumstance.set(client, enactor, :cover, Resolve::COVER, self.target, self.level)
      end
    end

    # `+e/conceal <target>=<none|concealed|hidden|undetected>`
    class PF2EncounterConcealCmd
      include CommandHandler

      attr_accessor :target, :level

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.target = trim_arg(args.arg1)
        self.level = trim_arg(args.arg2)
      end

      def required_args
        [ self.target, self.level ]
      end

      def handle
        SetsCircumstance.set(client, enactor, :concealment, Resolve::CONCEALMENT, self.target, self.level)
      end
    end

    # `+e/trust <name>` and `+e/untrust <name>`: who besides the GM may set cover and concealment in this
    # encounter. Trust ends with the encounter.
    class PF2EncounterTrustCmd
      include CommandHandler

      attr_accessor :name

      def parse_args
        self.name = titlecase_arg(cmd.args)
      end

      def required_args
        [ self.name ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        char = Character.named(self.name)

        return client.emit_failure(t('pf2e.no_combatant', :target => self.name)) unless char

        trusting = cmd.switch_is?('trust')
        list = Array(encounter.trusted) - [ char.name ]
        list << char.name if trusting

        encounter.update(:trusted => list)

        message = t(trusting ? 'pf2e.trusted' : 'pf2e.untrusted', :name => char.name, :gm => enactor.name)
        enactor.room.emit message
        PF2Encounter.send_to_encounter(encounter, message)
      end
    end

    # `+e/enter <aura>=<target>,<target>` and `+e/leave <aura>=<target>` - who is inside one of your auras,
    # as the map shows. Entering puts the aura's effects on them, following its own terms for whom it
    # affects; leaving ends them. Someone on your side is an ally and anyone else an enemy.
    class PF2EncounterAuraCmd
      include CommandHandler

      attr_accessor :aura, :targets, :actor

      def parse_args
        aura, _, targets = cmd.args.to_s.partition('=')
        self.aura = Domains.slug(aura)
        self.targets = targets.split(',').map(&:strip).reject(&:empty?)
      end

      def required_args
        [ self.aura, self.targets.first ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        emitter = self.actor || Combatants.find(encounter, enactor.name).state

        return client.emit_failure(t('pf2e.act_join_first', :id => encounter.id)) unless emitter

        found, missing = Combatants.resolve_all(enactor, self.targets, encounter)

        return client.emit_failure(t('pf2e.no_combatant', :target => missing.join(', '))) unless missing.empty?

        entering = cmd.switch_is?('enter')

        found.each do |target|
          if entering
            relation = emitter.npc? == target.npc? ? 'ally' : 'enemy'
            done = Auras.enter(emitter.holder, target.holder, self.aura, relation)
            return if CharState.emit_error!(client, done)

            names = done.state.map(&:name)
            message = names.empty? ? t('pf2e.aura_nothing', :target => target.label, :aura => self.aura) :
                        t('pf2e.aura_entered', :target => target.label, :aura => self.aura, :effects => names.join(', '))
          else
            done = Auras.leave(emitter.holder, target.holder, self.aura)
            message = t('pf2e.aura_left', :target => target.label, :aura => self.aura,
                                          :effects => done.state.empty? ? t('pf2e.nothing') : done.state.join(', '))
          end

          enactor_room.emit message
          PF2Encounter.send_to_encounter(encounter, message)
        end
      end
    end
  end
end
