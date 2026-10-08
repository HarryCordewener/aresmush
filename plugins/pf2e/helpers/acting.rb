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
      Scene = Struct.new(:encounter, :actor, :target, :enactor, :permitted)

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
          said['flanking'] && against.to_s == 'ac' ? Resolve::FLANKED : nil ].compact
      end

      # ------------------------------------------------------------------------------
      # Actions

      def self.act(scene, term, words)
        follow = Actors.of(scene.actor.holder).follow_up(term)
        name = follow ? follow['action'] : action_named(scene, term)

        return name if name.is_a?(Err)

        return strike(scene, nil, words) if name == 'Strike'

        entry = Actions.info(name)
        entry = follow_up_entry(entry, follow, term) if follow
        said = said(words, scene.permitted)
        out = report
        refused(out, said)

        # A creature's own ability, which no catalogue holds.
        return announce_ability(scene, name, out) if entry.empty?

        if entry['check']
          check_action(scene, name, entry, said, out)
        elsif entry['self_effect']
          self_action(scene, name, entry, said, out)
        else
          out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => name,
                                                  :cost => Actions.cost(name), :target => target_phrase(scene))
        end

        spend(scene, name, entry, out)

        Ok.new(:state => out)
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

      # A creature's ability that no catalogue holds: its stat block's words, for the GM to run.
      def self.announce_ability(scene, name, out)
        own = Actors.of(scene.actor.holder).own_ability(name) || {}
        cost = own['type'] == 'action' ? Actions::COSTS[own['cost'].to_i] || 'one action' : Actions::TYPES[own['type']]

        out['lines'] << told('pf2e.act_announced', :actor => scene.actor.label, :action => name, :cost => cost,
                                                :target => target_phrase(scene))
        out['lines'] << told('pf2e.act_note', :text => own['text']) if own['text']

        TurnState.spend(scene.actor.holder, name, :cost => own['cost'] || 1, :type => own['type'] || 'action',
                                                  :attack => Array(own['traits']).include?('attack'))

        Ok.new(:state => out)
      end

      def self.target_phrase(scene)
        scene.target ? told('pf2e.act_at', :target => scene.target.label) : ''
      end

      # An action that puts an effect on whoever uses it: Rage, Take Cover, a stance.
      # What is said after the action's name reaches its effect: the rank it is at, a counter, an answer
      # to what it asks - `action/use rage` and `+e/act raise a shield` are the same command.
      def self.self_action(scene, name, entry, said, out)
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
      end

      # What was said about an effect, in the words `ActiveEffects.apply` takes: `rank 6`, `value 3`, and
      # an answer to what it asks.
      def self.effect_options(said)
        (said['rank'] ? [ "rank #{said['rank']}" ] : []) + said['words']
      end

      # An action whose check is rolled against something: a target's defence, or a DC.
      def self.check_action(scene, name, entry, said, out)
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

        result = Resolve.roll(rolled_check, :dc => dc, :extra => extra)
        statistic = stat_name ? stat_name.to_s : kind.capitalize

        out['lines'] << check_line(scene, name, statistic, result, check, defence, dc)
        out['detail'] += detail_lines(name, statistic, result, defence)

        return unless result['degree']

        outcome = Degree::NAMES[result['degree']]
        note = (check['notes'] || {})[outcome]
        out['lines'] << told('pf2e.act_note', :text => note) if note

        rolled_check.notes(result['degree']).each { |one| out['lines'] << told('pf2e.act_note', :text => one['text']) if one['text'] }

        consequences(scene, Array(Actions.consequences(slug, check['variant'])[outcome]), out,
                     :rank => rank_of(scene.actor.holder, kind, stat_name))
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

      # ------------------------------------------------------------------------------
      # Strikes

      def self.strike(scene, weapon_term, words)
        said = said(words, scene.permitted)
        out = report
        refused(out, said)

        return Err.new(:no_target, 'pf2e.act_needs_target') unless scene.target

        attack = attack_for(scene.actor.holder, weapon_term)

        return Err.new(:no_attack, 'pf2e.act_no_attack', 'attack' => weapon_term.to_s) unless attack

        # Range increments are a ranged or thrown attack's; a melee Strike ignores them.
        increments = attack['ranged'] || Pf2e.has_trait?(attack['traits'], 'thrown') ? said['range'].to_i : 0
        said = said.merge('range' => increments)
        return Err.new(:out_of_range, 'pf2e.act_out_of_range') if increments > 6

        options = TurnState.map_options(scene.actor.holder) + options_for(scene, said, 'strike') + [ 'action:strike' ]
        check = Check.of(scene.actor.holder, 'attack', attack, options)
        extra = increments > 1 ? [ { 'source' => "range increment #{increments}", 'slug' => 'range-penalty',
                                     'type' => 'untyped', 'value' => -2 * (increments - 1) } ] : []

        rolled = attack_roll(scene, attack, check, said, extra, out)
        out['lines'] << rolled['line']

        if rolled['hit']
          hit(scene, attack, check, rolled['result'], out)
        elsif attack['bomb'] && rolled.dig('result', 'degree') == Degree::FAILURE
          splash(scene, attack, check, out)
        end

        # A bomb is thrown whatever it does.
        Consumables.spend!(scene.actor.holder, attack['consumable']) if attack['consumable']

        TurnState.spend(scene.actor.holder, 'Strike', :cost => 1, :type => 'action', :attack => true)

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
        parts << told('pf2e.act_nth_attack', :nth => [ attacks + 1, 3 ].min == 2 ? '2nd' : '3rd') if attacks.positive?
        parts << told('pf2e.act_flanking') if said['flanking']
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
        rows = Actors.of(scene.actor.holder).strike_damage(attack, check, critical)

        deal(scene, scene.target, rows, out, :critical => critical)

        Consumables.effect(scene.encounter, scene.actor.label, scene.target, attack['effect'], out) if attack['bomb'] && attack['effect']

        follow_ups(scene, attack, out)

        critical_specialization(scene, attack, out) if critical
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
        immediate, persistent = rows.partition { |row| row['category'].to_s != 'persistent' }
        shown = []

        immediate.each do |row|
          held = Harm.damage(whom.holder, row['amount'], row['type'], :critical => critical)
          resisted = Array(held['applied']).map { |one| one['category'] == 'immunity' ? 'immune' : "#{one['category']} #{one['adjustment']}" }
          kind = row['category'].to_s == 'splash' ? "splash #{row['type']}" : row['type']
          shown << "#{held['amount']} #{kind}#{resisted.empty? ? '' : " (#{resisted.join(', ')})"}"
        end

        # Words already, because they join the rest of the hit in one line.
        persistent.each do |row|
          PersistentDamage.add(whom.holder, row['formula'], row['type'])
          shown << Telling.value(told('pf2e.act_persistent', :formula => row['formula'], :type => row['type']))
        end

        return if shown.empty?

        out['lines'] << told('pf2e.act_damage', :damage => shown.join(' + '), :target => whom.label)
        out['gm'] << told('pf2e.act_hp_left', :target => whom.label, :hp => Harm.hit_points(whom.holder))
      end

      # A character's attacks by what they would call them: the weapons they have equipped, their
      # unarmed attacks, and what a feat or an item granted. A creature's are its Strikes.
      def self.attacks_of(holder)
        Actors.of(holder).attacks
      end

      def self.attack_for(holder, term)
        listed = attacks_of(holder)

        return listed.first&.last if term.to_s.strip.empty?

        wanted = Domains.slug(term)

        (listed.find { |names, _| names.any? { |one| Domains.slug(one) == wanted } } ||
          listed.find { |names, _| names.any? { |one| Domains.slug(one).include?(wanted) } })&.last
      end

      # ------------------------------------------------------------------------------
      # Spells

      # A spell cast at one or more targets. `cast` is what the caster's magic answered when the slot was
      # spent - the rank and the casting figures - or, for a creature, its spellcasting.
      def self.cast(scene, spell, targets, words, cast: nil)
        said = said(words, scene.permitted)
        out = report
        refused(out, said)
        spell, mechanics = spell_mechanics(spell)
        mechanics = variant(mechanics, said) if mechanics
        rank = spell_rank(scene.actor.holder, spell, mechanics, said, cast)
        casting = Actors.of(scene.actor.holder).casting(spell, cast)

        out['lines'] << told('pf2e.act_cast', :actor => scene.actor.label, :spell => spell, :rank => rank,
                                           :targets => targets.map(&:label).join(', ').then { |one| one.empty? ? '' : " at #{one}" })

        unless mechanics
          out['lines'] << told('pf2e.act_spell_gm')
          return Ok.new(:state => out)
        end

        attack = mechanics['attack']
        formulas = spell_damage(mechanics, rank)
        dc = casting ? spell_figure(scene.actor.holder, 'spell_dc', casting) : nil

        targets.each do |target|
          each = Scene.new(scene.encounter, scene.actor, target, scene.enactor, scene.permitted)

          if attack
            spell_attack(each, spell, mechanics, casting, formulas, said, out)
          elsif mechanics['save']
            spell_save(each, spell, mechanics, dc, formulas, out)
          elsif formulas.any?
            spell_unopposed(each, mechanics, formulas, out)
          else
            spell_effect(each, spell, rank, out)
          end
        end

        spell_effect(scene, spell, rank, out) if targets.empty? && !attack && !mechanics['save']

        spend_casting(scene.actor.holder, spell, mechanics['time'], attack)

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

      # Whether the caster has to say which way they cast a spell before it is spent: where the way decides
      # the kind of damage it deals, as Gouging Claw's slashing or piercing does, cast without one it
      # would deal damage of no kind.
      def self.way_needed(spell, words)
        name, mechanics = spell_mechanics(spell)
        ways = Array((mechanics || {})['variants']).select { |one| one['name'] }
        untyped = Array((mechanics || {})['damage']).any? { |one| one['type'].to_s == 'untyped' }

        return Ok.new(:state => nil) if ways.empty? || !untyped

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

      def self.spell_mechanics(spell)
        catalogue = Global.read_config('pf2e_spell_mechanics') || {}

        catalogue.find { |name, _| name.casecmp?(spell.to_s.strip) } || [ spell, nil ]
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
        result = Resolve.roll(check, :dc => dc, :extra => extra)

        out['lines'] << told('pf2e.act_save_line', :target => target.label, :save => save.capitalize,
                                                :roll => Telling.roll(result), :dc => dc,
                                                :degree => Telling.degree(result['degree'], false))
        out['detail'] += detail_lines("#{target.label}'s #{save}", save, result, nil)

        heal_or_hurt(scene, mechanics, formulas, result['degree'], out) if formulas.any?

        outcome(scene, mechanics, result['degree'], formulas, out)
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
          out['lines'] << told('pf2e.act_healed', :target => scene.target.label, :amount => amount)
          return
        end

        factor = degree ? damage_factor(mechanics, degree) : 1

        if factor.nil?
          shown = formulas.map { |formula, type, *_| "#{formula} #{type}" }.join(' + ')
          return out['lines'] << told('pf2e.act_spell_damage_gm', :target => scene.target.label, :damage => shown)
        end

        rows = DamageRoll.of_formulas(formulas.map { |f, type, category, _| [ f, type, category ] }, false)
        rows = rows.map { |row| row.merge('amount' => (row['amount'] * factor).floor) }
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
      def self.consequences(scene, list, out, rank: 'trained')
        list.each do |one|
          whom = one['on'] == 'actor' ? scene.actor : scene.target

          next unless whom

          if one['condition'] then condition_consequence(scene, whom, one, out)
          elsif one['remove'] then removal_consequence(whom, one, out)
          elsif one['effect'] then effect_consequence(scene, whom, one, rank, out)
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

        set = Pf2e.set_condition(whom.holder, name, value || Pf2e.default_condition_value(name))
        return out['lines'] << told(set.key, set.args) if set.err?

        ends = scene.encounter && one['until'] ? Turns.expiry_for(one['until'], scene.encounter, scene.actor.label, whom.label) : nil
        expire_at(whom.holder, name, ends) if ends

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

      def self.removal_consequence(whom, one, out)
        held = whom.holder.pf2_conditions || {}

        Array(one['remove']).map { |name| Pf2e.canonical_condition(name) }.select { |name| held.key?(name) }.each do |name|
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
      def self.detail_lines(what, statistic, result, defence)
        lines = [ told('pf2e.why_roll', :what => what, :statistic => statistic, :roll => Telling.roll(result),
                                        :base => result['breakdown']['base']) ]
        lines += modifier_lines(result['breakdown'])

        if defence
          lines << told('pf2e.why_defence', :dc => defence['dc'], :base => defence['breakdown']['base'])
          lines += modifier_lines(defence['breakdown'])
        end

        lines
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
