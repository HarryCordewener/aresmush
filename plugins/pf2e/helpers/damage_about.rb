module AresMUSH
  module Pf2e

    # What is so of some damage beyond its kind, for whoever it lands on to weigh against what they are
    # immune to, weak to and resist (`IWR.facts`): what dealt it, what that is made of, and how it came.
    module DamageAbout

      # What a player may say of their weapon after a slash, which the game cannot see: `/silver`,
      # `/cold iron`, `/holy`.
      # Asked for rather than held, because `IWR` loads after this.
      def self.sayable
        IWR::MATERIALS + %w{holy unholy magical ghost-touch}
      end

      # Where an ability's words put its damage on everyone in a space.
      AREA = /\b(?:cone|burst|emanation|line)\b|\beach (?:creature|enemy)\b|\bcreatures? (?:in|within)\b/i

      def self.traits(list)
        Array(list).map { |trait| "item:trait:#{Domains.slug(trait)}" }
      end

      # A Strike's: the weapon's traits and group, whether it is magical or a fist, and what was said of it.
      def self.of_attack(attack, options = [])
        slugs = Array(attack['traits']).map { |trait| Domains.slug(trait) }
        about = traits(slugs) + [ 'item:type:weapon' ]
        about << "item:group:#{Domains.slug(attack['group'])}" unless attack['group'].to_s.empty?
        about << 'item:category:unarmed' if attack['unarmed'] || slugs.include?('unarmed')
        about << 'item:magical' if attack['rune'].to_i.positive? || slugs.include?('magical')

        about + said(options)
      end

      # What was said of the damage, in the words that are about damage.
      def self.said(words)
        Array(words).map { |word| Domains.slug(word.to_s.split(':').last) }.select { |word| sayable.include?(word) }
                    .flat_map { |word| IWR.fact(word) }
      end

      # That something is a spell, and which: what an immunity to magic asks, and what it excepts.
      def self.spell(name)
        [ 'item:type:spell', "item:slug:#{Domains.slug(name)}" ]
      end

      # A spell's: magical, with its traits, and dealt to an area where it has one.
      def self.of_spell(mechanics, name = nil)
        (name ? spell(name) : [ 'item:type:spell' ]) + [ 'item:magical' ] + traits(mechanics['traits']) +
          (mechanics['area'].to_s.empty? ? [] : [ 'area-damage' ])
      end

      # A creature's ability's: its traits, and an area where its words give it one.
      def self.of_ability(ability)
        slugs = Array(ability['traits']).map { |trait| Domains.slug(trait) }
        magical = (slugs & (IWR::TRADITIONS + [ 'magical' ])).any?

        traits(slugs) + (magical ? [ 'item:magical' ] : []) + (ability['text'].to_s.match?(AREA) ? [ 'area-damage' ] : [])
      end
    end
  end
end
