module AresMUSH
  module Pf2e

    # What a character shrugs off, and what hurts them more.
    #
    # Immunity, weakness and resistance are the other side of the damage work: damage now has a kind, so
    # something can care what kind it is. Twenty-six rules on the things we stock declare one - a Charm
    # of Resistance, an Aeon Stone, and the immunities Blinded and Deafened carry.
    #
    # The arithmetic is theirs (`system/damage/iwr.ts`) and has three steps in an order that matters:
    #
    #   1. Immunity to the kind takes the whole of it.
    #   2. The **highest** applicable weakness adds its value - once, not once per weakness.
    #   3. The **highest** applicable resistance subtracts, and damage does not go below nothing.
    #
    # Taking the highest rather than the sum is the same shape as modifier stacking, and for the same
    # reason: two resistances of 5 are resistance 5.
    module IWR

      KINDS = %w{Immunity Weakness Resistance}.freeze

      # Immunity to a kind of damage takes all of it; immunity to something else - a trait, a condition -
      # is not about damage at all, and those are held so a predicate can ask.
      def self.of(char)
        SheetReads.memo(char, :iwr) { gather(char) }
      end

      # Whoever's: a character's from their rules, a creature's from its stat block and what it is under.
      def self.for(holder)
        Actors.of(holder).creature? ? Npcs.iwr(holder) : of(holder)
      end

      def self.gather(char)
        sources = Effects.sources(char)
        options = Effects.options(char)
        context = Effects.context(char)

        KINDS.each_with_object({}) do |kind, out|
          out[kind.downcase] = Rules.declarations(sources, options, kind, context)
        end
      end

      # ------------------------------------------------------------------------------
      # What a type means
      #
      # Each type is a description of what it is about, read against what is so of the damage or the
      # effect: its kind and category, what it is made of, where it came from (`actor/data/iwr.ts`).

      PHYSICAL = %w{bludgeoning piercing slashing bleed}.freeze
      ENERGY = %w{acid cold electricity fire force sonic vitality void}.freeze
      DAMAGE_TYPES = (PHYSICAL + ENERGY + %w{mental poison spirit untyped}).freeze
      LETTERS = { 'b' => 'bludgeoning', 'p' => 'piercing', 's' => 'slashing' }.freeze
      MATERIALS = %w{abysium adamantine cold-iron dawnsilver djezet duskwood inubrix keep-stone noqual orichalcum
                     peachwood siccatite silver sisterstone sovereign-steel warpglass vorpal-adamantine}.freeze
      TRADITIONS = %w{arcane divine occult primal}.freeze
      ITEM_TRAITS = %w{air alchemical auditory disease earth light metal olfactory prediction radiation time visual
                       water wood}.freeze

      # Kinds of damage that are also the trait of an effect: immunity to poison is to the damage and to
      # what carries the trait.
      ALSO_TRAITS = %w{mental poison}.freeze

      DESCRIBED = {
        'all-damage' => [ 'damage' ],
        'area-damage' => [ 'area-damage' ],
        'arrow-vulnerability' => [ 'item:group:bow' ],
        'axes' => [ 'item:group:axe' ],
        'axe-vulnerability' => [ 'item:group:axe' ],
        'critical-hits' => [ 'check:outcome:critical-success' ],
        'physical' => [ 'damage:category:physical' ],
        'energy' => [ 'damage:category:energy' ],
        'ghost-touch' => [ { 'or' => %w{item:rune:property:astral item:rune:property:ghost-touch item:rune:property:greater-astral} } ],
        'holy' => [ { 'or' => %w{origin:action:trait:holy item:trait:holy} } ],
        'unholy' => [ { 'or' => %w{origin:action:trait:unholy item:trait:unholy} } ],
        'magic' => [ { 'or' => %w{origin:action:trait:impulse item:from-spell item:type:spell} } ],
        'magical' => [ { 'or' => %w{item:magical origin:action:trait:magical} + TRADITIONS.map { |one| "origin:action:trait:#{one}" } } ],
        'non-magical' => [ { 'not' => 'item:magical' } ],
        'persistent-damage' => [ { 'or' => [ 'damage:category:persistent',
                                             { 'and' => %w{item:type:condition item:slug:persistent-damage} } ] } ],
        'precision' => [ 'damage:component:precision' ],
        'splash-damage' => [ 'damage:component:splash' ],
        'spells' => [ 'damage', { 'or' => %w{item:type:spell item:from-spell item:trait:impulse} } ],
        'damage-from-spells' => [ 'damage', { 'or' => %w{item:type:spell item:from-spell item:trait:impulse} } ],
        'unarmed-attacks' => [ 'item:category:unarmed' ],
        'weapons' => [ 'item:type:weapon', { 'not' => 'item:category:unarmed' } ]
      }.freeze

      # A weakness to a material is also to what counts as it.
      ALSO = { 'cold-iron' => 'sovereign-steel', 'silver' => 'dawnsilver' }.freeze

      # Weaknesses to what does not itself deal damage - holy, water - which a hit feels once however many
      # kinds of damage it deals.
      ONCE = (TRADITIONS + %w{air arrow-vulnerability axe-vulnerability earth ghost-touch holy metal plant radiation
                              salt-water salt spells unholy water wood}).freeze

      # The description of one type. `category` is which of immunity, weakness and resistance asks.
      def self.describe(type, category = nil)
        return Array(type['definition']) if type.is_a?(Hash)

        type = Domains.slug(type)
        type = LETTERS[type] || type

        return DESCRIBED[type] if DESCRIBED.key?(type)
        return [ { 'or' => [ "item:trait:#{type}", "origin:action:trait:#{type}" ] } ] if TRADITIONS.include?(type)
        return [ "item:trait:#{type}" ] if ITEM_TRAITS.include?(type)
        return damage_type(type) if DAMAGE_TYPES.include?(type)
        return material(type, category) if MATERIALS.include?(type)

        # A condition by its name, or a kind of effect by its trait: `fear-effects` is anything with fear.
        trait = type.delete_suffix('-effects')

        [ { 'or' => [ { 'and' => [ 'item:type:condition', "item:slug:#{type}" ] },
                      { 'and' => [ 'item:type:effect', "item:trait:#{trait}" ] } ] } ]
      end

      def self.damage_type(type)
        return [ "damage:type:#{type}" ] unless ALSO_TRAITS.include?(type)

        [ { 'or' => [ "damage:type:#{type}", { 'and' => [ 'item:type:effect', "item:trait:#{type}" ] } ] } ]
      end

      def self.material(type, category)
        also = category == 'weakness' ? ALSO[type] : nil

        also ? [ { 'or' => [ "damage:material:#{type}", "damage:material:#{also}" ] } ] : [ "damage:material:#{type}" ]
      end

      # What is so of some damage, as the descriptions ask it: its kind and category, and whatever else
      # was said of it - `silver`, `magical`, `area`, a trait - or stated outright as a fact.
      WORDS = { 'precision' => 'damage:component:precision', 'splash' => 'damage:component:splash',
                'splash-damage' => 'damage:component:splash', 'persistent' => 'damage:category:persistent',
                'persistent-damage' => 'damage:category:persistent', 'area' => 'area-damage',
                'magical' => 'item:magical', 'spell' => 'item:type:spell', 'weapon' => 'item:type:weapon',
                'unarmed' => 'item:category:unarmed', 'critical' => 'check:outcome:critical-success',
                'ghost-touch' => 'item:rune:property:ghost-touch' }.freeze

      def self.facts(kind, about = [])
        kind = kind.nil? ? nil : Domains.slug(kind)
        kind = LETTERS[kind] || kind
        own = kind ? [ 'damage', "damage:type:#{kind}" ] : []
        own << 'damage:category:physical' if PHYSICAL.include?(kind)
        own << 'damage:category:energy' if ENERGY.include?(kind)
        # A kind that is no kind of damage is something said of it: `persistent-damage`.
        own += fact(kind) if kind && !DAMAGE_TYPES.include?(kind)

        own + Array(about).compact.flat_map { |one| fact(one) }
      end

      def self.fact(word)
        return [ word.to_s ] if word.to_s.include?(':')

        slug = Domains.slug(word)

        return [ WORDS[slug] ] if WORDS.key?(slug)
        return [ "damage:material:#{slug}" ] if MATERIALS.include?(slug)
        return [ slug ] if slug == 'area-damage'

        [ "item:trait:#{slug}" ]
      end

      # Whether an entry is about what these facts describe: any of its types, none of its exceptions,
      # and its own description where it has one.
      def self.about?(entry, facts, category = nil)
        types = Array(entry['type']).reject { |type| Domains.slug(type) == 'custom' }

        return Predicate.test(entry['definition'], facts) if types.empty?
        return false unless types.any? { |type| Predicate.test(describe(type, category), facts) }
        return false if Array(entry['exceptions']).any? { |one| Predicate.test(describe(one, category) - [ 'damage' ], facts) }

        entry['definition'].nil? || Predicate.test(entry['definition'], facts)
      end

      def self.label(entry)
        type = Array(entry['type']).join('/')
        excepted = Array(entry['exceptions']).map { |one| one.is_a?(Hash) ? (one['label'].to_s.split('.').last || 'some') : one }

        doubled = Array(entry['doubleVs']).map { |one| one.is_a?(Hash) ? (one['label'].to_s.split('.').last || 'some') : one }
        notes = []
        notes << "except #{excepted.join(', ')}" if excepted.any?
        notes << "double against #{doubled.join(', ')}" if doubled.any?

        notes.empty? ? type : "#{type} (#{notes.join('; ')})"
      end

      # ------------------------------------------------------------------------------
      # Damage

      # What `amount` of `kind` damage comes to for this character, and what did it. `about` is what else
      # is so of the damage (`facts`), and `once` holds the weaknesses a hit has already felt, for a hit
      # that deals more than one kind.
      #
      #   { 'amount' =>, 'applied' => [ { 'category' =>, 'type' =>, 'adjustment' => } ] }
      def self.apply(held, amount, kind, about = [], once: nil)
        facts = facts(kind, about)
        applied = []

        return { 'amount' => amount, 'applied' => applied } if facts.empty?

        found = immunity(held, facts)

        if found
          applied << { 'category' => 'immunity', 'type' => label(found), 'adjustment' => -amount }
          return { 'amount' => 0, 'applied' => applied }
        end

        amount = weaken(amount, facts, held, applied, once)
        amount = resist(amount, facts, held, applied)

        { 'amount' => amount, 'applied' => applied }
      end

      # The immunity that takes the whole of some damage. Immunity to critical hits takes only the
      # doubling, which is the Strike's to leave out (`immune?`).
      def self.immunity(held, facts)
        Array(held['immunity']).find do |entry|
          !Array(entry['type']).map { |type| Domains.slug(type) }.include?('critical-hits') && about?(entry, facts, 'immunity')
        end
      end

      # Whether they are immune to what the words describe: `precision`, `critical`, a kind of damage.
      def self.immune?(held, against)
        words = Array(against)
        kind = words.find { |one| DAMAGE_TYPES.include?(LETTERS[Domains.slug(one)] || Domains.slug(one)) }
        facts = facts(kind, words - [ kind ])

        Array(held['immunity']).any? { |entry| about?(entry, facts, 'immunity') }
      end

      def self.weaken(amount, facts, held, applied, once)
        felt = Array(once)
        found = Array(held['weakness']).select { |entry| about?(entry, facts, 'weakness') && !felt.include?(label(entry)) }
                                       .max_by { |entry| entry['value'].to_i }

        return amount unless found

        once << label(found) if once && (Array(found['type']).map { |type| Domains.slug(type) } & ONCE).any?
        applied << { 'category' => 'weakness', 'type' => label(found), 'adjustment' => found['value'].to_i }

        amount + found['value'].to_i
      end

      def self.resist(amount, facts, held, applied)
        found = Array(held['resistance']).select { |entry| about?(entry, facts, 'resistance') }
                                         .max_by { |entry| resisted(entry, facts) }

        return amount unless found

        taken = [ resisted(found, facts), amount ].min
        applied << { 'category' => 'resistance', 'type' => label(found), 'adjustment' => -taken }

        amount - taken
      end

      # A resistance's value against this damage: twice itself against what it is doubled against.
      def self.resisted(entry, facts)
        doubled = Array(entry['doubleVs']).any? { |one| Predicate.test(describe(one, 'resistance'), facts) }

        entry['value'].to_i * (doubled ? 2 : 1)
      end

      # ------------------------------------------------------------------------------
      # Conditions and effects

      def self.immune_to_condition?(held, condition)
        facts = [ 'item:type:condition', "item:slug:#{Domains.slug(condition)}" ]

        Array(held['immunity']).any? { |entry| about?(entry, facts, 'immunity') }
      end

      # The immunity that keeps out an effect with these traits - a spell, an action, an ability - by its
      # name, or nothing.
      def self.immune_to_effect?(held, traits)
        facts = [ 'item:type:effect' ] + Array(traits).map { |trait| "item:trait:#{Domains.slug(trait)}" }
        found = Array(held['immunity']).find { |entry| about?(entry, facts, 'immunity') }

        found ? label(found) : nil
      end
    end
  end
end
