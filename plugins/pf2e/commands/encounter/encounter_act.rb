module AresMUSH
  module Pf2e

    # What the `+e/act`, `+e/strike` and `+e/cast` commands share: who is acting and at whom, and telling
    # the room, the encounter's log and the scene what happened.
    #
    # Each takes the same shape of arguments - the thing done, `=` who it is done to, then `/` and the
    # circumstances - so a player learns one grammar:
    #
    #   +e/act trip=#3/flanking
    #   +e/strike #3=longsword/range 2
    #   +e/cast fear=#3,#4
    #
    # and a GM acting for a creature puts the creature first, the way `roll/for` does: `+e/as #3=strike
    # aria`.
    module ActsInEncounter

      # `trip=#3/flanking/range 2` as `[ 'trip', '#3', [ 'flanking', 'range 2' ] ]`.
      def self.split(args)
        parts = args.to_s.split('/').map(&:strip)
        head, _, tail = parts.shift.to_s.partition('=')

        [ head.strip, tail.strip, parts.reject(&:empty?) ]
      end

      # The one acting: the combatant the enactor plays, as they stand in the encounter. Nothing is done
      # outside one.
      def acting_as(encounter, actor = nil)
        return able(actor) if actor
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless encounter

        found = Combatants.find(encounter, enactor.name)

        return Err.new(:not_in_encounter, 'pf2e.act_join_first', 'id' => encounter.id) unless found.ok?

        able(found.state)
      end

      # A creature with no hit points left, or a character knocked out, does nothing - but for answering
      # the hit that knocked them out, which the rules have happen before it lands.
      def able(combatant)
        holder = combatant.holder
        down = Actors.of(holder).creature? ? holder.hp_left.to_i <= 0 : Pf2e.held_conditions(holder).key?('Unconscious')

        return Ok.new(:state => combatant) unless down && !Acting.answering?(holder)

        Err.new(:cannot_act, 'pf2e.act_cannot_act', 'actor' => combatant.label)
      end

      def scene_for(encounter, actor, target)
        Acting::Scene.new(encounter, actor, target, enactor, Combatants.trusted?(enactor, encounter))
      end

      # Tells the room and records it in the encounter and the scene. What only the GM sees goes to them.
      def tell(encounter, out)
        message = Telling.lines(out['lines']).join('%r')

        enactor_room.emit message

        if encounter
          PF2Encounter.send_to_encounter(encounter, message)
          Scenes.add_to_scene(encounter.scene, message, Game.master.system_character, false, true) if encounter.scene
        end

        tell_gm(encounter, out['gm'])

        enactor.update(:pf2_last_roll => out['detail'])
      end

      def tell_gm(encounter, lines)
        return if lines.empty?

        message = Telling.lines(lines).join('%r')
        gm = encounter && PF2Encounter.gm_of(encounter)

        if gm && gm != enactor
          Login.emit_ooc_if_logged_in(gm, message)
        elsif gm == enactor || !encounter
          client.emit_ooc message
        end
      end
    end

    # `+e/act <action>[=<target>,<target>...][/<circumstance>...]`
    class PF2EncounterActCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :action, :target, :words, :actor

      def parse_args
        self.action, self.target, self.words = ActsInEncounter.split(cmd.args)
      end

      def required_args
        [ self.action ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        named = self.target.to_s.split(',').map(&:strip).reject(&:empty?)
        targets, missing = Combatants.resolve_all(enactor, named, encounter)

        unless missing.empty?
          found = Combatants.resolve(enactor, missing.first, encounter)
          return if CharState.emit_error!(client, found)
        end

        done = Acting.act(scene_for(encounter, actor.state, targets.first), self.action, self.words,
                          :targets => targets)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state)
      end
    end

    # `+e/strike <target>[=<weapon>][/<circumstance>...]`
    class PF2EncounterStrikeCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :target, :weapon, :words, :actor

      def parse_args
        self.target, self.weapon, self.words = ActsInEncounter.split(cmd.args)
      end

      def required_args
        [ self.target ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        found = Combatants.resolve(enactor, self.target, encounter)

        return if CharState.emit_error!(client, found)

        done = Acting.strike(scene_for(encounter, actor.state, found.state), self.weapon, self.words)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state)
      end
    end

    # `+e/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>][/<circumstance>...]`
    #
    # A character's spell is cast through their magic first, which spends the slot, the focus point or the
    # use - and refuses where they have none - exactly as `cast` does. A creature's is cast from its stat
    # block's spellcasting.
    class PF2EncounterCastCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :spell, :targets, :words, :actor

      # A switch `cast` takes that says which kind of casting spends the spell.
      KINDS = %w{focus focusc innate signature}.freeze

      def parse_args
        self.spell, targets, self.words = ActsInEncounter.split(cmd.args)
        self.targets = targets.split(',').map(&:strip).reject(&:empty?)
      end

      def required_args
        [ self.spell ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        found, missing = Combatants.resolve_all(enactor, self.targets, encounter)

        unless missing.empty?
          client.emit_failure t('pf2e.no_combatant', :target => missing.join(', '))
          return
        end

        # Asked before the spell is spent, so a caster who has to choose loses nothing by not having.
        return if CharState.emit_error!(client, Acting.way_needed(self.spell, self.words))

        cast = Actors.of(actor.state.holder).spends_spells? ? spend_the_spell(actor.state.holder) : nil

        if cast.is_a?(String)
          client.emit_failure cast
          return
        end

        spell = cast.is_a?(Hash) ? cast['spell name'] : self.spell
        done = Acting.cast(scene_for(encounter, actor.state, nil), spell, found, self.words, :cast => cast)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state)
      end

      # The caster's magic spends the spell and answers with what it was cast at, or says why it could not.
      def spend_the_spell(char)
        said = Acting.said(self.words, false)
        charclass = said['class'] ? said['class'].split.map(&:capitalize).join(' ') : casting_class(char)
        kind = self.words.map(&:downcase).find { |word| KINDS.include?(word) }
        level = said['rank'] ? said['rank'].to_s : nil

        return t('pf2emagic.not_caster') unless charclass || kind == 'innate'

        Pf2emagic.cast_spell(char, charclass || 'Innate', self.spell, [], level, kind)
      end

      # Which of their casting classes casts it, where they did not say: the one that knows the spell, and
      # otherwise the only one they have. A spellcasting entry is named by `name`.
      def casting_class(char)
        return nil unless char.magic

        entries = Pf2emagic::Entries.casting(char.magic)
        knows = entries.find { |entry| knows_spell?(char.magic, entry['name']) }

        (knows || entries.first)&.dig('name')
      end

      def knows_spell?(magic, source)
        Pf2emagic::Entries.known(magic, source).values.flatten.any? { |spell| spell.to_s.casecmp?(self.spell.to_s) }
      end
    end

    # `+e/as <combatant>=<act|strike|cast> <what>` - a GM acting for a creature, or for anyone in the
    # encounter.
    class PF2EncounterAsCmd
      include CommandHandler

      attr_accessor :who, :verb, :rest

      # Asked for rather than held in a constant, because the aura command is defined in a file loaded
      # after this one.
      def self.verbs
        { 'act' => PF2EncounterActCmd, 'strike' => PF2EncounterStrikeCmd, 'cast' => PF2EncounterCastCmd,
          'enter' => PF2EncounterAuraCmd, 'leave' => PF2EncounterAuraCmd }
      end

      def parse_args
        self.who, _, command = cmd.args.to_s.partition('=')
        self.verb, _, self.rest = command.strip.partition(' ')
        self.who = self.who.strip
        self.verb = self.verb.downcase
      end

      def required_args
        [ self.who, self.verb ]
      end

      def check_verb
        return nil if self.class.verbs.key?(self.verb)

        t('pf2e.bad_option', :element => 'command', :options => self.class.verbs.keys.join(', '))
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        actor = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, actor)

        handler = self.class.verbs[self.verb].new(client, Command.new("e/#{self.verb} #{self.rest}"), enactor)
        handler.parse_args
        handler.actor = actor.state

        missing = handler.required_args.any? { |one| one.to_s.empty? }

        return client.emit_failure(t('dispatcher.invalid_syntax', :cmd => "e/#{self.verb}")) if missing

        handler.handle
      end
    end

    # `+e/why` - every modifier of the last roll you made or made for someone.
    class PF2EncounterWhyCmd
      include CommandHandler

      def handle
        events = Array(enactor.pf2_last_roll)

        return client.emit_ooc(t('pf2e.why_nothing')) if events.empty?

        client.emit Telling.lines(events).join('%r')
      end
    end

    # `+e/turn [<combatant>]` - what you, or a combatant, have done this turn.
    class PF2EncounterTurnCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        found = Combatants.find(encounter, self.who || enactor.name)

        return if CharState.emit_error!(client, found)

        client.emit_ooc t('pf2e.turn_of', :name => found.state.label, :summary => TurnState.summary(found.state.holder))
      end
    end
  end
end
