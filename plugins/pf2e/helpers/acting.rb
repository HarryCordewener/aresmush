module AresMUSH
  module Pf2e

    # What a combatant does in an encounter, resolved: an action, a Strike, a spell.
    #
    # The map is in another app, so everything it would have told Foundry is said in words - the target by
    # its id, `flanking`, `range 2` - and the engine does the arithmetic from there: the check against the
    # target's real defence, the multiple attack penalty from the attacks already made this turn, cover
    # and concealment set on the target, and whatever the outcome does. A consequence an action states
    # outright happens; the GM takes it back with `+e/undo`, like any other change in an encounter.
    #
    # Each entry point answers a report for the command to tell, each part a list of events (`Telling`)
    # that the room, `+e/why` and the portal each render their own way:
    #
    #   'lines'   what the room sees, the rolls in it
    #   'gm'      what only the GM sees: a creature's hit points
    #   'detail'  every modifier of every roll, for `+e/why`
    module Acting

      # Who is acting, at whom, in which encounter, and on whose word. `permitted` is whether the one
      # typing may speak for a target's cover and concealment.
      #
      # Someone acting on themselves is one record held once: a model saves every attribute it holds, so
      # two copies would each write back what the other changed.
      Scene = Struct.new(:encounter, :actor, :target, :enactor, :permitted) do
        def initialize(*)
          super

          return unless actor && target
          return unless actor.holder.class == target.holder.class && actor.holder.id == target.holder.id

          self.target = target.dup.tap { |one| one.holder = actor.holder }
        end
      end

      def self.report
        { 'lines' => [], 'gm' => [], 'detail' => [] }
      end

      # ------------------------------------------------------------------------------
      # What was said

      COVER_WORDS = { 'lesser cover' => 'lesser', 'cover' => 'standard', 'standard cover' => 'standard',
                      'greater cover' => 'greater' }.freeze

      # The words after a command's slashes, sorted into what they mean. Anything not recognised is a
      # circumstance, offered as Foundry's options would spell it, and kept as said so an action can find
      # a variant or a skill in it.
      def self.said(words, permitted)
        Array(words).map { |word| word.to_s.strip }.reject(&:empty?).each_with_object(
          { 'options' => [], 'words' => [], 'refused' => [] }
        ) do |word, out|
          lower = word.downcase

          if lower.match?(/\A\d+\z/) then out['dc'] = lower.to_i
          elsif (found = lower.match(/\Arange\s+(\d+)\z/)) then out['range'] = found[1].to_i
          elsif (found = lower.match(/\Arank\s+(\d+)\z/)) then out['rank'] = found[1].to_i
          elsif (found = lower.match(/\Aactions?\s+(\d+)\z/)) then out['actions'] = found[1].to_i
          elsif (found = lower.match(/\Aclass\s+(.+)\z/)) then out['class'] = found[1].strip
          elsif %w{flanking flanked flank}.include?(lower) then out['flanking'] = true
          elsif COVER_WORDS.key?(lower)
            permitted ? out['cover'] = COVER_WORDS[lower] : out['refused'] << word
          elsif Resolve::CONCEALMENT.key?(lower)
            permitted ? out['concealment'] = lower : out['refused'] << word
          else
            out['words'] << lower
            out['options'] += Pf2e.circumstances([ word ])
          end
        end
      end

      # What the actor's rules read about the roll: what they said, what they know of the target, and -
      # for an action about a particular action - `action:demoralize:unintelligible`.
      def self.options_for(scene, said, slug = nil)
        scoped = slug ? said['words'].map { |word| "action:#{slug}:#{Domains.slug(word)}" } : []
        flanked = said['flanking'] ? [ 'target:condition:off-guard' ] : []

        said['options'] + scoped + flanked + (scene.target ? Resolve.seen_as(scene.target.holder, 'target') : [])
      end

      # The target's cover and concealment: set on it in the encounter, or said for this one roll by
      # someone who may say so.
      def self.cover_of(scene, said)
        said['cover'] || (scene.encounter && scene.target ? (scene.encounter.cover || {})[scene.target.number.to_s] : nil)
      end

      def self.concealment_of(scene, said)
        said['concealment'] ||
          (scene.encounter && scene.target ? (scene.encounter.concealment || {})[scene.target.number.to_s] : nil)
      end

      # What this one attack gives the defender: cover, and the off-guard of being flanked.
      def self.defender_extra(scene, said, against)
        [ Resolve.cover_modifier(cover_of(scene, said), against),
          (said['flanking'] || said['inside']) && against.to_s == 'ac' ? Resolve::FLANKED : nil ].compact
      end

      # ------------------------------------------------------------------------------
      # Actions

      # `targets` is every combatant it is aimed at, where more than one was named; only a creature's
      # ability that deals damage against a save takes more than one.
      # Actions done with a command of their own, which using them as an action points at.
      COMMANDS = { 'quick-alchemy' => '+e/alchemy <item>', 'refocus' => '+e/refocus',
                   'cast-a-spell' => '+e/cast <spell>=<target>' }.freeze

      def self.act(scene, term, words, targets: nil)
        follow = Actors.of(scene.actor.holder).follow_up(term)
        name = follow ? follow['action'] : action_named(scene, term)

        return name if name.is_a?(Err)

        if follow
          followed = follow_up(scene, follow, term)
          return followed if followed
        end

        scene = escaping(scene) if name == ESCAPE
        return scene if scene.is_a?(Err)

        # Out of something that swallowed or engulfed them, at the DC it lists.
        listed = name == ESCAPE ? (Holding.inside(scene.actor.holder) || {})['escape_dc'] : nil
        words = Array(words) + [ listed.to_s ] if listed && Array(words).none? { |word| word.to_s.match?(/\A\d+\z/) }

        stopped = Restraints.refusal(scene.actor, name, traits_of(scene, name))
        return stopped if stopped

        command = COMMANDS[Domains.slug(name)]
        return Err.new(:own_command, 'pf2e.act_own_command', 'action' => name, 'command' => command) if command

        # An exploration activity is taken up while exploring; it and anything else that takes minutes are
        # refused in a fight.
        exploring = Exploration.exploring?(scene.encounter)
        return Exploration.take_up(scene, name, report) if exploring && Exploration.activity?(name)
        if !exploring && scene.encounter && Exploration.only_exploring?(name, Actions.info(name))
          return Err.new(:explore_only, 'pf2e.explore_only', 'action' => name)
        end

        unshielded = name == ShieldBlock::RAISE && ShieldBlock.cannot_raise(scene.actor.holder)
        return unshielded if unshielded

        targets ||= [ scene.target ].compact
        own = Actors.of(scene.actor.holder).own_ability(name)
        ability = own ? MonsterAbilities.row(name, own, scene.actor.holder) : nil
        if targets.size > 1 && !CreatureAbilities.saves?(own_text(scene, name)) && !(ability && ability['several']) &&
           !Afflictions.read(name, own_text(scene, name))
          return Err.new(:one_target, 'pf2e.act_one_target', 'action' => name)
        end

        risked = Restraints.risked(scene.actor, name, traits_of(scene, name))
        return lost(scene, name, risked) if risked && !risked['kept']

        return MonsterAbilities.use(scene, name, own, targets) if ability

        return strike(scene, nil, words) if name == 'Strike'

        entry = Actions.info(name)
        entry = follow_up_entry(entry, follow, term) if follow

        return reaction_strike(scene, name, entry, words) if entry['strike']
        return several_strikes(scene, name, entry, words) if entry['strikes']
        return shield_block(scene, name, entry) if name == ShieldBlock::NAME
        return bonded_item(scene, name, entry, words) if name == BondedItem::NAME
        return attack_answer(scene, name, entry) if entry['type'] == 'reaction' && AttackAnswers.answer(scene.actor.holder, name)
        said = said(words, scene.permitted)
        out = report
        refused(out, said)
        out['lines'] << risked['line'] if risked

        # A creature's own ability, which no catalogue holds.
        return announce_ability(scene, name, out, targets) if entry.empty?

        if entry['check']
          check_action(scene, name, entry, said, out)
          push_distance(scene, term, out) if follow && follow['action'] == 'Shove'
        elsif entry['self_effect']
          self_action(scene, name, entry, said, out)
        else
          out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => name,
                                                  :cost => Actions.cost(name), :target => target_phrase(scene))
          consequences(scene, Array(Actions.consequences(Domains.slug(name))['always']), out)
        end

        spend(scene, name, entry, out)

        Ok.new(:state => out)
      end

      ESCAPE = 'Escape'.freeze

      # The traits of what is being done: the catalogue's, or the creature's own ability's.
      def self.traits_of(scene, name)
        own = Actors.of(scene.actor.holder).own_ability(name)

        Array((own || Actions.info(name))['traits'])
      end

      # An action a grabbed creature's flat check lost: it is spent, and nothing comes of it.
      def self.lost(scene, name, risked)
        out = report
        out['lines'] << risked['line']
        spend(scene, name, Actions.info(name), out)

        Ok.new(:state => out)
      end

      # What a creature's follow-up to a Strike needs before it is attempted. A Grab on someone it
      # already holds tightens the hold without a roll, which is all of the action; anything else needs
      # the Strike that lists it to have just hit this target. Answers the outcome where there is nothing
      # left to attempt, and nothing where the attempt goes ahead.
      def self.follow_up(scene, follow, term)
        label = Domains.slug(term).split('-').map(&:capitalize).join(' ')
        held = follow['action'] == 'Grapple' ? Holding.held_by(scene.encounter, scene.actor.label) : []
        target = scene.target || (held.size == 1 ? held.first : nil)

        if target && held.any? { |one| one.label == target.label }
          out = report
          out['lines'] << Holding.tighten(scene.encounter, scene.actor, target)
          # Keeping a hold costs an action, even for a creature whose Grab is free after a hit.
          TurnState.spend(scene.actor.holder, label, :cost => 1, :type => 'action')

          return Ok.new(:state => out)
        end

        return nil if scene.target && TurnState.followed?(scene.actor.holder, term, scene.target.label)

        Err.new(:follow_up_needs_hit, 'pf2e.follow_up_needs_hit', 'action' => label, 'actor' => scene.actor.label)
      end

      # Escape is from whoever holds them, where nobody is named; with nothing holding them there is
      # nothing to escape.
      def self.escaping(scene)
        return Err.new(:escape_nothing, 'pf2e.escape_nothing') unless Holding.held?(scene.actor.holder)
        return scene if scene.target

        by = Holding.by(scene.actor.holder)
        holder = by && scene.encounter ? Combatants.find(scene.encounter, by) : nil

        holder&.ok? ? Scene.new(scene.encounter, scene.actor, holder.state, scene.enactor, scene.permitted) : scene
      end

      # A follow-up is the action it attempts, named for the ability, costing what the ability costs, and
      # outside the multiple attack penalty.
      def self.follow_up_entry(entry, follow, term)
        label = Domains.slug(term).split('-').map(&:capitalize).join(' ')

        entry.merge('type' => follow['type'], 'cost' => follow['cost'], 'no_map' => true, 'label' => label)
      end

      # The action the actor means: one of the catalogue's they may use, or - for a creature - one of its
      # own abilities by name.
      def self.action_named(scene, term)
        actor = Actors.of(scene.actor.holder)
        own = actor.own_ability(term)

        return own['name'] if own

        found = Actions.find(term)

        return found if found.err?

        allowed = actor.may_use(found.state)

        allowed.err? ? allowed : found.state
      end

      def self.own_text(scene, name)
        (Actors.of(scene.actor.holder).own_ability(name) || {})['text']
      end

      # A creature's ability that no catalogue holds: its stat block's words, for the GM to run - and where
      # they say what it deals and the save against it, each target's save rolled and the damage dealt.
      # That a creature uses an ability of its own, at whom, for what it costs, and its stat block's words:
      # all of them where they are the GM's to run, and only its line of figures (`brief`) where the game
      # runs it.
      def self.announce(scene, name, own, targets, out, brief: false)
        cost = own['type'] == 'action' ? Actions::COSTS[own['cost'].to_i] || 'one action' : Actions::TYPES[own['type']]
        aimed = targets.map(&:label).join(', ')
        words = brief ? own['text'].to_s.split('%r').first : own['text']

        out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => name, :cost => cost,
                                                :target => aimed.empty? ? '' : told('pf2e.act_at', :target => aimed))
        out['lines'] << told('pf2e.act_note', :text => words) unless words.to_s.empty?
      end

      # What using it costs the turn. A reaction already spent is the GM's to allow, and they are told.
      def self.paid(scene, name, own, out = nil)
        reaction_spent(scene, out) if out && own['type'] == 'reaction'

        TurnState.spend(scene.actor.holder, name, :cost => own['cost'] || 1, :type => own['type'] || 'action',
                                                  :attack => Array(own['traits']).include?('attack'))
      end

      def self.reaction_spent(scene, out)
        return unless TurnState.turn(scene.actor.holder)['reaction']

        out['gm'] << told('pf2e.act_reaction_spent', :actor => scene.actor.label)
      end

      # A Push whose stat block lists how far: that far on a success, and twice it on a critical success.
      def self.push_distance(scene, term, out)
        listed = Array(Actors.of(scene.actor.holder).own_abilities).map { |one| one['name'].to_s[/\A(?:Improved )?Push (\d+) feet\z/i, 1] }.compact.first

        out['lines'] << told('pf2e.act_push_distance', :feet => listed.to_i, :twice => listed.to_i * 2) if listed
      end

      def self.announce_ability(scene, name, out, targets = [ scene.target ].compact)
        own = Actors.of(scene.actor.holder).own_ability(name) || {}
        announce(scene, name, own, targets, out)
        Recharge.used(scene, name, own, out)

        affliction = Afflictions.read(name, own['text'], own['traits'])

        if affliction
          targets.each { |target| Afflictions.catch(scene, target, affliction, out) }
        else
          ability_saves(scene, name, own, targets, out)
        end

        paid(scene, name, own, out)

        Ok.new(:state => out)
      end

      # A creature's ability whose words call for a save: each target rolls it, takes what the words deal
      # by how they rolled, and is left with what the outcome names. Whoever is immune to it - by a trait
      # of it, or for having saved against it lately - is passed by. Answers whether there was a save.
      def self.ability_saves(scene, name, own, targets, out)
        figures = CreatureAbilities.saving(own['text'])
        listed = figures ? nil : CreatureAbilities.damage_save(own['text'])

        return false unless figures || listed

        figures ||= { 'dc' => listed['dc'], 'save' => listed['save'], 'basic' => true,
                      'damage' => [ [ listed['formula'], listed['type'] ] ], 'outcomes' => {}, 'outcome_text' => {} }
        # Damage with no outcomes of its own to scale it is a basic save's, as an area's is.
        basic = figures['basic'] || figures['outcome_text'].empty?
        mechanics = figures.slice('save', 'outcomes', 'outcome_text').merge('basic' => basic, 'traits' => Array(own['traits']))
        formulas = figures['damage'].map { |formula, type| [ formula, type, nil, [ 'damage' ] ] }
        out['about'] = DamageAbout.of_ability(own)

        targets.each do |target|
          next if immune?(own['traits'], out, target)
          next if lately_saved?(scene, name, target, out)

          degree = spell_save(Scene.new(scene.encounter, scene.actor, target, scene.enactor, scene.permitted), name,
                              mechanics, figures['dc'], formulas, out)
          saved_against(scene, name, target, figures['immune'], degree)

          next unless degree && degree <= Degree::FAILURE

          # What whoever failed also burns with.
          Array(figures['persistent']).each do |formula, type|
            PersistentDamage.add(target.holder, formula, type)
            out['lines'] << told('pf2e.act_damage', :target => target.label,
                                                 :damage => told('pf2e.act_persistent', :formula => formula, :type => type))
          end
        end

        true
      end

      # Immunity for a while to something already saved against: a dragon's presence, a ghoul's stench.
      LATELY = 'saved'.freeze

      def self.lately_saved?(scene, name, target, out)
        till = (TurnState.of(target.holder)[LATELY] || {})["#{name}@#{scene.actor.label}"].to_i

        return false unless scene.encounter && till > scene.encounter.round.to_i

        out['lines'] << told('pf2e.act_temp_immune', :target => target.label, :action => name)
        true
      end

      def self.saved_against(scene, name, target, immune, degree)
        return unless immune && scene.encounter && degree
        return if immune['after'] == 'success' && degree < Degree::SUCCESS
        return if immune['after'] == 'critical' && degree < Degree::CRITICAL_SUCCESS

        held = TurnState.of(target.holder)[LATELY] || {}
        till = scene.encounter.round.to_i + immune['rounds'].to_i

        TurnState.write(target.holder, LATELY => held.merge("#{name}@#{scene.actor.label}" => till))
      end

      def self.target_phrase(scene)
        scene.target ? told('pf2e.act_at', :target => scene.target.label) : ''
      end

      # An action that puts an effect on whoever uses it: Rage, Take Cover, a stance.
      # What is said after the action's name reaches its effect: the rank it is at, a counter, an answer
      # to what it asks - `action/use rage` and `+e/act raise a shield` are the same command.
      def self.self_action(scene, name, entry, said, out)
        temporary = temp_hp_of(scene.actor.holder)
        applied = ActiveEffects.apply(scene.actor.holder, entry['self_effect'], :options => effect_options(said),
                                                                                :applied_by => scene.actor.label,
                                                                                :encounter => scene.encounter)

        if applied.err?
          out['lines'] << told(applied.key, applied.args)
          return
        end

        effect = applied.state

        out['lines'] << told('pf2e.act_self_effect', :actor => scene.actor.label, :action => name,
                                                  :cost => Actions.cost(name), :effect => effect.name,
                                                  :lasts => ActiveEffects.remaining(effect))

        gained = temp_hp_of(scene.actor.holder) - temporary
        out['lines'] << told('pf2e.act_temp_hp', :count => temp_hp_of(scene.actor.holder)) if gained.positive?
      end

      # Temporary hit points, wherever the holder keeps them.
      def self.temp_hp_of(holder)
        fresh = holder.class[holder.id] || holder

        (fresh.respond_to?(:temp_hp) ? fresh.temp_hp : fresh.hp&.temp_hp).to_i
      end

      # What was said about an effect, in the words `ActiveEffects.apply` takes: `rank 6`, `value 3`, and
      # an answer to what it asks.
      def self.effect_options(said)
        (said['rank'] ? [ "rank #{said['rank']}" ] : []) + said['words']
      end

      # An action whose check is rolled against something: a target's defence, or a DC.
      def self.check_action(scene, name, entry, said, out)
        out['about'] = DamageAbout.traits(entry['traits'])

        return if immune?(entry['traits'], out, scene.target)

        check = entry['check']
        variant = variant_of(check, said)
        check = check.merge(variant) if variant
        slug = check['slug'] || Domains.slug(name)

        figure = statistic_for(scene.actor.holder, check['statistic'], said)

        if figure.is_a?(Err)
          out['lines'] << told(figure.key, figure.args)
          return
        end

        kind, stat_name = figure
        attack = Array(entry['traits']).include?('attack') && !entry['no_map']
        name = entry['label'] || name
        options = Array(check['options']) + options_for(scene, said, slug) +
                  (attack ? TurnState.map_options(scene.actor.holder) : [])
        rolled_check = Check.of(scene.actor.holder, kind, stat_name, options)
        extra = action_modifiers(check, rolled_check.options) + weapon_bonus(scene.actor.holder, check) +
                (attack ? attack_penalty(scene.actor.holder) : [])

        defence = nil
        dc = said['dc'] || check['dc']

        if dc.nil? && check['against'] && scene.target
          defence = Resolve.defence(scene.target.holder, check['against'],
                                    :options => Resolve.seen_as(scene.actor.holder, 'origin'),
                                    :extra => defender_extra(scene, said, check['against']))
          dc = defence && defence['dc']
        end

        spared = scene.target && Incapacitation.spares?(entry['traits'], scene.target.holder, :source => scene.actor.holder)
        result = Resolve.roll(rolled_check, :dc => dc, :extra => extra, :shift => Incapacitation.shift(spared, :against))
        statistic = stat_name ? stat_name.to_s : kind.capitalize

        out['lines'] << check_line(scene, name, statistic, result, check, defence, dc)
        out['lines'] << told('pf2e.act_incapacitation_against', :target => scene.target.label) if spared
        out['detail'] += detail_lines(name, statistic, result, defence)

        return unless result['degree']

        outcome = Degree::NAMES[result['degree']]
        applied = Array(Actions.consequences(slug, check['variant'])[outcome])

        # The action's own words for the outcome, where the engine has nothing of its own to do: where it
        # does, what it does is told as it is done.
        note = (check['notes'] || {})[outcome]
        out['lines'] << told('pf2e.act_note', :text => note) if note && applied.empty?

        rolled_check.notes(result['degree']).each { |one| out['lines'] << told('pf2e.act_note', :text => one['text']) if one['text'] }

        consequences(scene, applied, out, :rank => rank_of(scene.actor.holder, kind, stat_name), :dc => dc,
                                          :options => Array(check['options']))
      end

      # The way of doing the action the actor named - `stabilize` for First Aid - or its first. The
      # variant's slug is kept, because what its outcomes do is keyed by it.
      def self.variant_of(check, said)
        variants = check['variants'] || {}

        found = said['words'].map { |word| Domains.slug(word) }.find { |word| variants.key?(word) } ||
                variants.keys.first

        found ? variants[found].reject { |field, _| field == 'name' }.merge('variant' => found) : nil
      end

      # Which figure the action rolls. One statistic is that one; a choice of several is the one the
      # actor names, or their best; an action that rolls whatever the actor chooses - Aid - needs them to
      # name it.
      def self.statistic_for(holder, statistic, said)
        candidates = Array(statistic).reject { |one| one.to_s.empty? || one == 'unarmed' }
        named = said['words'].map { |word| Stat.identify(word) }.compact
                             .find { |kind, _| %w{skill lore perception}.include?(kind) }
        allowed = named && (candidates.empty? ||
                            candidates.any? { |one| Domains.slug(one) == Domains.slug(named[1] || named[0]) })

        return named if allowed
        return Err.new(:name_a_skill, 'pf2e.act_name_a_skill') if candidates.empty?

        figures = candidates.map { |one| Stat.identify(one) }.compact

        figures.max_by { |kind, name| Check.of(holder, kind, name).total.to_i }
      end

      # The modifiers an action's own check carries, where their circumstances hold: Demoralize is -4
      # against a creature that does not understand you.
      def self.action_modifiers(check, options)
        Array(check['modifiers']).select { |one| Predicate.test(one['predicate'], options) }.map do |one|
          { 'source' => one['label'] || check['slug'], 'slug' => Domains.slug(one['label']),
            'type' => one['type'] || 'untyped', 'value' => one['value'].to_i }
        end
      end

      # A weapon with the action's trait lends its potency rune to the check: a +1 trip weapon adds +1 to
      # Trip (`action-macros/helpers.ts` `getWeaponPotencyModifier`). A ranged trip is -2.
      def self.weapon_bonus(holder, check)
        wanted = Array(check['weapon_traits'])

        return [] if wanted.empty?

        weapon = Actors.of(holder).weapons_with_traits(wanted).first

        return [] unless weapon

        rows = [ Stat.item(Pf2egear.get_rune_value(weapon, 'fundamental', 'potency'), "#{weapon.name} potency",
                           'weapon-potency') ].compact
        rows << { 'source' => 'ranged trip', 'slug' => 'ranged-trip', 'type' => 'circumstance', 'value' => -2 } if
          Array(weapon.traits).map { |trait| Domains.slug(trait) }.include?('ranged-trip')

        rows
      end

      # An action with the attack trait that is not a Strike takes the multiple attack penalty as well,
      # at -5 and -10: nothing about it is agile.
      def self.attack_penalty(holder)
        attacks = TurnState.turn(holder)['attacks'].to_i

        return [] unless attacks.positive?

        [ { 'source' => 'multiple attack penalty', 'slug' => 'multiple-attack-penalty', 'type' => 'untyped',
            'value' => TurnState.map_penalty(attacks) } ]
      end

      def self.rank_of(holder, kind, name)
        Actors.of(holder).proficiency(kind, name)
      end

      # Whether the last hit on them can still be answered: nothing has moved their hit points since.
      # Whether someone who is down may still do this: answer the hit that dropped them, or - for a
      # creature - use what its stat block gives it for the moment it drops.
      def self.answering?(holder, doing = nil)
        return when_down?(holder, doing) if Actors.of(holder).creature?

        %w{attacked struck}.any? do |key|
          hit = TurnState.of(holder)[key]

          hit && hit['after'] == AttackAnswers.standing(holder)
        end
      end

      def self.when_down?(holder, doing)
        own = doing ? Actors.of(holder).own_ability(doing) : nil

        !own.nil? && (MonsterAbilities.row(own['name']) || {})['when_down'] == true
      end

      # What a creature that has just dropped may still do, for its GM to use.
      def self.offered_when_down(holder)
        Array(holder.stat_block['actions']).map { |one| one['name'] }.select { |name| when_down?(holder, name) }
      end

      def self.attack_answer(scene, name, entry)
        answered = AttackAnswers.use(scene, name, report)

        spend(scene, name, entry, answered.state) if answered.ok?
        answered
      end

      def self.bonded_item(scene, name, entry, words)
        drained = BondedItem.drain(scene, words, report)

        spend(scene, name, entry, drained.state) if drained.ok?
        drained
      end

      def self.shield_block(scene, name, entry)
        blocked = ShieldBlock.block(scene, report)

        spend(scene, name, entry, blocked.state) if blocked.ok?
        blocked
      end

      # ------------------------------------------------------------------------------
      # Strikes

      # A Strike made as a reaction, Reactive Strike's: with the attack named among what was said, or the
      # first that will do. It spends the reaction, and the multiple attack penalty neither applies to it
      # nor counts it.
      def self.reaction_strike(scene, name, entry, words)
        melee = entry['strike'] == 'melee'
        term = said(words, scene.permitted)['words'].find { |word| attack_for(scene.actor.holder, word, :melee => melee) }

        strike(scene, term, words, :reaction => name, :melee => melee)
      end

      # Which attacks an action's Strikes may be made with: `unarmed`, `melee` or `ranged`, or any.
      STRIKE_KINDS = {
        'unarmed' => ->(attack) { Pf2e.has_trait?(attack['traits'], 'unarmed') },
        'melee' => ->(attack) { !attack['ranged'] },
        'ranged' => ->(attack) { attack['ranged'] || Array(attack['traits']).any? { |one| one.to_s.start_with?('thrown') } }
      }.freeze

      # An action that is several Strikes - Flurry of Blows' two unarmed ones - or a Strike and something
      # more - Deadly Aim's ranged one - at the one target, each counting toward the multiple attack
      # penalty, for what the action costs, and with the action's own rules switched on. What they hit
      # with is dealt together, so a resistance or weakness applies once to the whole.
      def self.several_strikes(scene, name, entry, words)
        holder = scene.actor.holder
        kind = entry['strikes']['attack']
        usable = attacks_of(holder).select { |_, attack| !STRIKE_KINDS[kind] || STRIKE_KINDS[kind].call(attack) }
        named = said(words, scene.permitted)['words']
        attack = named.map { |word| usable.find { |names, _| names.any? { |one| Domains.slug(one) == Domains.slug(word) } } }.compact.first ||
                 usable.first

        return Err.new(:no_attack, 'pf2e.act_no_attack', 'attack' => kind.to_s) unless attack

        words = Array(words) + own_toggles(holder, name)

        out = report
        out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => name,
                                                :cost => Actions.cost(name), :target => target_phrase(scene))

        hits = []

        entry['strikes']['count'].to_i.times do
          struck = strike(scene, attack.first.first, words, :spent => false, :hold => true)

          return struck if struck.err?

          %w{lines gm detail}.each { |key| out[key] += struck.state[key] }
          hits += struck.state['held']
        end

        deal(scene, scene.target, combined(hits), out, :critical => hits.any? { |one| one['critical'] }) if hits.any?
        spend(scene, name, entry, out)
        Ok.new(:state => out)
      end

      # The circumstances an action's own rules declare to switch themselves on, which using it does.
      def self.own_toggles(holder, name)
        source = Effects.sources(holder).find { |one| Domains.slug(one['name']) == Domains.slug(name) }

        source ? Rules.of_kind(source, 'RollOption').select { |row| row['toggleable'] }.map { |row| row['option'].to_s } : []
      end

      # Hits' damage as one: each kind added up, and each persistent damage as it is.
      def self.combined(hits)
        immediate, persistent = hits.flat_map { |one| one['rows'] }.partition { |row| row['category'].to_s != 'persistent' }

        immediate.group_by { |row| [ row['type'], row['category'] ] }
                 .map { |_, rows| rows.first.merge('amount' => rows.sum { |row| row['amount'].to_i }) } + persistent
      end

      # `hold` keeps a hit's damage in the report's `held` for the caller to deal, with what else it hit.
      def self.strike(scene, weapon_term, words, reaction: nil, melee: false, spent: true, hold: false)
        said = said(words, scene.permitted)
        out = report
        out['held'] = [] if hold
        refused(out, said)

        return Err.new(:no_target, 'pf2e.act_needs_target') unless scene.target

        attack = attack_for(scene.actor.holder, weapon_term, :melee => melee)

        return Err.new(:no_attack, 'pf2e.act_no_attack', 'attack' => weapon_term.to_s) unless attack

        stopped = Restraints.refusal(scene.actor, 'Strike', [ 'attack' ])
        return stopped if stopped

        # What has swallowed someone cannot attack them, and is off-guard to them.
        if Holding.inside?(scene.target.holder, scene.actor.label)
          return Err.new(:swallowed, 'pf2e.swallowed_cannot_attack', 'actor' => scene.actor.label, 'target' => scene.target.label)
        end
        said = said.merge('inside' => true) if Holding.inside?(scene.actor.holder, scene.target.label)

        if reaction
          out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => reaction,
                                                  :cost => Actions.cost(reaction), :target => target_phrase(scene))
          reaction_spent(scene, out)
        end

        # Range increments are a ranged or thrown attack's; a melee Strike ignores them.
        increments = attack['ranged'] || Pf2e.has_trait?(attack['traits'], 'thrown') ? said['range'].to_i : 0
        said = said.merge('range' => increments, 'no_map' => !reaction.nil?)
        return Err.new(:out_of_range, 'pf2e.act_out_of_range') if increments > 6

        penalty = said['no_map'] ? [] : TurnState.map_options(scene.actor.holder)
        options = penalty + options_for(scene, said, 'strike') + [ 'action:strike' ]
        check = Check.of(scene.actor.holder, 'attack', attack, options)
        extra = increments > 1 ? [ { 'source' => "range increment #{increments}", 'slug' => 'range-penalty',
                                     'type' => 'untyped', 'value' => -2 * (increments - 1) } ] : []

        rolled = attack_roll(scene, attack, check, said, extra, out)
        out['lines'] << rolled['line']

        # A hit kept to be answered is the last attack's; one that misses leaves nothing to answer.
        unless rolled['hit'] || scene.target.creature?
          TurnState.write(scene.target.holder, 'struck' => nil, 'attacked' => nil)
        end

        if rolled['hit']
          hit(scene, attack, check, rolled['result'], out)
        elsif attack['bomb'] && rolled.dig('result', 'degree') == Degree::FAILURE
          splash(scene, attack, check, out)
        end

        # A bomb is thrown whatever it does.
        Consumables.spend!(scene.actor.holder, attack['consumable']) if attack['consumable']

        if reaction
          TurnState.spend(scene.actor.holder, reaction, :type => 'reaction')
        else
          TurnState.spend(scene.actor.holder, 'Strike', :cost => spent ? 1 : 0, :type => 'action', :attack => true,
                                                        :struck => { 'strike' => attack['name'], 'target' => scene.target.label,
                                                                     'hit' => rolled['hit'] ? true : false,
                                                                     'effects' => Array(attack['effects']) })
        end

        Ok.new(:state => out)
      end

      # The concealment flat check, then the attack against AC.
      #
      #   { 'line' => what the room sees, 'result' => the roll, 'hit' => whether it hit }
      def self.attack_roll(scene, attack, check, said, extra, out)
        concealment = concealment_of(scene, said)
        flat = concealment ? Resolve.flat(Resolve::CONCEALMENT[concealment]) : nil

        if flat && !flat['success']
          return { 'hit' => false,
                   'line' => told('pf2e.act_concealed_miss', :actor => scene.actor.label, :target => scene.target.label,
                                                          :attack => attack['name'], :concealment => concealment,
                                                          :die => flat['die'], :dc => flat['dc']) }
        end

        defence = Resolve.defence(scene.target.holder, 'ac', :options => Resolve.seen_as(scene.actor.holder, 'origin'),
                                                             :extra => defender_extra(scene, said, 'ac'))
        result = Resolve.roll(check, :dc => defence['dc'], :extra => extra)

        out['detail'] += detail_lines(attack['name'], 'attack', result, defence)
        out['detail'] << told('pf2e.act_flat_passed', :concealment => concealment, :die => flat['die'], :dc => flat['dc']) if flat

        line = told('pf2e.act_strike_line', :actor => scene.actor.label, :target => scene.target.label,
                                         :attack => attack['name'], :circumstances => circumstance_phrase(scene, said),
                                         :roll => Telling.roll(result), :ac => defence['dc'],
                                         :degree => Telling.degree(result['degree'], true))

        { 'line' => line, 'result' => result, 'hit' => Degree.success?(result['degree']) }
      end

      # `(2nd attack, flanking, standard cover)`.
      def self.circumstance_phrase(scene, said)
        attacks = TurnState.turn(scene.actor.holder)['attacks'].to_i
        parts = []
        parts << told('pf2e.act_nth_attack', :nth => [ attacks + 1, 3 ].min == 2 ? '2nd' : '3rd') if attacks.positive? && !said['no_map']
        parts << told('pf2e.act_flanking') if said['flanking']
        parts << told('pf2e.act_from_inside') if said['inside']
        parts << told('pf2e.act_range', :range => said['range']) if said['range'].to_i > 1
        cover = cover_of(scene, said)
        parts << told('pf2e.act_cover_level', :level => cover) if cover
        concealment = concealment_of(scene, said)
        parts << concealment if concealment

        parts.empty? ? '' : told('pf2e.act_circumstances', :list => parts)
      end

      # What a Strike does when it hits.
      def self.hit(scene, attack, check, result, out)
        critical = result['degree'] == Degree::CRITICAL_SUCCESS
        # A critical hit on something immune to critical hits is a critical hit that deals a hit's damage.
        doubled = critical && !IWR.immune?(iwr_of(scene.target.holder), [ 'critical' ])
        out['lines'] << told('pf2e.act_crit_immune', :target => scene.target.label) if critical && !doubled
        rows = Actors.of(scene.actor.holder).strike_damage(attack, check, doubled)
        answerable = !scene.target.creature?
        out['about'] = DamageAbout.of_attack(attack, check.options)

        if answerable
          calm = critical ? Actors.of(scene.actor.holder).strike_damage(attack, check, false) : rows
          AttackAnswers.remember(scene.target.holder, result, calm)
        end

        if out['held']
          out['held'] << { 'rows' => rows, 'critical' => critical }
        else
          deal(scene, scene.target, rows, out, :critical => critical)
        end

        Consumables.effect(scene.encounter, scene.actor.label, scene.target, attack['effect'], out) if attack['bomb'] && attack['effect']

        follow_ups(scene, attack, out)

        critical_specialization(scene, attack, out) if critical
        Recharge.critical_hit(scene, out) if critical

        return unless answerable

        AttackAnswers.dealt(scene.target.holder)
        AttackAnswers.offered(scene.target.holder).each do |reaction|
          out['lines'] << told('pf2e.act_follow_up', :effect => reaction, :command => "+e/act #{reaction.downcase}")
        end
      end

      # A splash weapon that misses still splashes the target, though not on a critical miss.
      def self.splash(scene, attack, check, out)
        rows = Actors.of(scene.actor.holder).strike_damage(attack, check, false).select { |row| row['category'] == 'splash' }

        deal(scene, scene.target, rows, out) if rows.any?
      end

      # What a creature's Strike lets it do next, where the stat block lists it: Grab, Knockdown and Push
      # are actions of their own that attempt a Grapple, Trip or Shove, and the line names the command.
      # Any other attack effect is the GM's to run.
      def self.follow_ups(scene, attack, out)
        Array(attack['effects']).each do |effect|
          if FOLLOW_UPS.key?(Domains.slug(effect))
            out['lines'] << told('pf2e.act_follow_up', :effect => effect,
                                                    :command => "+e/as #{scene.actor.ref}=act #{Domains.slug(effect).tr('-', ' ')}=#{scene.target.ref}")
          elsif (affliction = Afflictions.of_creature(scene.actor.holder, effect))
            # A venom the Strike carries: whoever it hit saves against it now.
            Afflictions.catch(scene, scene.target, affliction, out)
          else
            out['lines'] << told('pf2e.act_attack_effects', :effects => effect)
          end
        end
      end

      # A creature's follow-up after a Strike that lists it: the action it attempts, and what it costs.
      # It neither takes nor adds to the multiple attack penalty; the improved form is a free action.
      FOLLOW_UPS = {
        'grab' => { 'action' => 'Grapple', 'type' => 'action', 'cost' => 1 },
        'improved-grab' => { 'action' => 'Grapple', 'type' => 'free', 'cost' => 0 },
        'knockdown' => { 'action' => 'Trip', 'type' => 'action', 'cost' => 1 },
        'improved-knockdown' => { 'action' => 'Trip', 'type' => 'free', 'cost' => 0 },
        'push' => { 'action' => 'Shove', 'type' => 'action', 'cost' => 1 },
        'improved-push' => { 'action' => 'Shove', 'type' => 'free', 'cost' => 0 }
      }.freeze

      # A critical hit with a weapon whose critical specialization effect the character has. What the
      # engine can do it does; what is movement on the map, or a judgement, is shown for the GM.
      def self.critical_specialization(scene, attack, out)
        found = Actors.of(scene.actor.holder).critical_specialization(attack)

        return unless found

        out['lines'] << told('pf2e.act_crit_spec', :group => found['group'])

        return out['lines'] << told('pf2e.act_crit_spec_text', :text => found['text']) if found['effects'].empty?

        found['effects'].each do |one|
          if one['save'] then crit_spec_save(scene, one, out)
          elsif one['persistent'] then crit_spec_bleed(scene, attack, one, out)
          elsif one['damage_per_die'] then crit_spec_damage(scene, attack, one, out)
          elsif one['condition'] then condition_consequence(scene, scene.target, one, out)
          end
        end
      end

      # Persistent damage, with the weapon's potency rune added where the effect says so: a +1 knife's
      # bleed is 1d6+1.
      def self.crit_spec_bleed(scene, attack, one, out)
        bonus = one['potency'] ? attack['rune'].to_i : 0
        formula = bonus.positive? ? "#{one['persistent']}+#{bonus}" : one['persistent']

        PersistentDamage.add(scene.target.holder, formula, one['type'])
        out['lines'] << told('pf2e.act_damage', :target => scene.target.label,
                                             :damage => told('pf2e.act_persistent', :formula => formula, :type => one['type']))
      end

      # More damage of the weapon's own kind for each of its damage dice: a pick's 2 per die.
      def self.crit_spec_damage(scene, attack, one, out)
        dice = (attack['dice'] || 1).to_i + attack['striking'].to_i
        kind = DamageRoll.kind(attack['damage_type'])

        deal(scene, scene.target, [ { 'amount' => one['damage_per_die'].to_i * dice, 'type' => kind } ], out)
      end

      # The target saves against the attacker's DC, and a failure does what the effect says.
      def self.crit_spec_save(scene, one, out)
        dc = Stat.total(scene.actor.holder, one['against'] == 'class_dc' ? 'class_dc' : one['against'])
        check = Check.of(scene.target.holder, 'save', one['save'], Resolve.seen_as(scene.actor.holder, 'origin'))
        result = Resolve.roll(check, :dc => dc)

        out['lines'] << told('pf2e.act_save_line', :target => scene.target.label, :save => one['save'].capitalize,
                                                :roll => Telling.roll(result), :dc => dc,
                                                :degree => Telling.degree(result['degree'], false))

        return if Degree.success?(result['degree'])

        consequences(scene, Array(one['failure']).map { |effect| effect.merge('on' => 'target') }, out)
      end

      # Damage landing on someone: persistent damage is set to burn, the rest dealt after what they
      # resist, and the room is told what they took.
      # `critical` is a critical hit's, or a critically failed save's: one that drops a character leaves
      # them nearer death.
      def self.deal(scene, whom, rows, out, critical: false)
        # Nothing to deal - a basic save critically succeeded - is told as nothing, not as 0 damage.
        if rows.all? { |row| row['amount'].to_i <= 0 && row['category'].to_s != 'persistent' }
          return out['lines'] << told('pf2e.act_unharmed', :target => whom.label)
        end

        immediate, persistent = rows.partition { |row| row['category'].to_s != 'persistent' }
        shown = []
        standing = still_up(whom.holder)
        blockable = ShieldBlock.before(whom.holder)
        taken = 0
        physical = 0
        fate = nil

        # Precision damage is lost on a target immune to it; the rest of each type is taken together.
        precise, immediate = immediate.partition { |row| row['category'].to_s == 'precision' }
        if precise.any? && IWR.immune?(iwr_of(whom.holder), [ 'precision' ])
          shown << "0 precision (immune)"
          precise = []
        end

        felt = []
        sharp = 0
        # A hit brings someone a step nearer death once, by whichever kind of its damage first gets through.
        stepped = false

        DamageRoll.by_type(immediate + precise).each do |row|
          was = still_up(whom.holder)
          held = Harm.damage(whom.holder, row['amount'], row['type'], :critical => critical, :continuing => stepped,
                                                                      :about => Array(out['about']) + Array(row['categories']),
                                                                      :once => felt)
          stepped ||= !held['fate'].nil? || still_up(whom.holder) != was
          fate ||= held['fate']
          taken += held['amount'].to_i
          physical += held['amount'].to_i if ShieldBlock.physical?(row['type'])
          sharp += held['amount'].to_i if %w{piercing slashing}.include?(DamageRoll.kind(row['type']).to_s)
          resisted = Array(held['applied']).reject { |one| one['category'] != 'immunity' && one['adjustment'].to_i.zero? }
                                           .map { |one| one['category'] == 'immunity' ? 'immune' : "#{one['category']} #{one['adjustment']}" }
          kind = row['categories'] == [ 'splash' ] ? "splash #{row['type']}" : row['type']
          notes = (row['splash'].to_i.positive? ? [ "with #{row['splash']} splash" ] : []) + resisted
          shown << "#{held['amount']} #{kind}#{notes.empty? ? '' : " (#{notes.join(', ')})"}"
        end

        # Words already, because they join the rest of the hit in one line.
        persistent.each do |row|
          PersistentDamage.add(whom.holder, row['formula'], row['type'])
          shown << Telling.value(told('pf2e.act_persistent', :formula => row['formula'], :type => row['type']))
        end

        return if shown.empty?

        out['lines'] << told('pf2e.act_damage', :damage => shown.join(' + '), :target => whom.label)
        out['gm'] << told('pf2e.act_hp_left', :target => whom.label, :hp => Harm.hit_points(whom.holder))
        dropped(whom, standing, out, fate)
        freed = scene.actor ? Holding.cut_free(scene.actor, whom, sharp) : nil
        out['lines'] << freed if freed
        offer_block(whom, blockable, taken, physical, critical, out) if blockable && physical.positive?
      end

      # A hit a raised shield could have taken is kept for Shield Block, and its bearer told they may.
      def self.offer_block(whom, before, taken, physical, critical, out)
        ShieldBlock.remember(whom.holder, before, taken, physical, critical)

        return unless ShieldBlock.offered?(whom.holder)

        out['lines'] << told('pf2e.act_follow_up', :effect => ShieldBlock::NAME, :command => '+e/act shield block')
      end

      def self.iwr_of(holder)
        IWR.for(holder)
      end

      # Whether the target is immune to an effect with one of these traits, which is then all of what
      # happens to them: the room is told, and nothing is rolled.
      def self.immune?(traits, out, target)
        found = target ? IWR.immune_to_effect?(IWR.for(target.holder), traits) : nil

        out['lines'] << told('pf2e.act_immune', :target => target.label, :to => found) if found

        !found.nil?
      end

      # Whether someone is on their feet: a creature with hit points left, a character not yet dying -
      # and how near death a dying one is.
      def self.still_up(holder)
        fresh = holder.class[holder.id] || holder

        Actors.of(fresh).creature? ? fresh.hp_left.to_i.positive? : Pf2e.condition_level(fresh, 'Dying')
      end

      # What a hit that settled a character's fate is told as.
      FATES = { :dead => 'pf2e.act_dead', :spared => 'pf2e.act_spared' }.freeze

      # The room is told when a hit drops someone: a creature is down, a character dying or nearer
      # death - or dead, or spared it, which is the `fate` the damage answered with.
      def self.dropped(whom, standing, out, fate = nil)
        now = still_up(whom.holder)

        if FATES[fate]
          out['lines'] << told(FATES[fate], :target => whom.label)
        elsif standing == true && now == false
          out['lines'] << told('pf2e.act_down', :target => whom.label)
          offered_when_down(whom.holder).each do |name|
            out['lines'] << told('pf2e.act_follow_up', :effect => name, :command => "+e/as ##{whom.holder.number}=act #{name.downcase}")
          end
        elsif standing.is_a?(Integer) && now.is_a?(Integer) && now > standing
          out['lines'] << told('pf2e.act_dying', :target => whom.label, :value => now)
        else
          return
        end

        # Whoever has dropped holds nobody any longer.
        out['lines'].concat(Holding.let_go(Gm.encounter_of(whom.holder), whom.label))
      end

      # A character's attacks by what they would call them: the weapons they have equipped, their
      # unarmed attacks, and what a feat or an item granted. A creature's are its Strikes.
      def self.attacks_of(holder)
        Actors.of(holder).attacks
      end

      def self.attack_for(holder, term, melee: false)
        listed = attacks_of(holder)
        listed = listed.reject { |_, attack| attack['ranged'] } if melee

        return listed.first&.last if term.to_s.strip.empty?

        wanted = Domains.slug(term)

        (listed.find { |names, _| names.any? { |one| Domains.slug(one) == wanted } } ||
          listed.find { |names, _| names.any? { |one| Domains.slug(one).include?(wanted) } })&.last
      end

      # ------------------------------------------------------------------------------
      # Spells

      # A spell cast at one or more targets. `cast` is what the caster's magic answered when the slot was
      # spent - the rank and the casting figures - or, for a creature, its spellcasting.
      # What stops a spell before it is spent: a caster restrained cannot cast one that takes their hands,
      # and one grabbed loses it on a failed flat check. Answers the refusal, the report of a spell lost,
      # or nothing where it is cast.
      def self.casting_stopped(scene, spell)
        name, mechanics = spell_mechanics(spell)
        traits = Array((mechanics || {})['traits'])
        traits = Array((Global.read_config('pf2e_spells', name) || {})['traits']) if traits.empty?

        stopped = Restraints.refusal(scene.actor, name, traits)
        return stopped if stopped

        risked = Restraints.risked(scene.actor, name, traits)
        return nil if risked.nil? || risked['kept']

        out = report
        out['lines'] << risked['line']
        TurnState.spend(scene.actor.holder, name, :cost => ((mechanics || {})['time'] || 2).to_i.clamp(1, 3), :type => 'action')

        Ok.new(:state => out)
      end

      def self.cast(scene, spell, targets, words, cast: nil)
        said = said(words, scene.permitted)
        out = report
        refused(out, said)
        spell, base = spell_mechanics(spell)
        named = base && variant(base, said)
        mechanics = named
        rank = spell_rank(scene.actor.holder, spell, mechanics, said, cast)
        casting = Actors.of(scene.actor.holder).casting(spell, cast)

        out['lines'] << told('pf2e.act_cast', :actor => scene.actor.label, :spell => spell, :rank => rank,
                                           :targets => targets.map(&:label).join(', ').then { |one| one.empty? ? '' : " at #{one}" })

        unless mechanics
          out['lines'] << told('pf2e.act_spell_gm')
          return Ok.new(:state => out)
        end

        attack = mechanics['attack']
        dc = casting ? spell_figure(scene.actor.holder, 'spell_dc', casting) : nil

        targets.each do |target|
          each = Scene.new(scene.encounter, scene.actor, target, scene.enactor, scene.permitted)
          mechanics = (named.equal?(base) ? way_for(base, target) : named).merge('cast_rank' => rank)
          attack = mechanics['attack']
          out['about'] = DamageAbout.of_spell(mechanics)

          next if immune?(mechanics['traits'], out, target)
          formulas = Adjustments.spell_damage(scene.actor.holder, mechanics, spell_damage(mechanics, rank))

          if attack
            spell_attack(each, spell, mechanics, casting, formulas, said, out)
          elsif mechanics['save']
            spell_save(each, spell, mechanics, dc, formulas, out)
          elsif formulas.any?
            spell_unopposed(each, mechanics, formulas, out)
          elsif mechanics['applies'] && each.target
            consequences(each, Array(mechanics['applies']).map { |one| one.merge('on' => 'target') }, out)
          else
            spell_effect(each, spell, rank, out)
          end
        end

        spell_effect(scene, spell, rank, out) if targets.empty? && !named['attack'] && !named['save']

        spend_casting(scene.actor.holder, spell, named['time'], named['attack'])

        Ok.new(:state => out)
      end

      # A spell cast another way - Heal with two actions and at range, Needle Darts of silver - as the
      # spell with that way's fields over its own. Chosen by how many actions it is cast with
      # (`/actions 2`), or by a word of the variant's name; without either, the spell as it stands.
      def self.variant(mechanics, said)
        variants = Array(mechanics['variants'])

        chosen = variants.find { |one| said['actions'] && one['time'].to_s == said['actions'].to_s } ||
                 variants.find { |one| said['words'].any? { |word| Domains.slug(one['name']).include?(Domains.slug(word)) } }

        return mechanics unless chosen

        mechanics.merge(chosen.reject { |field, _| field == 'name' }).merge('name' => chosen['name'])
      end

      # A spell cast one way against the undead and another for anyone else - Lay on Hands - cast without
      # saying which, is cast the way its target calls for.
      def self.way_for(mechanics, target)
        variants = Array(mechanics['variants'])
        undead = variants.find { |one| one['name'].to_s.match?(/undead/i) }

        return mechanics unless undead

        chosen = Effects.facts(target.holder).include?('self:mode:undead') ? undead : (variants - [ undead ]).first

        chosen ? mechanics.merge(chosen.reject { |field, _| field == 'name' }).merge('name' => chosen['name']) : mechanics
      end

      # Whether the caster has to say which way they cast a spell before it is spent: where the way decides
      # the kind of damage it deals, as Gouging Claw's slashing or piercing does, cast without one it
      # would deal damage of no kind; and where only its ways deal any, as Elemental Breath's elements do.
      def self.way_needed(spell, words)
        name, mechanics = spell_mechanics(spell)
        ways = Array((mechanics || {})['variants']).select { |one| one['name'] }
        untyped = Array((mechanics || {})['damage']).any? { |one| one['type'].to_s == 'untyped' }
        # Only its ways deal anything, and its target does not decide which.
        ways_only = Array((mechanics || {})['damage']).empty? && ways.any? { |one| Array(one['damage']).any? } &&
                    ways.none? { |one| one['name'].to_s.match?(/undead/i) }

        return Ok.new(:state => nil) if ways.empty? || !(untyped || ways_only)

        chosen = variant(mechanics, said(words, false))

        return Ok.new(:state => chosen['name']) unless chosen.equal?(mechanics)

        Err.new(:way_needed, 'pf2e.cast_way_needed', 'spell' => name,
                'ways' => ways.map { |one| one['name'][/\(([^)]+)\)/, 1] || one['name'] }.join(', '))
      end

      # How much of a spell's damage an outcome deals. A basic save is the basic scale; any other save
      # says in its own text what each outcome does, and an outcome whose text says nothing is the GM's
      # to apply.
      def self.damage_factor(mechanics, degree)
        return DamageRoll::BASIC.fetch(degree, 1) if mechanics['basic']

        (mechanics['damage_scale'] || {})[Degree::NAMES[degree]]
      end

      # The spell by its own name, and what it does: `[ 'Fear', { … } ]`, or the name as typed and nothing.
      # A spell's casting time is its cost: `2` is two actions, `1 to 3` counts the least, a reaction
      # spends the reaction, and anything longer is not cast in a turn.
      def self.spend_casting(holder, spell, time, attack)
        kind = time.to_s.match?(/reaction/i) ? 'reaction' : 'action'
        cost = time.to_s[/\A\d+/].to_i
        cost = 0 if time.to_s.match?(/minute|hour|day/i)

        TurnState.spend(holder, spell, :cost => cost, :type => kind, :attack => !!attack)
      end

      # A creature's stat block lists a spell with how it is cast after its name - `Fly (Constant)`,
      # `Charm (At Will)` - and the spell is the name before that.
      def self.spell_mechanics(spell)
        catalogue = Global.read_config('pf2e_spell_mechanics') || {}
        named = [ spell.to_s.strip, spell.to_s.sub(/\s*\([^)]*\)\s*\z/, '').strip ].uniq

        named.filter_map { |one| catalogue.find { |name, _| name.casecmp?(one) } }.first || [ spell, nil ]
      end

      # The rank a spell is cast at: what the caster said, what the slot was, or its own; a cantrip is half
      # the caster's level, rounded up.
      def self.spell_rank(holder, spell, mechanics, said, cast)
        return said['rank'] if said['rank']

        slot = cast && cast['spell level'].to_s
        return slot.split('/').last.to_i if slot && slot.include?('/')
        return slot.to_i if slot && slot.to_i.positive?

        listed = Actors.of(holder).listed_spell_rank(spell)
        return listed if listed

        return (holder.pf2_level / 2.0).ceil.clamp(1, 10) if mechanics && mechanics['rank'].to_i.zero?

        (mechanics && mechanics['rank']).to_i.clamp(1, 10)
      end

      # A spell's damage at a rank, heightened: an interval adds its damage each step above the spell's own
      # rank, and a fixed heightening replaces it at the highest rank reached.
      def self.spell_damage(mechanics, rank)
        base = [ mechanics['rank'].to_i, 1 ].max
        formulas = Array(mechanics['damage']).map { |one| [ one['formula'], one['type'], one['category'], one['kinds'] ] }
        heightened = mechanics['heightening'] || {}

        if heightened['interval']
          steps = [ (rank - base) / heightened['interval'].to_i, 0 ].max
          formulas = formulas.each_with_index.map do |(formula, *rest), index|
            added = Array(heightened['damage'])[index]
            [ DamageRoll.summed(([ formula ] + ([ added ] * (added ? steps : 0))).join('+')), *rest ]
          end
        elsif heightened['fixed']
          reached = heightened['fixed'].keys.map(&:to_i).select { |one| one <= rank }.max
          if reached
            replaced = heightened['fixed'][reached.to_s]
            formulas = formulas.each_with_index.map { |(formula, *rest), index| [ replaced[index] || formula, *rest ] }
          end
        end

        formulas
      end

      def self.spell_figure(holder, kind, casting)
        figure = Actors.of(holder).figure(kind, casting)

        figure ? figure['total'].to_i : nil
      end

      # A spell attack's outcomes are the attack's own: Briny Bolt's critical hit blinds what it hits.
      def self.spell_attack(scene, spell, mechanics, casting, formulas, said, out)
        options = TurnState.map_options(scene.actor.holder) + options_for(scene, said) + [ 'action:cast-a-spell' ]
        check = Check.of(scene.actor.holder, 'spell_attack', casting || {}, options)
        extra = attack_penalty(scene.actor.holder)

        rolled = attack_roll(scene, { 'name' => spell }, check, said, extra, out)
        out['lines'] << rolled['line']

        if rolled['hit'] && formulas.any?
          critical = rolled['result']['degree'] == Degree::CRITICAL_SUCCESS
          rows = DamageRoll.of_formulas(formulas.map { |formula, type, category, _| [ formula, type, category ] }, critical)
          deal(scene, scene.target, rows, out, :critical => critical)
        end

        degree = rolled.dig('result', 'degree')
        outcome(scene, mechanics, degree, formulas, out) if degree
      end

      # A save against the caster's DC, rolled by each target: a basic save scales the damage, and any
      # save leaves what its outcome says.
      def self.spell_save(scene, spell, mechanics, dc, formulas, out)
        target = scene.target
        save = mechanics['save']

        unless dc
          out['lines'] << told('pf2e.act_save_gm', :target => target.label, :save => save.capitalize)
          return
        end

        check = Check.of(target.holder, 'save', save, Resolve.seen_as(scene.actor.holder, 'origin') + Array(mechanics['traits']))
        # Standard or greater cover helps a Reflex save against an area.
        extra = save == 'reflex' && mechanics['area'] ? [ Resolve.cover_modifier(cover_of(scene, {}), 'reflex') ].compact : []
        spared = Incapacitation.spares?(mechanics['traits'], target.holder, :rank => mechanics['cast_rank'],
                                                                           :source => scene.actor.holder)
        result = Resolve.roll(check, :dc => dc, :extra => extra, :shift => Incapacitation.shift(spared, :theirs))

        out['lines'] << told('pf2e.act_save_line', :target => target.label, :save => save.capitalize,
                                                :roll => Telling.roll(result), :dc => dc,
                                                :degree => Telling.degree(result['degree'], false))
        out['lines'] << told('pf2e.act_incapacitation', :target => target.label) if spared
        out['detail'] += detail_lines("#{target.label}'s #{save}", save, result, nil)

        heal_or_hurt(scene, mechanics, formulas, result['degree'], out) if formulas.any?

        outcome(scene, mechanics, result['degree'], formulas, out)

        result['degree']
      end

      # What an outcome leaves on the target. Where it leaves nothing the engine can set and deals no
      # damage, its own words are told, so the room knows what Command's failure makes the target do.
      def self.outcome(scene, mechanics, degree, formulas, out)
        named = Degree::NAMES[degree]
        held = Array((mechanics['outcomes'] || {})[named])

        consequences(scene, held.map { |one| one.merge('on' => 'target') }, out)

        words = (mechanics['outcome_text'] || {})[named]
        out['lines'] << told('pf2e.act_outcome_words', :words => words) if words && held.empty? && formulas.empty?
      end

      # Damage that heals the living and hurts the undead, or the reverse, by the spell's vitality or void.
      def self.heal_or_hurt(scene, mechanics, formulas, degree, out)
        heals = formulas.select { |_f, _t, _c, kinds| Array(kinds).include?('healing') }
        mode = Effects.facts(scene.target.holder).find { |one| one.start_with?('self:mode:') }.to_s.split(':').last
        traits = Array(mechanics['traits'])
        hurts_this = (traits.include?('vitality') && mode == 'undead') || (traits.include?('void') && mode != 'undead')

        if heals.any? && !hurts_this
          amount = heals.sum { |formula, *_| Pf2e.roll_formula(formula) }
          Harm.heal(scene.target.holder, amount)
          out['lines'] << told('pf2e.act_healed', :target => scene.target.label, :count => amount)
          return
        end

        factor = degree ? damage_factor(mechanics, degree) : 1

        if factor.nil?
          shown = formulas.map { |formula, type, *_| "#{formula} #{type}" }.join(' + ')
          return out['lines'] << told('pf2e.act_spell_damage_gm', :target => scene.target.label, :damage => shown)
        end

        rows = DamageRoll.of_formulas(formulas.map { |f, type, category, _| [ f, type, category ] }, false)
        rows = rows.filter_map do |row|
          next row.merge('amount' => (row['amount'] * factor).floor) unless row['category'].to_s == 'persistent'

          scaled = Pf2e.scaled_formula(row['formula'], factor)
          scaled && row.merge('formula' => scaled)
        end
        deal(scene, scene.target, rows, out, :critical => degree == Degree::CRITICAL_FAILURE)
      end

      # Damage with no attack and no save: it lands.
      def self.spell_unopposed(scene, mechanics, formulas, out)
        heal_or_hurt(scene, mechanics, formulas, nil, out)
      end

      # A spell that puts an effect on whoever it is cast at, where the effect catalogue holds one of its
      # name: Heroism is Spell Effect: Heroism.
      def self.spell_effect(scene, spell, rank, out)
        found = ActiveEffects.catalogue.key?("Spell Effect: #{spell}") ? "Spell Effect: #{spell}" : nil

        return out['lines'] << told('pf2e.act_spell_gm') unless found

        whom = scene.target || scene.actor
        applied = ActiveEffects.apply(whom.holder, found, :options => [ "rank #{rank}" ], :applied_by => scene.actor.label,
                                                          :encounter => scene.encounter)

        return if applied.err?

        out['lines'] << told('pf2e.act_now_under', :target => whom.label, :effect => found,
                                                :lasts => ActiveEffects.remaining(applied.state))
      end

      # ------------------------------------------------------------------------------
      # Consequences

      # What an outcome does, done: each on the target or on the actor. `rank` is the actor's proficiency
      # in what they rolled, which Aid's bonus grows with.
      def self.consequences(scene, list, out, rank: 'trained', dc: nil, options: [])
        list.each do |one|
          whom = one['on'] == 'actor' ? scene.actor : scene.target

          next unless whom

          if one['condition'] then condition_consequence(scene, whom, one, out)
          elsif one['remove'] then removal_consequence(scene, whom, one, out)
          elsif one['effect'] then effect_consequence(scene, whom, one, rank, out)
          elsif one['heal']
            amount = Pf2e.roll_formula(one['heal']) + (one['bonus'] || {})[dc.to_s].to_i
            Harm.heal(whom.holder, amount, options)
            out['lines'] << told('pf2e.act_healed', :target => whom.label, :count => amount)
            out['gm'] << told('pf2e.act_hp_left', :target => whom.label, :hp => Harm.hit_points(whom.holder))
          elsif one['damage']
            deal(scene, whom, [ { 'amount' => Pf2e.roll_formula(one['damage']), 'type' => one['type'],
                                  'formula' => one['damage'] } ], out)
          elsif one['persistent']
            PersistentDamage.remove(whom.holder, one['persistent'])
            out['lines'] << told('pf2e.act_persistent_ended', :target => whom.label, :type => one['persistent'])
          end
        end
      end

      # A condition set. One already held at a higher value stays at it, which is the rule for gaining a
      # condition you have.
      def self.condition_consequence(scene, whom, one, out)
        name = Pf2e.canonical_condition(one['condition'])
        before = (whom.holder.pf2_conditions || {})[name]
        before_value = before.is_a?(Hash) ? before['value'] : nil
        value = one['value'] ? [ one['value'].to_i, before_value.to_i ].max : nil

        return if before && (value.nil? || value == before_value.to_i)

        if Gm.spared?(whom.holder, name, scene.actor.label)
          return out['lines'] << told('pf2e.act_not_lasting', :target => whom.label, :condition => name)
        end

        set = Pf2e.set_condition(whom.holder, name, value || Pf2e.default_condition_value(name))
        return out['lines'] << told(set.key, set.args) if set.err?

        ends = scene.encounter && one['until'] ? Turns.expiry_for(one['until'], scene.encounter, scene.actor.label, whom.label) : nil
        expire_at(whom.holder, name, ends) if ends
        Holding.mark(whom.holder, name, scene.actor.label) unless whom.label == scene.actor.label

        shown = value ? "#{name} #{value}" : name
        timed_by = one['until'].to_s.start_with?('its-') ? whom.label : scene.actor.label
        out['lines'] << told('pf2e.act_now', :target => whom.label, :condition => shown,
                                          :until => ends ? until_phrase(one['until'].to_s.delete_prefix('its-'), timed_by) : '')
      end

      # ` until the end of Aria's next turn`, ` for 10 rounds`.
      def self.until_phrase(until_when, actor)
        rounds = until_when.to_s[/\Arounds:(\d+)\z/, 1]

        return told(rounds == '1' ? 'pf2e.until_one_round' : 'pf2e.until_rounds', :rounds => rounds) if rounds

        told("pf2e.until_#{until_when.to_s.tr('-', '_')}", :actor => actor)
      end

      def self.expire_at(holder, name, ends)
        list = holder.pf2_conditions || {}

        return unless list[name].is_a?(Hash)

        list[name] = list[name].merge('expires' => ends)
        holder.update(:pf2_conditions => list)
      end

      # What an outcome takes off someone. A hold on a target is only the holder's own to lose: a failed
      # Grapple does not shake loose what another creature holds.
      def self.removal_consequence(scene, whom, one, out)
        held = whom.holder.pf2_conditions || {}
        theirs = one['on'] == 'target' ? Holding.by(whom.holder) : nil

        Array(one['remove']).map { |name| Pf2e.canonical_condition(name) }.select { |name| held.key?(name) }.each do |name|
          next if Holding::HOLDS.include?(name) && theirs && theirs != scene.actor.label

          value = held[name].is_a?(Hash) ? held[name]['value'] : nil
          removed = Pf2e.remove_condition(whom.holder, name)

          next out['lines'] << told(removed.key, removed.args) if removed.err?

          out['lines'] << told('pf2e.act_no_longer', :target => whom.label, :condition => name)
        end
      end

      def self.effect_consequence(scene, whom, one, rank, out)
        answer = one['answer'].is_a?(Hash) ? (one['answer'][rank] || one['answer']['default']) : one['answer']
        applied = ActiveEffects.apply(whom.holder, one['effect'], :options => [ answer ].compact,
                                                                  :applied_by => scene.actor.label,
                                                                  :encounter => scene.encounter)

        return out['lines'] << told(applied.key, applied.args) if applied.err?

        out['lines'] << told('pf2e.act_now_under', :target => whom.label, :effect => applied.state.name,
                                                :lasts => ActiveEffects.remaining(applied.state))
      end

      # ------------------------------------------------------------------------------
      # Counting and telling

      # The action is counted against the actor's turn, and a limit on how often it may be used is shown
      # when it has been reached - shown, not refused.
      def self.spend(scene, name, entry, out)
        holder = scene.actor.holder
        frequency = entry['frequency']
        before = TurnState.used(holder, name)

        TurnState.spend(holder, entry['label'] || name, :cost => entry['cost'] || 1, :type => entry['type'] || 'action',
                                      :attack => Array(entry['traits']).include?('attack') && !entry['no_map'],
                                      :frequency => frequency)

        return unless frequency && before >= frequency['max'].to_i

        out['lines'] << told('pf2e.act_frequency_reached', :action => name, :max => frequency['max'],
                                                        :per => frequency['per'], :used => before + 1)
      end

      def self.refused(out, said)
        return if said['refused'].empty?

        out['lines'] << told('pf2e.act_cover_refused', :words => said['refused'].join(', '))
      end


      def self.check_line(scene, name, statistic, result, check, defence, dc)
        roll = Telling.roll(result)

        if defence
          told('pf2e.act_check_line', :actor => scene.actor.label, :action => name, :target => scene.target.label,
                                   :statistic => statistic, :roll => roll, :defence => defence_name(check['against']),
                                   :dc => dc, :degree => Telling.degree(result['degree'], false))
        elsif dc
          told('pf2e.act_check_dc_line', :actor => scene.actor.label, :action => name, :statistic => statistic,
                                      :roll => roll, :dc => dc, :degree => Telling.degree(result['degree'], false),
                                      :target => target_phrase(scene))
        elsif check['against']
          told('pf2e.act_check_gm_line', :actor => scene.actor.label, :action => name, :statistic => statistic,
                                      :roll => roll, :defence => defence_name(check['against']))
        else
          told('pf2e.act_check_open_line', :actor => scene.actor.label, :action => name, :statistic => statistic,
                                        :roll => roll)
        end
      end

      def self.defence_name(against)
        against.to_s.downcase == 'ac' ? 'AC' : "#{against.to_s.capitalize} DC"
      end

      # Every modifier of a roll and of the defence it was against, for `+e/why`.
      # The roll and what it was against, each from its number before modifiers and then each modifier;
      # one with no modifiers ends where its number does.
      def self.detail_lines(what, statistic, result, defence)
        lines = [ told('pf2e.why_roll', :what => what, :statistic => statistic, :roll => Telling.roll(result),
                                        :base => based(result['breakdown']), :tail => tail(result['breakdown'])) ]
        lines += modifier_lines(result['breakdown'])

        if defence
          plain = Array(defence['breakdown']['modifiers']).empty? && !defence['breakdown']['basis'] &&
                  defence['breakdown']['base'].to_i == defence['dc'].to_i
          lines << (plain ? told('pf2e.why_defence_plain', :defence => defence_word(defence), :dc => defence['dc']) :
                            told('pf2e.why_defence', :defence => defence_word(defence), :dc => defence['dc'],
                                                     :base => based(defence['breakdown']), :tail => tail(defence['breakdown'])))
          lines += modifier_lines(defence['breakdown'])
        end

        lines
      end

      # `15 (expert, level 11)`: the base, and what it is made of where that is known.
      def self.based(breakdown)
        basis = breakdown['basis']

        basis ? "#{breakdown['base']} (#{basis})" : breakdown['base'].to_s
      end

      def self.tail(breakdown)
        Array(breakdown['modifiers']).empty? ? '.' : ':'
      end

      # `AC`, `Will DC`, `Athletics DC`.
      def self.defence_word(defence)
        return 'AC' if defence['kind'] == 'ac'

        "#{(defence['name'] || defence['kind']).to_s.split.map(&:capitalize).join(' ')} DC"
      end

      def self.modifier_lines(breakdown)
        Array(breakdown['modifiers']).map do |row|
          value = row['value'].to_i

          told(row['enabled'] ? 'pf2e.why_modifier' : 'pf2e.why_modifier_off',
               :value => "#{value.negative? ? '' : '+'}#{value}", :type => row['type'], :source => row['source'])
        end
      end

      # What happened, as an event: a locale key and its arguments, for whoever tells it to render.
      def self.told(key, args = {})
        Telling.event(key, args)
      end
    end
  end
end
