module AresMUSH
  module Pf2e

    # An aura: an emanation around a character that puts effects on whoever is inside it - a champion's
    # aura on their allies, Silence on everyone.
    #
    # Foundry's `Aura` (`rule-element/aura.ts`) knows where everyone stands and applies its effects as
    # creatures enter and leave. This engine has no positions, so it cannot know who is inside; what it
    # can know is everything else. `Auras.of` says what auras a character projects and what each would do,
    # and `enter` and `leave` apply and end those effects on someone a DM says is inside or has left -
    # following the aura's own terms for whom it affects. When the aura itself ends, everything it put on
    # anyone ends with it.
    module Auras

      # Whom an aura's effect reaches, by how the one inside stands to the one projecting it.
      AFFECTS = { 'allies' => %w{ally}, 'enemies' => %w{enemy}, 'all' => %w{ally enemy} }.freeze

      # Every aura the character projects: its slug, its radius, and the effects it puts on others.
      def self.of(char)
        options = Effects.character_facts(char)
        context = Effects.context(char)

        ActiveEffects.on(char).flat_map do |effect|
          item = ActiveEffects.instance_item(effect)

          Array(ActiveEffects.info(effect.name)['rules']).select { |row| row['key'] == 'Aura' }.map do |row|
            row = Rules.resolved(row, Effects.source(effect.name, [], 'item' => item), context)

            next nil unless row && Predicate.test(row['predicate'], options)

            { 'slug' => row['slug'] || Domains.slug(effect.name), 'effect' => effect,
              'radius' => Formula.value(row['radius'] || 0, context.merge('item' => item)).to_i,
              'traits' => Array(row['traits']),
              'effects' => Array(row['effects']).map { |one| reach(one) }.compact }
          end.compact
        end
      end

      def self.reach(one)
        catalogue, name = Grants.target(one['uuid'])

        return nil unless catalogue == 'effects' && ActiveEffects.catalogue.key?(name)

        { 'name' => name, 'affects' => (one['affects'] || 'all').to_s, 'self' => one['includesSelf'] != false,
          'predicate' => one['predicate'], 'leaves_on_exit' => one['removeOnExit'] != false }
      end

      # The origin an effect records when an aura put it there, so the aura can find it again.
      def self.origin(emitter, aura)
        "#{Pf2e.holder_key(emitter)}:#{aura['slug']}"
      end

      # Someone is inside one of the emitter's auras. `relation` is `ally` or `enemy`; the emitter
      # themselves is inside their own aura, and only an effect that includes its emitter reaches them.
      def self.enter(emitter, target, slug, relation = 'ally')
        aura = of(emitter).find { |one| one['slug'] == slug }

        return Err.new(:no_aura, 'pf2e.aura_not_found', 'aura' => slug, 'name' => emitter.name) unless aura

        mine = Pf2e.holder_key(emitter) == Pf2e.holder_key(target)
        facts = Effects.character_facts(target)

        applied = aura['effects'].select { |one|
          (mine ? one['self'] : AFFECTS.fetch(one['affects'], []).include?(relation.to_s)) &&
            Predicate.test(one['predicate'], facts)
        }.reject { |one| inside?(target, one['name'], origin(emitter, aura)) }.map do |one|
          effect = ActiveEffects.apply(target, one['name'], :applied_by => emitter.name,
                                                             :encounter => aura['effect'].encounter).state
          effect.update(:aura_of => origin(emitter, aura), :level => aura['effect'].level)
          effect
        end

        Ok.new(:state => applied)
      end

      # Someone has left the aura: what it put on them ends, unless the aura says it stays.
      def self.leave(emitter, target, slug)
        aura = of(emitter).find { |one| one['slug'] == slug }
        leaving = aura ? aura['effects'].select { |one| one['leaves_on_exit'] }.map { |one| one['name'] } : []

        ended = ActiveEffects.on(target).select { |effect|
          effect.aura_of == (aura ? origin(emitter, aura) : "#{Pf2e.holder_key(emitter)}:#{slug}") &&
            (aura.nil? || leaving.include?(effect.name))
        }

        ended.each { |effect| ActiveEffects.remove(target, effect) }

        Ok.new(:state => ended.map(&:name))
      end

      def self.inside?(target, name, origin)
        ActiveEffects.on(target).any? { |effect| effect.name == name && effect.aura_of == origin }
      end

      # The effect projecting an aura has ended: everything the aura put on anyone ends with it.
      def self.dispelled(emitter, effect)
        slugs = Array(ActiveEffects.info(effect.name)['rules']).select { |row| row['key'] == 'Aura' }
                                                               .map { |row| row['slug'] || Domains.slug(effect.name) }

        slugs.flat_map { |slug| Pf2eEffect.find(:aura_of => "#{Pf2e.holder_key(emitter)}:#{slug}").to_a }.each do |one|
          ActiveEffects.remove(one.holder, one) if one.holder
        end
      end
    end
  end
end
