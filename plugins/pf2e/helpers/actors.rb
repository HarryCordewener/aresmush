module AresMUSH
  module Pf2e

    # Whoever the engine is working on: a character, or a creature in an encounter.
    #
    # The two answer the same questions differently. A character's figures are built from their sheet;
    # a creature's are its stat block's numbers. A character carries gear, has feats, writes derived
    # values and hears about their own turn; a creature has abilities, is run by the GM and has only its
    # hit points. Foundry has the same split - one actor, with a character and an NPC beneath it.
    #
    # So each is an object answering the engine's questions, and the one place that asks which kind of
    # thing it has is `Actors.of`. Code that works on "whoever" asks the actor; it never asks whether
    # the actor is a creature.
    module Actors

      def self.of(holder)
        return CreatureActor.new(holder) if holder.is_a?(Pf2eNpc)
        return EncounterCharacterActor.new(holder) if holder.is_a?(Pf2eCombatantState)

        CharacterActor.new(holder)
      end
    end

    # What both kinds of actor share.
    class Actor
      attr_reader :holder

      def initialize(holder)
        @holder = holder
      end

      def name
        @holder.name
      end

      # What a Strike rolled with `critical` does, after what the target resists - as rows of damage.
      def strike_damage(_attack, _check, _critical)
        []
      end

      # An ability or a Strike's follow-up that no action catalogue holds, by the name typed.
      def own_ability(_term)
        nil
      end

      def follow_up(_term)
        nil
      end

      def critical_specialization(_attack)
        nil
      end

      def listed_spell_rank(_spell)
        nil
      end
    end

    class CharacterActor < Actor
      def creature?
        false
      end

      # Which side of a fight it is on, which is what decides whether an aura's effect is for an ally or
      # an enemy.
      def side
        'characters'
      end

      # ------------------------------------------------------------------------------
      # What the rules engine reads

      def sources
        Effects.sheet_sources(@holder)
      end

      def options(domains = nil)
        facts + RollOptions.active(@holder, domains)
      end

      def facts
        Effects.sheet_facts(@holder)
      end

      # What is true of it without asking what it is under - which is what those facts are built from.
      def base_facts
        Effects.sheet_character_facts(@holder)
      end

      def context
        Effects.sheet_context(@holder)
      end

      def figure(kind, name = nil, options = [], extra = [])
        Stat.of(@holder, kind, name, options, extra)
      end

      # What alters the things it has: its feats, class features and items as well as what it is under.
      def alteration_sources
        Effects.feats(@holder) + Effects.features(@holder) + Effects.items(@holder)
      end

      def carries_items?
        true
      end

      # A character's rules write derived values to the sheet: Rage's temporary hit points.
      def derives_sheet?
        true
      end

      # What heals it as its turn starts, from any source it has.
      def turn_healing
        context = self.context
        options = self.options

        sources.flat_map do |source|
          Rules.of_kind(source, 'FastHealing').select { |row| Predicate.test(row['predicate'], options) }
                                              .map { |row| Rules.contribute(row, source, context.merge('item' => source['item'] || {})) }
                                              .compact
        end
      end

      # Its abilities' own sources beyond what it is under. A character's auras come from effects.
      def ability_sources
        []
      end

      # ------------------------------------------------------------------------------
      # Hit points

      def damage(amount, kind = nil, is_dm: false, critical: false)
        held = kind ? IWR.apply(IWR.of(@holder), amount.to_i, kind) : { 'amount' => amount.to_i, 'applied' => [] }

        Pf2eHP.modify_damage(@holder, amount.to_i, false, is_dm, kind, [], :critical => critical)

        held
      end

      def heal(amount, options = [])
        Pf2eHP.modify_damage(@holder, amount.to_i, true, false, nil, options)

        amount.to_i
      end

      def hit_points
        @holder.hp ? "#{Pf2eHP.get_current_hp(@holder)} / #{Pf2eHP.get_max_hp(@holder)}" : '---'
      end

      # ------------------------------------------------------------------------------
      # Who hears about it

      # A player is told their own turn has come; a creature's reminder is the GM's.
      def hears_own_turn?
        true
      end

      def notify_damage(amount, source)
        Login.notify person, :pf2_damage, t('pf2e.you_took_damage', :amount => amount, :source => source), 0
      end

      # The player behind it, who is told things.
      def person
        @holder
      end

      # What names it among everyone an aura or a rule might mean.
      def key
        @holder.id.to_s
      end

      def reminder_lines
        []
      end

      # ------------------------------------------------------------------------------
      # Acting

      # Whether it may use a catalogue action: the basic ones, and what its feats and features give it.
      def may_use(name)
        Actions.usable(@holder, name)
      end

      # Its attacks by what a player would call them: the weapons equipped, unarmed attacks, and what a
      # feat or an item granted.
      def attacks
        weapons = Pf2egear::Inventory.held(@holder, 'weapons').select(&:equipped).map do |weapon|
          [ [ weapon.name, weapon.nickname ].compact, Pf2eCombat.attack_descriptor(@holder, weapon) ]
        end

        unarmed = (@holder.combat&.unarmed_attacks || {}).map do |name, info|
          [ [ name ], Pf2eCombat.unarmed_descriptor(name, info, Pf2eCombat.get_unarmed_prof(@holder, name, info), @holder) ]
        end

        bombs = Pf2egear::Inventory.held(@holder, 'consumables').select { |item| Consumables.bomb?(item.name) }.map do |item|
          [ [ item.name ], Pf2eCombat.bomb_descriptor(@holder, item) ]
        end

        weapons + unarmed + Pf2eCombat.granted_strikes(@holder).map { |one| [ [ one['name'] ], one ] } + bombs
      end

      def strike_damage(attack, check, critical)
        degree = critical ? Degree::CRITICAL_SUCCESS : Degree::SUCCESS
        instances = Damage.of(@holder, attack, check.options + [ "check:outcome:#{Degree::SLUGS[degree]}" ])['instances']

        DamageRoll.of_instances(instances, critical, attack)
      end

      def critical_specialization(attack)
        Pf2e.crit_spec_consequences(@holder, attack)
      end

      # Its equipped weapons with any of these traits: a trip weapon lends its rune to Trip.
      def weapons_with_traits(traits)
        Pf2egear::Inventory.held(@holder, 'weapons').select(&:equipped).select do |one|
          (Array(one.traits).map { |trait| Domains.slug(trait) } & Array(traits)).any?
        end
      end

      def proficiency(kind, name)
        kind == 'skill' ? Pf2eSkills.get_skill_prof(@holder, name).to_s.downcase : 'trained'
      end

      # A character's spell is spent through their magic, which answers with the casting; that is it.
      def casting(_spell, cast)
        cast
      end

      def spends_spells?
        true
      end

      # Which record an effect it is under belongs to.
      def effect_owner_field
        :character
      end

      # And which an item it carries belongs to.
      def item_owner_field
        :character
      end
    end

    # A character as they stand in an encounter: the character, with the encounter's state in place of
    # their own (`Pf2eCombatantState`).
    class EncounterCharacterActor < CharacterActor
      def person
        @holder.character
      end

      def key
        "state-#{@holder.id}"
      end

      def effect_owner_field
        :state
      end

      def item_owner_field
        :state
      end
    end

    class CreatureActor < Actor
      def creature?
        true
      end

      def side
        'creatures'
      end

      # ------------------------------------------------------------------------------
      # What the rules engine reads

      def sources
        Npcs.sources(@holder)
      end

      def options(domains = nil)
        Npcs.options(@holder, domains)
      end

      def facts
        Npcs.facts(@holder)
      end

      def base_facts
        [ "self:level:#{@holder.pf2_level}" ] + Effects.named('self:trait', @holder.pf2_traits)
      end

      def context
        Npcs.context(@holder)
      end

      def figure(kind, name = nil, options = [], _extra = [])
        Npcs.stat(@holder, kind, name, options)
      end

      # A creature carries nothing and has no feats; only what it is under alters.
      def alteration_sources
        []
      end

      def carries_items?
        false
      end

      # Its figures are its stat block's; there is no sheet to write to.
      def derives_sheet?
        false
      end

      def turn_healing
        Npcs.healing(@holder)
      end

      def ability_sources
        Npcs.ability_sources(@holder)
      end

      # ------------------------------------------------------------------------------
      # Hit points

      def damage(amount, kind = nil, is_dm: false, critical: false)
        Npcs.damage(@holder, amount, kind)
      end

      def heal(amount, _options = [])
        Npcs.heal(@holder, amount)
      end

      def hit_points
        "#{@holder.hp_left} / #{@holder.max_hp}"
      end

      # ------------------------------------------------------------------------------
      # Who hears about it

      def hears_own_turn?
        false
      end

      def notify_damage(_amount, _source)
      end

      # A creature carries nothing of its own; what it has is its stat block's.
      def item_owner_field
        :character
      end

      # Nobody plays a creature; the GM hears for it.
      def person
        nil
      end

      def key
        "npc-#{@holder.id}"
      end

      # Its Strikes, and the command that makes one.
      # Its Strikes, ready to type - or, with no hit points left, that it has fallen and how to clear it.
      def reminder_lines
        return [ t('pf2e.turn_down', :name => @holder.name, :ref => "##{@holder.number}") ] unless @holder.hp_left.to_i.positive?

        strikes = Npcs.strikes(@holder).map { |one| "#{one['name']} #{StatBlock.signed(one['bonus'])}" }

        strikes.any? ? [ t('pf2e.turn_npc_strikes', :strikes => strikes.join(', '), :ref => "##{@holder.number}") ] : []
      end

      # ------------------------------------------------------------------------------
      # Acting

      # A creature is run by the GM, who may use any action for it.
      def may_use(name)
        Ok.new(:state => name)
      end

      def own_ability(term)
        Array(@holder.stat_block['actions']).find { |one| one['name'].casecmp?(term.to_s.strip) }
      end

      def follow_up(term)
        Acting::FOLLOW_UPS[Domains.slug(term)]
      end

      def attacks
        Npcs.strikes(@holder).map { |one| [ [ one['name'] ], one ] }
      end

      # The stat block's formula for the Strike, and what its rules add to it.
      def strike_damage(attack, check, critical)
        extras = Npcs.strike_damage(@holder, attack, check.options)

        DamageRoll.merged(DamageRoll.of_formulas(attack['damage'], critical, attack) +
                          DamageRoll.of_extras(extras, critical))
      end

      def weapons_with_traits(_traits)
        []
      end

      def proficiency(_kind, _name)
        'trained'
      end

      # Its spellcasting that holds the spell, or the first it has.
      def casting(spell, _cast)
        Npcs.casting(@holder, spell)
      end

      # Its spells are its stat block's, cast as often as the GM says.
      def spends_spells?
        false
      end

      # The rank the stat block lists the spell at; a cantrip is half its level, rounded up.
      def listed_spell_rank(spell)
        listed = Npcs.casting(@holder, spell)
        rank = (listed && listed['spells'] || {}).find { |_rank, names| names.any? { |one| one.casecmp?(spell) } }&.first

        return nil unless rank
        return (@holder.pf2_level / 2.0).ceil.clamp(1, 10) if rank.to_s == '0'

        rank.to_i
      end

      def effect_owner_field
        :npc
      end
    end
  end
end
