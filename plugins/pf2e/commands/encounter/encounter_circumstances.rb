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
        Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor.room)
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
        Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor.room)
      end
    end

    # `+e/enter <aura>=<target>,<target>` and `+e/leave <aura>=<target>` - who is inside one of your auras,
    # as the map shows. Entering puts the aura's effects on them, following its own terms for whom it
    # affects; leaving ends them. Someone on your side is an ally and anyone else an enemy.
    class PF2EncounterAuraCmd
      include CommandHandler

      attr_accessor :aura, :targets, :actor

      # A creature's aura whose words call for a save - a dragon's presence, a ghoul's stench - has
      # whoever enters it roll that save. Answers what happened, or nothing where the aura is not one.
      def aura_save(encounter, emitter, target)
        own = Actors.of(emitter.holder).own_abilities.find { |one| Domains.slug(one['name']) == self.aura }

        return nil unless own && CreatureAbilities.saving(own['text'])

        out = Acting.report
        out['lines'] << Telling.event('pf2e.aura_entered_save', :target => target.label, :actor => emitter.label, :aura => own['name'])
        Acting.ability_saves(Acting::Scene.new(encounter, emitter, target, enactor, true), own['name'], own, [ target ], out)

        Telling.lines(out['lines']).join('%r')
      end

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
            relation = Actors.of(emitter.holder).side == Actors.of(target.holder).side ? 'ally' : 'enemy'
            done = Auras.enter(emitter.holder, target.holder, self.aura, relation)
            return if CharState.emit_error!(client, done)

            names = done.state.map(&:name)
            saved = names.empty? ? aura_save(encounter, emitter, target) : nil
            message = if saved then saved
                      elsif names.empty? then t('pf2e.aura_nothing', :target => target.label, :aura => self.aura)
                      else t('pf2e.aura_entered', :target => target.label, :aura => self.aura, :effects => names.join(', '))
                      end
          else
            done = Auras.leave(emitter.holder, target.holder, self.aura)
            message = t('pf2e.aura_left', :target => target.label, :aura => self.aura,
                                          :effects => done.state.empty? ? t('pf2e.nothing') : done.state.join(', '))
          end

          Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor_room, :story => true)
        end
      end
    end
  end
end
