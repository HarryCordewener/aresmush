module AresMUSH
  module Pf2e

    # Shield Block, the reaction to a hit just taken while a shield is raised: the shield takes its
    # Hardness off the hit's physical damage, and the shield and its bearer each take what is left.
    #
    # The hit has already been dealt when the player answers it, so whoever takes physical damage behind
    # a raised shield keeps the hit on them - what they had before it, what it dealt, and whether it was
    # a critical hit - until the next hit or the block, and while nothing else has moved their hit points. Blocking puts back what they had and deals the
    # hit again less the Hardness, so being knocked out by it is undone when the block saves them.
    module ShieldBlock

      NAME = 'Shield Block'.freeze

      RAISE = 'Raise a Shield'.freeze

      PHYSICAL = %w{bludgeoning piercing slashing}.freeze

      # The shield they could block with: equipped - or their stat block's - raised, and not broken.
      def self.raised(holder)
        return nil unless ActiveEffects.named_on(holder, 'Effect: Raise a Shield').any?

        shield = Actors.of(holder).shield

        shield && !broken?(shield) ? shield : nil
      end

      # Why someone cannot Raise a Shield - none equipped, or the one they have is broken - or nil. A
      # creature whose stat block gives it none raises what its GM says it has.
      def self.cannot_raise(holder)
        actor = Actors.of(holder)
        shield = actor.shield

        return nil if shield.nil? && actor.creature?
        return Err.new(:no_shield, 'pf2e.raise_shield_none') unless shield
        return Err.new(:broken_shield, 'pf2e.raise_shield_broken', 'shield' => shield.nickname || shield.name) if broken?(shield)

        nil
      end

      # Broken at half its Hit Points, its Broken Threshold.
      def self.broken?(shield)
        shield.hp.to_i.positive? && shield.damage.to_i * 2 >= shield.hp.to_i
      end

      def self.physical?(type)
        PHYSICAL.include?(Domains.slug(type))
      end

      # What a hit can put back: nil for someone with no raised shield.
      def self.before(holder)
        return nil unless raised(holder)

        damage, temp_hp = Actors.of(holder).standing

        { 'damage' => damage, 'temp_hp' => temp_hp, 'conditions' => holder.pf2_conditions || {} }
      end

      def self.remember(holder, before, taken, physical, critical)
        TurnState.write(holder, 'struck' => { 'before' => before, 'taken' => taken, 'physical' => physical,
                                              'critical' => critical, 'after' => AttackAnswers.standing(holder) })
      end

      # Whether to offer the block: they have it, their reaction is ready, and the hit is on them.
      def self.offered?(holder)
        hit = TurnState.of(holder)['struck']

        Actors.of(holder).has_action?(NAME) && !TurnState.turn(holder)['reaction'] && hit &&
          hit['after'] == AttackAnswers.standing(holder) && raised(holder)
      end

      def self.block(scene, out)
        holder = scene.actor.holder
        shield = raised(holder)
        hit = TurnState.of(holder)['struck']

        return Err.new(:no_raised_shield, 'pf2e.shield_block_no_shield') unless shield
        return Err.new(:nothing_to_block, 'pf2e.shield_block_no_hit') unless hit
        return Err.new(:too_late, 'pf2e.answer_too_late', 'action' => NAME) unless hit['after'] == AttackAnswers.standing(holder)

        blocked = [ shield.hardness.to_i, hit['physical'].to_i ].min
        rest = hit['physical'].to_i - blocked

        Actors.of(holder).stand_at(hit['before']['damage'], hit['before']['temp_hp'])
        holder.update(:pf2_conditions => hit['before']['conditions'])
        Harm.damage(holder, hit['taken'].to_i - blocked, nil, :critical => hit['critical']) if hit['taken'].to_i > blocked
        shield.update(:damage => shield.damage.to_i + rest)
        TurnState.write(holder, 'struck' => nil)

        name = shield.nickname || shield.name
        out['lines'] << Telling.event('pf2e.shield_blocked', :actor => scene.actor.label, :shield => name,
                                                            :blocked => blocked, :taken => hit['taken'].to_i - blocked,
                                                            :rest => rest)
        if shield.hp.to_i.positive? && shield.damage.to_i >= shield.hp.to_i
          out['lines'] << Telling.event('pf2e.shield_destroyed', :shield => name)
        elsif broken?(shield)
          out['lines'] << Telling.event('pf2e.shield_broken', :shield => name)
        end
        out['gm'] << Telling.event('pf2e.act_hp_left', :target => scene.actor.label, :hp => Harm.hit_points(holder))

        Ok.new(:state => out)
      end
    end
  end
end
