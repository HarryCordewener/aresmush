module AresMUSH
  module Pf2e

    # What an effect changes about one of the character's things while it lasts: Magic Weapon makes a
    # weapon +1 striking, Shrink Item makes it lighter, a spell makes armour into cold iron, another makes
    # a frightened character more frightened.
    #
    # Foundry writes each as an `ItemAlteration` naming a kind of item or one item by id, a property, and
    # a mode (`item-alteration/handlers.ts`). An alteration is applied to what is read, never to what is
    # stored: the weapon on the character is unchanged, and the one an attack reads is altered for as long
    # as the effect lasts. That is what lets it end without anyone putting anything back.
    #
    # Only the properties that change something this engine models are read. The rest - a spell's area,
    # an action's frequency, an item's description - are refused at import.
    module Alterations

      # Each property, onto the field of the thing it alters.
      #
      #   list  a list of words, which `add` and `remove` change a word at a time
      #   step  a die size, which `upgrade` and `downgrade` move one size at a time
      PROPERTIES = {
        'traits' => { 'field' => 'traits', 'list' => true },
        'runes-potency' => { 'field' => 'potency' },
        'runes-striking' => { 'field' => 'striking' },
        'runes-resilient' => { 'field' => 'resilient' },
        'damage-dice-faces' => { 'field' => 'die', 'step' => true },
        'damage-dice-number' => { 'field' => 'dice' },
        'damage-type' => { 'field' => 'damage_type' },
        'material-type' => { 'field' => 'material' },
        'range-increment' => { 'field' => 'range' },
        'group' => { 'field' => 'group' },
        'category' => { 'field' => 'category' },
        'ac-bonus' => { 'field' => 'ac_bonus' },
        'dex-cap' => { 'field' => 'dex_cap' },
        'check-penalty' => { 'field' => 'check_penalty' },
        'speed-penalty' => { 'field' => 'speed_penalty' },
        'strength' => { 'field' => 'strength' },
        'hardness' => { 'field' => 'hardness' },
        'badge-value' => { 'field' => 'value' },
        'badge-max' => { 'field' => 'max' },
        'pd-recovery-dc' => { 'field' => 'recovery_dc' }
      }.freeze

      # The kinds of thing an alteration may name that are things here.
      KINDS = %w{weapon armor shield condition effect}.freeze

      # Every alteration the character's feats, items and effects make to things of this kind. Conditions
      # are not asked, because a condition's value is itself one of the things altered, and working out
      # which conditions a character has is where that value is read.
      def self.rows(char, kind)
        SheetReads.memo(char, :"alterations_#{kind}") do
          # A creature in an encounter carries nothing and has no feats; only what it is under alters.
          sources = (Pf2e.npc?(char) ? [] : Effects.feats(char) + Effects.items(char)) + ActiveEffects.sources(char)

          context = Effects.context(char)

          sources.flat_map do |source|
            Rules.of_kind(source, 'ItemAlteration').map { |row| Rules.resolved(row, source, {}) }.compact
                  .select { |row| row['itemType'].to_s == kind || row['itemId'] }
                  .map { |row| valued(row, context.merge('item' => source['item'] || {})) }
          end
        end
      end

      # A number an alteration gives may be a formula over the character or the effect - Invoke Offense's
      # striking rune is better at 12th level - so it is worked out where the rule came from. A word it
      # gives, a trait or a material, stands as it is.
      WORDS = %w{traits damage-type material-type group category}.freeze

      def self.valued(row, context)
        return row if WORDS.include?(row['property'].to_s) || !row['value'].is_a?(String)
        return row if row['property'].to_s == 'damage-dice-faces' && row['value'].to_s.match?(/\A\d+\z/)

        row.merge('value' => Formula.value(row['value'], context))
      rescue Formula::Invalid
        row
      end

      # `held` altered by what reaches it. `id` is the thing's own id, which an alteration naming one
      # thing is matched on, and `options` what it answers to, which an alteration's predicate is tested
      # against alongside what is true of the character.
      def self.apply(char, kind, held, id: nil, options: [])
        reaching = rows(char, kind)

        return held if reaching.empty?

        facts = Effects.character_facts(char) + Array(options)

        reaching.each_with_object(held.dup) do |row, out|
          next if row['itemId'] ? row['itemId'].to_s != id.to_s : row['itemType'].to_s != kind
          next unless Predicate.test(row['predicate'], facts)

          alter!(out, row)
        end
      end

      def self.alter!(held, row)
        property = PROPERTIES[row['property'].to_s]

        return unless property

        field = property['field']
        mode = row['mode'].to_s

        held[field] = if property['list']
                        listed(held[field], mode, row['value'])
                      elsif property['step']
                        stepped(held[field], mode, row['value'])
                      elsif mode == 'override'
                        row['value']
                      else
                        Paths::MODES[mode] ? Paths::MODES[mode].call(held[field].to_i, row['value'].to_i) : held[field]
                      end
      end

      def self.listed(held, mode, value)
        words = Array(held)
        word = value.to_s

        case mode
        when 'add' then (words + [ word ]).uniq
        when 'remove' then words.reject { |one| Domains.slug(one) == Domains.slug(word) }
        when 'override' then Array(value)
        else words
        end
      end

      # A die size, one step at a time: `upgrade` a d8 to a d10. `override` names the faces.
      def self.stepped(held, mode, value)
        case mode
        when 'upgrade' then Damage.step(held, 1)
        when 'downgrade' then Damage.step(held, -1)
        when 'override' then value ? "d#{value}" : held
        else held
        end
      end

      # ------------------------------------------------------------------------------
      # The things that are altered

      # A weapon's attack descriptor, as an alteration leaves it. `striking` and `rune` are what the
      # descriptor calls the runes an alteration calls `runes-striking` and `runes-potency`.
      def self.attack(char, descriptor)
        held = descriptor.merge('potency' => descriptor['rune'], 'material' => Array(descriptor['materials']).first)
        altered = apply(char, 'weapon', held, :id => descriptor['id'],
                                              :options => Pf2eCombat.attack_options(descriptor, char))

        altered.merge('rune' => altered['potency'].to_i,
                      'materials' => [ altered['material'] ].compact | Array(descriptor['materials']))
               .reject { |field, _| %w{potency material}.include?(field) }
      end

      # The armour a character is wearing, as an alteration leaves it: what AC, the penalties and the
      # runes read. Nil when they wear none.
      Worn = Struct.new(:name, :category, :ac_bonus, :dex_cap, :check_penalty, :speed_penalty, :min_str,
                        :traits, :potency, :resilient, keyword_init: true)

      def self.armor(char)
        armor = Pf2eCombat.get_equipped_armor(char)

        return nil unless armor

        held = { 'ac_bonus' => armor.ac_bonus.to_i, 'dex_cap' => armor.dex_cap.to_i,
                 'check_penalty' => armor.check_penalty.to_i, 'speed_penalty' => armor.speed_penalty.to_i,
                 # Foundry's strength requirement is a modifier; this catalogue records a score.
                 'strength' => (armor.min_str.to_i - 10) / 2,
                 'traits' => Array(armor.traits), 'category' => armor.category,
                 'potency' => Pf2egear.get_rune_value(armor, 'fundamental', 'potency').to_i,
                 'resilient' => Pf2egear.get_rune_value(armor, 'fundamental', 'power').to_i }

        # What the armour answers to, as an item and as the thing the character wears: Forgefather's Seal
        # hardens light and medium armour, and says so as `armor:category:light`.
        facts = [ "category:#{Domains.slug(armor.category)}" ] +
                held['traits'].map { |one| "trait:#{Domains.slug(one)}" }
        altered = apply(char, 'armor', held, :id => armor.id,
                                             :options => facts.flat_map { |one| [ "item:#{one}", "armor:#{one}" ] })

        Worn.new(:name => armor.name, :category => altered['category'], :ac_bonus => altered['ac_bonus'].to_i,
                 :dex_cap => altered['dex_cap'].to_i, :check_penalty => altered['check_penalty'].to_i,
                 :speed_penalty => altered['speed_penalty'].to_i,
                 :min_str => armor.min_str.to_i.positive? ? 10 + (2 * altered['strength'].to_i) : 0,
                 :traits => altered['traits'], :potency => altered['potency'].to_i,
                 :resilient => altered['resilient'].to_i)
      end

      # A condition's value and maximum, as an alteration leaves them: an effect that makes a frightened
      # character's fear worse raises its value while it lasts.
      def self.condition(char, name, value)
        altered = apply(char, 'condition', { 'value' => value },
                        :options => [ "item:slug:#{Domains.slug(name)}", "item:type:condition" ])

        altered['value']
      end
    end
  end
end
