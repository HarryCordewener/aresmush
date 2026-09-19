module AresMUSH
  module Pf2e

    # What a statistic answers to, so an effect can name a group rather than a list of statistics.
    #
    # Frightened is "-1 status penalty to all your checks and DCs". Written against statistics that is
    # a line per skill, per save, per DC, and a line more every time a skill is added. Written against
    # domains it is one row naming `all`, and a skill added tomorrow is covered because it declares
    # `all` itself.
    #
    # The same mechanism carries the cases that are otherwise special: Clumsy penalises
    # Dexterity-based rolls, so it names `dex-based` and every statistic that reads Dexterity picks it
    # up - including a statistic that reads Dexterity only because some other effect said it could.
    #
    # Domains are Foundry's (`document.ts:568`, `752`, `784`, `844`, `1016`) and the slugs are theirs
    # too, so a converted rule element's `selector` needs no translation.
    module Domains

      # Every check and every DC answers to this. Hit points and speed are neither, which is why they
      # are the two kinds below that do not name it.
      ALL = 'all'.freeze

      # A statistic's kind decides its domains; adding a kind is adding a row. `name` is the
      # statistic's own name where it has one, and `ability` the attribute it reads.
      #
      # Each list is Foundry's, from the place they build it, so a selector copied out of their data
      # reaches the same statistics here. Two of them are worth noticing because they are not what a
      # reading of the rules would guess: perception and a lore carry no `<attr>-based` domain, so
      # Stupefied reaches a Wisdom-based Perception check only if a condition says `perception`
      # outright - and theirs does.
      KINDS = [
        # `document.ts:511` enters hit points' Constitution part as a modifier; the figure itself
        # answers to `hp` alone, being neither a check nor a DC.
        { 'name' => 'hp', 'domains' => ->(_name, _ability) { [ 'hp' ] } },

        # `creature/document.ts:764`. A speed answers to its own kind and to every speed at once.
        { 'name' => 'speed', 'domains' => ->(name, _ability) {
          [ "#{slug(name || 'land')}-speed", 'all-speeds' ]
        } },

        { 'name' => 'ac', 'domains' => ->(_name, _ability) { [ ALL, 'ac', 'dex-based' ] } },

        # `character/document.ts:585`, which is the whole list, plus the domains the roll itself has.
        { 'name' => 'perception',
          'domains' => ->(_name, _ability) { [ 'perception', ALL ] + rolled('perception') } },

        { 'name' => 'save',
          'domains' => ->(name, ability) {
            [ slug(name), 'saving-throw', ALL ] + based(ability) + rolled(name)
          } },

        # `character/document.ts:845`.
        { 'name' => 'skill',
          'domains' => ->(name, ability) {
            [ slug(name), 'skill-check', ALL ] + based(ability) + skill_check(ability) + rolled(name)
          } },

        # `character/document.ts:903`. A lore's attribute is always Intelligence and the list says
        # `int-skill-check` without `int-based`.
        { 'name' => 'lore',
          'domains' => ->(name, _ability) {
            [ slug(name), 'skill-check', 'lore-skill-check', 'int-skill-check', ALL ] + rolled(name)
          } },

        # Healing a character receives, which is theirs rather than the healer's: Robust Health recovers
        # more from Treat Wounds, whoever is doing the treating.
        { 'name' => 'healing', 'domains' => ->(_name, _ability) { [ 'healing-received' ] } },

        { 'name' => 'class_dc', 'domains' => ->(_name, _ability) { [ 'class-dc', 'class', ALL ] } },
        { 'name' => 'spell_dc', 'domains' => ->(_name, _ability) { [ 'spell-dc', ALL ] } },
        { 'name' => 'spell_attack',
          'domains' => ->(_name, _ability) { [ 'spell-attack', 'attack-roll', ALL ] } },

        # `actor/helpers.ts:315`. `name` is the attack descriptor, so the weapon's own id, its name,
        # its group and its base type each get a domain: an effect can reach one sword, every sword,
        # every sword of a group, or every attack.
        { 'name' => 'attack', 'domains' => ->(attack, ability) { attack_domains(attack, ability) } },

        # `actor/helpers.ts:378`.
        { 'name' => 'damage', 'domains' => ->(attack, ability) { damage_domains(attack, ability) } },

        # Initiative is a check with some other statistic underneath it - Perception unless a feat says
        # otherwise - so it answers to that statistic's domains as well as its own.
        { 'name' => 'initiative',
          'domains' => ->(name, ability) {
            [ 'initiative' ] + self.for(name || 'perception', nil, ability)
          } }
      ].freeze

      # The domains built off a name rather than fixed. An attack's name, group and base type come from
      # the weapon or the unarmed attack a character has, and a feat can grant one nothing has heard of
      # - Tiger Stance grants a tiger claw - so a selector ending in one of these is reachable whatever
      # the name in front of it. Anything else has to be in a list some statistic actually declares.
      DERIVED_SUFFIXES = %w{-damage -base-damage -base-type-damage -weapon-group-damage -strike-damage
                            -speed -attack -attack-roll -base-attack-roll -group-attack-roll
                            -skill-check -check -based -lore}.freeze

      def self.derived?(selector)
        DERIVED_SUFFIXES.any? { |suffix| selector.to_s.end_with?(suffix) }
      end

      # What a check answers to because it is a check rather than a figure: `check` and its own name
      # with `-check` after it (`statistic/statistic.ts:314`). Armored Stealth adjusts the armour
      # penalty on `stealth-check`, which is the roll, and would reach nothing named `stealth`.
      def self.rolled(name)
        [ 'check', "#{slug(name)}-check" ]
      end

      # The kinds of movement a creature can have, which is what a speed's own domain is built from
      # (`creature/document.ts`). A rule naming `fly-speed` reaches only a fly speed.
      MOVEMENT = %w{land burrow climb fly swim}.freeze

      BY_KIND = KINDS.each_with_object({}) { |row, out| out[row['name']] = row }.freeze

      # The attribute a statistic reads is a domain of its own, so an effect that penalises an
      # attribute reaches everything that reads it without naming any of them. A statistic may read
      # more than one - a finesse weapon's attack takes the better of Strength and Dexterity, and
      # Clumsy reaches it because it is Dexterity-based whichever of the two won.
      def self.for(kind, name = nil, ability = nil)
        row = BY_KIND[kind.to_s]

        raise ArgumentError, "no such kind of statistic: #{kind.inspect}" unless row

        (row['domains'].call(name, ability) + based(ability)).compact.uniq
      end

      # Whether an effect written against `selector` reaches a statistic with these domains. A selector
      # may name several, as Foundry's do.
      def self.matches?(selector, domains)
        (Array(selector).map { |named| slug(named) } & domains).any?
      end

      # Foundry's own list, in their order. An attack descriptor is a hash rather than a name because
      # every one of these comes off the weapon.
      def self.attack_domains(attack, ability)
        attack = {} unless attack.is_a?(Hash)
        reach = attack['ranged'] ? 'ranged' : 'melee'
        kind = attack['unarmed'] ? 'unarmed' : 'weapon'

        [ attack['base'] ? "#{slug(attack['base'])}-base-attack-roll" : nil,
          attack['group'] ? "#{slug(attack['group'])}-group-attack-roll" : nil,
          attack['id'] ? "#{attack['id']}-attack" : nil,
          attack['name'] ? "#{slug(attack['name'])}-attack" : nil,
          attack['name'] ? "#{slug(attack['name'])}-attack-roll" : nil,
          "#{kind}-attack-roll",
          "#{reach}-attack-roll",
          "#{reach}-strike-attack-roll",
          'strike-attack-roll',
          'attack-roll',
          'attack',
          'check',
          ALL,
          attack['prof'] ? "#{slug(attack['prof'])}-attack" : nil ] +
          based(ability) + Array(ability).map { |one| "#{abbreviation(one)}-attack" }
      end

      def self.damage_domains(attack, ability)
        attack = {} unless attack.is_a?(Hash)
        reach = attack['ranged'] ? 'ranged' : 'melee'
        kind = attack['unarmed'] ? 'unarmed' : 'weapon'
        action = attack['action'] || 'strike'

        [ attack['id'] ? "#{attack['id']}-damage" : nil,
          attack['id'] ? "#{attack['id']}-#{reach}-damage" : nil,
          attack['name'] ? "#{slug(attack['name'])}-damage" : nil,
          "#{reach}-#{action}-damage",
          "#{reach}-damage",
          "#{kind}-damage",
          attack['group'] ? "#{slug(attack['group'])}-weapon-group-damage" : nil,
          attack['base'] ? "#{slug(attack['base'])}-base-damage" : nil,
          attack['base'] ? "#{slug(attack['base'])}-base-type-damage" : nil,
          attack['base'] ? "#{slug(attack['base'])}-damage" : nil,
          'attack-damage',
          "#{action}-damage",
          'damage',
          attack['prof'] ? "#{slug(attack['prof'])}-damage" : nil ] +
          Array(ability).map { |one| "#{abbreviation(one)}-damage" }
      end

      def self.based(ability)
        Array(ability).map { |one| abbreviation(one) }.compact.map { |abbr| "#{abbr}-based" }
      end

      def self.skill_check(ability)
        Array(ability).map { |one| abbreviation(one) }.compact.map { |abbr| "#{abbr}-skill-check" }
      end

      # Foundry writes an attribute's domains off its three-letter form: `dex-based`, not
      # `dexterity-based`.
      def self.abbreviation(ability)
        return nil if ability.to_s.strip.empty?

        ability.to_s[0, 3].downcase
      end

      def self.slug(name)
        name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end
    end
  end
end
