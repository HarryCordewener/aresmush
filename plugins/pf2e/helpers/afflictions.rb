module AresMUSH
  module Pf2e

    # A venom, a disease or a curse, as a stat block gives one:
    #
    #   Saving Throw DC 19 Fortitude
    #   Maximum Duration 6 rounds
    #   Stage 1 no effect (1 round)
    #   Stage 2 Clumsy 2 (1 round)
    #   Stage 3 Paralyzed (1 round)
    #
    # Whoever is exposed saves at once: a failure puts them at stage 1, a critical failure at stage 2. As
    # each stage's time is up they save again at the end of their turn - down one stage for a success and
    # two for a critical success, up one for a failure and two for a critical failure, never past the
    # last - and it ends below stage 1 or when it has lasted as long as it can. A stage's conditions are
    # theirs while they are at it, and its damage is dealt each time they reach it.
    #
    # What someone is afflicted with is kept with their turn: `{ 'name', 'by', 'stage', 'next', 'until',
    # ... }`, where `next` is the round their next save falls due and `until` the round it ends.
    #
    # A stage counted in hours or days is reached and told, and its next save is the GM's to call.
    module Afflictions

      KEY = 'afflictions'.freeze

      HEAD = /Saving Throw DC (?<dc>\d+)\s*(?:basic\s+)?(?<save>Fortitude|Reflex|Will)/i
      STAGE = /\AStage (\d+)\s+(.*?)(?:\s*\(([^()]*)\))?\z/

      # The patterns for what a stage names, built when asked for because `CreatureAbilities` loads later.
      def self.names
        CreatureAbilities::VALUED + CreatureAbilities::PLAIN
      end

      def self.named
        @named ||= /\b(?:(#{CreatureAbilities::VALUED.join('|')}) (\d+)|(#{CreatureAbilities::PLAIN.join('|')}))\b/i
      end

      def self.dealt
        @dealt ||= /(#{CreatureAbilities::FORMULA}) ([a-z]+) damage/
      end

      # ------------------------------------------------------------------------------
      # Reading one

      def self.read(name, text, traits = [])
        lines = text.to_s.split('%r').map(&:strip)
        head = lines.filter_map { |line| line.match(HEAD) }.first

        return nil unless head && lines.any? { |line| line.match?(/\AStage 1\b/) }

        slugs = Array(traits).map { |trait| Domains.slug(trait) }
        stages = lines.filter_map { |line| line.match(STAGE) }.each_with_object([]) do |found, held|
          words = found[2].strip
          earlier = (like = words.match(/\Aas stage (\d+)\z/i)) ? held[like[1].to_i - 1] : nil

          held << { 'words' => words, 'conditions' => earlier ? earlier['conditions'] : conditions(words),
                    'damage' => earlier ? earlier['damage'] : damage(words), 'rounds' => rounds(found[3]) }
        end

        { 'name' => name, 'dc' => head[:dc].to_i, 'save' => head[:save].downcase,
          'onset' => lines.filter_map { |line| line[/\AOnset (.+)\z/, 1] }.first,
          'rounds' => rounds(lines.filter_map { |line| line[/\AMaximum Duration (.+)\z/, 1] }.first),
          'stages' => stages, 'virulent' => slugs.include?('virulent'), 'poison' => slugs.include?('poison'),
          'traits' => slugs }
      end

      # A stage's list is terse and repeats a condition without its capital: `sickened 1 and Slowed 1`.
      def self.conditions(words)
        words.scan(named).map do |valued, value, plain|
          one = { 'condition' => names.find { |name| name.casecmp?(valued || plain) } }
          value ? one.merge('value' => value.to_i) : one
        end
      end

      def self.damage(words)
        words.scan(dealt).reject { |_formula, type| type == 'persistent' }.map { |formula, type| [ formula.delete(' '), type ] }
      end

      # A time in rounds, where it is short enough to be counted in a fight.
      def self.rounds(words)
        found = words.to_s.match(/\A(\d+) (round|minute)s?\z/i)

        found ? found[1].to_i * (found[2].casecmp?('minute') ? 10 : 1) : nil
      end

      # The affliction a creature's Strike carries by this name. A stat block sometimes names it one way
      # on the Strike and another among its abilities, so a creature with only the one is taken to mean it.
      def self.of_creature(holder, effect)
        abilities = Actors.of(holder).own_abilities
        all = abilities.filter_map { |one| read(one['name'], one['text'], one['traits']) }
        named = all.find { |one| one['name'].casecmp?(effect.to_s) }

        return named if named
        return nil if abilities.any? { |one| one['name'].casecmp?(effect.to_s) }

        all.size == 1 ? all.first : nil
      end

      # ------------------------------------------------------------------------------
      # Who has what

      def self.on(holder)
        Array(TurnState.of(holder)[KEY])
      end

      def self.keep(holder, entry)
        TurnState.write(holder, KEY => on(holder).reject { |one| one['name'] == entry['name'] } + [ entry ])
      end

      def self.cure(holder, name)
        found = on(holder).find { |one| one['name'].casecmp?(name.to_s) }

        return nil unless found

        lift(holder, found['name'])
        TurnState.write(holder, KEY => on(holder).reject { |one| one['name'] == found['name'] })
        found
      end

      # What a stage left on them goes as the stage does.
      def self.lift(holder, name)
        (holder.pf2_conditions || {}).select { |_condition, held| held.is_a?(Hash) && held['granted_by'] == name }
                                     .each_key { |condition| Pf2e.remove_condition(holder, condition, true) }
      end

      # How a save moves the stage. A virulent affliction gives way only to two successes running, and
      # by one stage even to a critical success.
      def self.step(degree, virulent, successes)
        return { Degree::CRITICAL_FAILURE => 2, Degree::FAILURE => 1 }[degree] if degree <= Degree::FAILURE
        return degree == Degree::CRITICAL_SUCCESS ? -2 : -1 unless virulent

        degree == Degree::CRITICAL_SUCCESS || successes.positive? ? -1 : 0
      end

      # ------------------------------------------------------------------------------
      # Catching one, and its course

      # Someone is exposed: they save, and a failure starts it - or, for a poison they already carry,
      # worsens it.
      def self.catch(scene, target, affliction, out)
        return if Acting.immune?(affliction['traits'], out, target)

        held = on(target.holder).find { |one| one['name'] == affliction['name'] }

        return out['lines'] << Telling.event('pf2e.affliction_already', :target => target.label, :name => affliction['name']) if held && !affliction['poison']

        degree = save(scene.encounter, target, affliction.merge('by' => scene.actor.label), out)

        return if degree >= Degree::SUCCESS

        rise = degree == Degree::CRITICAL_FAILURE ? 2 : 1
        now = scene.encounter ? scene.encounter.round.to_i : 0
        entry = held || affliction.merge('by' => scene.actor.label, 'stage' => 0, 'successes' => 0,
                                         'until' => affliction['rounds'] ? now + affliction['rounds'] : nil)

        if affliction['onset'] && held.nil?
          keep(target.holder, entry)
          return out['lines'] << Telling.event('pf2e.affliction_onset', :target => target.label, :name => entry['name'], :onset => affliction['onset'])
        end

        stage(scene.encounter, target, entry, entry['stage'].to_i + rise, out)
      end

      # Their save against it, told. Answers the degree.
      def self.save(encounter, target, entry, out)
        source = encounter && entry['by'] ? Combatants.find(encounter, entry['by']) : nil
        origin = source&.ok? ? source.state.holder : nil
        check = Check.of(target.holder, 'save', entry['save'], (origin ? Resolve.seen_as(origin, 'origin') : []) + entry['traits'])
        spared = origin ? Incapacitation.spares?(entry['traits'], target.holder, :source => origin) : false
        result = Resolve.roll(check, :dc => entry['dc'], :shift => Incapacitation.shift(spared, :theirs))

        out['lines'] << Telling.event('pf2e.affliction_save', :target => target.label, :save => entry['save'].capitalize,
                                                             :roll => Telling.roll(result), :dc => entry['dc'], :name => entry['name'],
                                                             :degree => Telling.degree(result['degree'], false))
        out['lines'] << Telling.event('pf2e.act_incapacitation', :target => target.label) if spared

        result['degree']
      end

      # Puts them at a stage: what the last one left is lifted, this one's conditions land and its damage
      # is dealt, and the round of their next save is set. Below the first, it is over.
      def self.stage(encounter, target, entry, stage, out, round = nil)
        holder = target.holder
        lift(holder, entry['name'])

        if stage <= 0
          cure(holder, entry['name'])
          return out['lines'] << Telling.event('pf2e.affliction_over', :target => target.label, :name => entry['name'])
        end

        stage = [ stage, entry['stages'].size ].min
        now = entry['stages'][stage - 1]
        round ||= encounter ? encounter.round.to_i : 0

        keep(holder, entry.merge('stage' => stage, 'next' => now['rounds'] ? round + now['rounds'] : nil))
        out['lines'] << Telling.event('pf2e.affliction_stage', :target => target.label, :name => entry['name'], :stage => stage,
                                                              :words => now['words'])

        now['conditions'].each do |one|
          Pf2e.set_condition(holder, one['condition'], one['value'] || Pf2e.default_condition_value(one['condition']),
                             'granted_by' => entry['name'])
        end

        hurt(encounter, target, entry, now['damage'], out)
      end

      def self.hurt(encounter, target, entry, damage, out)
        return if damage.empty?

        source = encounter && entry['by'] ? Combatants.find(encounter, entry['by']) : nil
        actor = source&.ok? ? source.state : target
        about = out['about']
        out['about'] = DamageAbout.traits(entry['traits'])
        rows = DamageRoll.of_formulas(damage.map { |formula, type| [ formula, type, nil ] }, false)

        Acting.deal(Acting::Scene.new(encounter, actor, target, nil, true), target, rows, out)
        out['about'] = about
      end

      # The end of someone's turn: what has run its course ends, and what has had its stage's time is
      # saved against again. Answers what happened, for whoever tells the room.
      def self.turn_ended(encounter, label, round)
        found = Combatants.find(encounter, label)

        return [] unless found.ok? && found.state.holder && on(found.state.holder).any?

        target = found.state
        round = round.to_i
        out = Acting.report

        on(target.holder).each do |entry|
          if entry['until'] && round >= entry['until'].to_i
            cure(target.holder, entry['name'])
            out['lines'] << Telling.event('pf2e.affliction_over', :target => target.label, :name => entry['name'])
          elsif entry['next'] && round >= entry['next'].to_i
            again(encounter, target, entry, round, out)
          end
        end

        out['lines']
      end

      def self.again(encounter, target, entry, round, out)
        degree = save(encounter, target, entry, out)
        moved = step(degree, entry['virulent'], entry['successes'].to_i)
        entry = entry.merge('successes' => degree >= Degree::SUCCESS && moved.zero? ? entry['successes'].to_i + 1 : 0)

        stage(encounter, target, entry, entry['stage'].to_i + moved, out, round)
      end

      # `Giant Wasp Venom stage 2 (Clumsy 2), a save at the end of this turn`
      def self.reminders(holder, round)
        on(holder).map do |entry|
          stage = entry['stage'].to_i
          words = stage.positive? ? entry['stages'][stage - 1]['words'] : t('pf2e.affliction_waiting', :onset => entry['onset'])
          due = entry['next'] && round.to_i >= entry['next'].to_i ? t('pf2e.affliction_due') : ''

          t('pf2e.affliction_reminder', :name => entry['name'], :stage => stage, :words => words, :due => due)
        end
      end
    end
  end
end
