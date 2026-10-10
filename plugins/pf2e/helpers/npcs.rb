module AresMUSH
  module Pf2e

    # A key for someone that no character and creature share, since both are numbered by their own
    # tables: an aura's effects record whose aura put them there.
    def self.holder_key(holder)
      Actors.of(holder).key
    end

    # What a creature in an encounter is worth to the rules engine.
    #
    # A character's figures are built from their proficiencies, attributes, feats and gear. A creature's
    # are already on its stat block - AC 16, Reflex +7 - so its figure is that number, and what changes it
    # is what changes anyone's: its conditions and the effects it is under, read by the same rules. A
    # frightened goblin's Reflex is +7 less Frightened's own status penalty.
    module Npcs

      # One row per kind of figure: the stat block's number for it, and the attribute it is based on,
      # which is what decides the `dex-based` domain Clumsy reaches.
      KINDS = {
        # Maximum hit points: Drained's own rule lowers them.
        'hp' => { 'base' => ->(block, _name) { block['hp'] },
                  'ability' => ->(_name) { nil } },
        'ac' => { 'base' => ->(block, _name) { block['ac'] },
                  'ability' => ->(_name) { 'Dexterity' } },
        'perception' => { 'base' => ->(block, _name) { block['perception'] },
                          'ability' => ->(_name) { 'Wisdom' } },
        'save' => { 'base' => ->(block, name) { (block['saves'] || {})[Pf2e.canonical_save(name).to_s.downcase] },
                    'ability' => ->(name) { Pf2e::LINKED_ABILITY[name.to_s.downcase] } },
        'skill' => { 'base' => ->(block, name) { skill(block, name) },
                     'ability' => ->(name) { Pf2eSkills.get_linked_attr(name) } },
        'lore' => { 'base' => ->(block, name) { (block['skills'] || {})[name] || attribute(block, 'Intelligence') },
                    'ability' => ->(_name) { 'Intelligence' } },
        'attack' => { 'base' => ->(_block, strike) { strike['bonus'] },
                      'ability' => ->(strike) { Stat.attack_abilities(strike) } },
        'spell_attack' => { 'base' => ->(_block, casting) { casting['attack'] },
                            'ability' => ->(_casting) { nil } },
        'spell_dc' => { 'base' => ->(_block, casting) { casting['dc'] },
                        'ability' => ->(_casting) { nil } }
      }.freeze

      # A skill the stat block lists is its number; one it does not is the attribute alone, which is an
      # untrained creature's modifier.
      def self.skill(block, name)
        listed = (block['skills'] || {}).find { |skill, _| skill.casecmp?(name.to_s) }

        listed ? listed[1] : attribute(block, Pf2eSkills.get_linked_attr(name))
      end

      def self.attribute(block, ability)
        (block['abilities'] || {})[Domains.abbreviation(ability)].to_i
      end

      # A figure of the creature's, with what modifies it: `{ 'base' =>, 'modifiers' =>, 'total' => }`,
      # the shape `Stat.of` answers with.
      def self.stat(npc, kind, name = nil, options = [])
        row = KINDS[kind.to_s]

        raise ArgumentError, "no figure #{kind.inspect} on a creature" unless row

        base = row['base'].call(npc.stat_block, name)

        return nil if base.nil?

        ability = row['ability'].call(name)
        domains = Domains.for(kind, kind.to_s == 'save' ? Pf2e.canonical_save(name) : name, ability)
        sources = sources(npc)
        context = context(npc)
        held = options(npc, domains) + Array(options)

        met = Effects.modifiers(sources, domains, context, held).select { |one| one['met'] }
        own = [ Stat.multiple_attack(kind, name, sources, domains, held, context) ].compact
        adjusted = Modifiers.adjust(own + met, Rules.modifier_adjustments(sources, domains, held, context))

        Modifiers.breakdown(base.to_i, adjusted).merge('domains' => domains)
      end

      # ------------------------------------------------------------------------------
      # What the rules engine reads

      def self.sources(npc)
        SheetReads.memo(npc, :effect_sources) do
          Effects.conditions(npc) + ability_sources(npc) + ActiveEffects.sources(npc)
        end
      end

      # Its abilities and Strikes, each a source of the rules it carries - an aura, fast healing, a bonus
      # to its saves, extra damage on a Strike. A Strike's source carries the Strike's id, which is what
      # a rule about that Strike names (`{item|_id}-damage`).
      def self.ability_sources(npc)
        block = npc.stat_block
        owned = Array(block['actions']).map { |one| [ one, Domains.slug(one['name']) ] } +
                Array(block['strikes']).map { |one| [ one, strike_id(one) ] }

        # What a toggle on one of them switches is a circumstance of the moment - allies beside the
        # target for Pack Attack, a charge before the Strike - so it is off until the GM says it holds.
        owned.reject { |one, _id| Array(one['rules']).empty? }.map do |one, id|
          Effects.source(one['name'], one['rules'], 'kind' => Effects::DOES,
                         'item' => { 'id' => id, '_id' => id, 'level' => npc.pf2_level })
        end
      end

      def self.strike_id(strike)
        "strike-#{Domains.slug(strike['name'])}"
      end

      # What is true of it and what has been switched on for it: a toggle its abilities declare, off
      # until a GM says otherwise.
      def self.options(npc, domains = nil)
        facts(npc) + RollOptions.active(npc, domains)
      end

      # What is true of the creature, in Foundry's spelling: its level, its traits and the mode of being
      # they imply, the effects it is under and its conditions.
      def self.facts(npc)
        SheetReads.memo(npc, :effect_facts) do
          traits = npc.pf2_traits

          [ "self:level:#{npc.pf2_level}", 'self:type:npc' ] +
            Effects.named('self:trait', traits) + Effects.mode_facts(traits) +
            Effects.effect_facts(npc) +
            Effects.named('self:condition', Pf2e.held_conditions(npc).keys)
        end
      end

      def self.context(npc)
        abilities = Pf2e::ABILITIES.each_with_object({}) do |ability, out|
          out[Domains.abbreviation(ability)] = { 'mod' => attribute(npc.stat_block, ability) }
        end

        { 'actor' => { 'level' => npc.pf2_level, 'abilities' => abilities, 'flags' => { 'system' => {} },
                       'system' => { 'movement' => { 'speeds' =>
                                       { 'land' => { 'value' => (npc.stat_block['speeds'] || {})['land'].to_i } } } } } }
      end

      # ------------------------------------------------------------------------------
      # Its strikes and its spellcasting

      # A strike from the stat block as the attack code reads one: its bonus, traits and damage, and
      # whether it is ranged, which is what its range says.
      def self.strikes(npc)
        Array(npc.stat_block['strikes']).map do |strike|
          range = range_of(strike)

          { 'id' => strike_id(strike), 'name' => strike['name'], 'base' => strike['name'], 'bonus' => strike['bonus'].to_i,
            'traits' => Array(strike['traits']), 'ranged' => range.positive?,
            'range' => range, 'unarmed' => false,
            'damage' => Array(strike['damage']), 'effects' => Array(strike['effects']) }
        end
      end

      # A Strike's range increment in feet: its own, or what a `thrown-30` or `range-increment-60` trait
      # says. Nothing for a melee Strike.
      def self.range_of(strike)
        return strike['range'].to_i if strike['range'].to_i.positive?

        Array(strike['traits']).map { |one| one.to_s[/\A(?:thrown|range(?:-increment)?)-(\d+)\z/, 1].to_i }.max.to_i
      end

      def self.strike(npc, term = nil)
        listed = strikes(npc)

        return listed.first if term.to_s.strip.empty?

        wanted = Domains.slug(term)

        listed.find { |one| Domains.slug(one['name']) == wanted } ||
          listed.find { |one| Domains.slug(one['name']).include?(wanted) }
      end

      # The spellcasting that holds a spell, or the first there is.
      def self.casting(npc, spell = nil)
        entries = Array(npc.stat_block['spellcasting'])

        entries.find { |one| (one['spells'] || {}).values.flatten.any? { |name| name.casecmp?(spell.to_s) } } ||
          entries.first
      end

      # ------------------------------------------------------------------------------
      # Hit points

      # What a creature shrugs off and what hurts it more: its stat block's, and anything its effects add.
      def self.iwr(npc)
        block = npc.stat_block
        granted = IWR::KINDS.each_with_object({}) do |kind, out|
          out[kind.downcase] = Rules.declarations(sources(npc), facts(npc), kind, context(npc))
        end

        { 'immunity' => Array(block['immunities']).map { |type| { 'type' => [ type ] } } + granted['immunity'],
          'weakness' => listed(block['weaknesses']) + granted['weakness'],
          'resistance' => listed(block['resistances']) + granted['resistance'] }
      end

      # A stat block's weaknesses or resistances as entries: each is a value, or a value with what it
      # excepts and what it is doubled against.
      def self.listed(held)
        (held || {}).map do |type, value|
          value = { 'value' => value } unless value.is_a?(Hash)

          { 'type' => [ type ], 'value' => value['value'].to_i, 'exceptions' => Array(value['except']),
            'doubleVs' => Array(value['double']) }
        end
      end

      # `physical 10 (except silver)`, `all-damage 5 (except force; double against non-magical)`.
      def self.listed_words(held)
        listed(held).map do |entry|
          notes = []
          notes << "except #{entry['exceptions'].join(', ')}" if entry['exceptions'].any?
          notes << "double against #{entry['doubleVs'].join(', ')}" if entry['doubleVs'].any?

          "#{entry['type'].first} #{entry['value']}#{notes.empty? ? '' : " (#{notes.join('; ')})"}"
        end
      end

      # Damage to a creature, after what it resists: temporary hit points first, then its own.
      #
      #   { 'amount' => what it took, 'applied' => the immunities, weaknesses and resistances that counted }
      def self.damage(npc, amount, kind = nil, about = [], once: nil)
        held = IWR.apply(iwr(npc), amount.to_i, kind, about, :once => once)
        taken = held['amount']
        soaked = [ npc.temp_hp.to_i, taken ].min

        npc.update(:temp_hp => npc.temp_hp.to_i - soaked, :damage => [ npc.damage.to_i + taken - soaked, npc.max_hp ].min)
        Turns.damaged(npc, kind) if kind

        held
      end

      # What heals it as its turn starts. Its abilities' FastHealing rules where it has any - they carry
      # the circumstances too, like Air Scamp's only in open air - and otherwise what its hit point
      # details say: `regeneration 20 (deactivated by acid or fire)`, `fast healing 5`.
      HEALING = /(regeneration|fast healing)\s+(\d+)(?:\s*\(deactivated by ([^)]*)\))?/i

      def self.healing(npc)
        ruled = ability_sources(npc).any? { |source| Rules.of_kind(source, 'FastHealing').any? }

        return healing_from_rules(npc) if ruled

        npc.stat_block['hp_details'].to_s.scan(HEALING).map do |kind, value, stops|
          { 'type' => kind.downcase == 'regeneration' ? 'regeneration' : 'fast-healing', 'value' => value.to_i,
            'source' => npc.stat_block['hp_details'],
            'deactivated_by' => stops.to_s.split(/,|\bor\b|\band\b/).map(&:strip).reject(&:empty?) }
        end
      end

      def self.healing_from_rules(npc)
        context = context(npc)
        held = options(npc)

        sources(npc).flat_map do |source|
          Rules.of_kind(source, 'FastHealing').select { |row| Predicate.test(row['predicate'], held + Array(source['options'])) }
                                              .map { |row| Rules.contribute(row, source, context.merge('item' => source['item'] || {})) }
                                              .compact
        end
      end

      # What its rules add to a Strike's damage, beyond the stat block's own formula: an ability's
      # extra dice, a flat bonus. `[ { 'formula', 'type', 'category', 'bucket' } ]`, where the bucket is
      # how a critical hit treats it - doubled with the rest, fixed, or only on a critical.
      def self.strike_damage(npc, strike, options = [])
        domains = Domains.for('damage', strike, nil)
        sources = sources(npc)
        context = context(npc)
        held = options(npc, domains) + Pf2eCombat.attack_options(strike) + Array(options)
        base = Array(strike['damage']).first
        kind = base ? base[1] : nil

        dice = Effects.damage_dice(sources, domains, context, held).select { |row| row['met'] && !row['override'] }
                      .map do |row|
          { 'formula' => "#{row['dice']}#{row['die']}", 'type' => row['damage_type'] || kind,
            'category' => row['category'], 'bucket' => Damage::BUCKETS.fetch(row['critical'], 'doubling') }
        end

        flat = Effects.modifiers(sources, domains, context, held).select { |row| row['met'] && row['value'].to_i != 0 }
                      .map do |row|
          { 'formula' => row['value'].to_i.to_s, 'type' => row['damage_type'] || kind,
            'category' => row['category'], 'bucket' => Damage::BUCKETS.fetch(row['critical'], 'doubling') }
        end

        dice + flat
      end

      def self.heal(npc, amount)
        healed = [ amount.to_i, npc.damage.to_i ].min

        npc.update(:damage => npc.damage.to_i - healed)

        healed
      end
    end
  end
end
