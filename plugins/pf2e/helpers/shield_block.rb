module AresMUSH
  module Pf2e

    # Shield Block, the reaction to a hit just taken while a shield is raised: the shield takes its
    # Hardness off the hit's physical damage, and the shield and its bearer each take what is left.
    #
    # The hit has already been dealt when the player answers it, so whoever takes physical damage behind
    # a raised shield keeps the hit on them - what they had before it, what it dealt, and whether it was
    # a critical hit - until the next hit or the block. Blocking puts back what they had and deals the
    # hit again less the Hardness, so being knocked out by it is undone when the block saves them.
    module ShieldBlock

      NAME = 'Shield Block'.freeze

      PHYSICAL = %w{bludgeoning piercing slashing}.freeze

      # The shield they could block with: equipped, raised, and not broken.
      def self.raised(holder)
        return nil unless Actors.of(holder).carries_items?
        return nil unless ActiveEffects.named_on(holder, 'Effect: Raise a Shield').any?

        shield = Pf2egear::Inventory.held(holder, 'shields').find(&:equipped)

        shield && !broken?(shield) ? shield : nil
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

        hp = Pf2eHP.get_hp_obj(holder)

        { 'damage' => hp.damage.to_i, 'temp_hp' => hp.temp_hp.to_i, 'conditions' => holder.pf2_conditions || {} }
      end

      def self.remember(holder, before, taken, physical, critical)
        TurnState.write(holder, 'struck' => { 'before' => before, 'taken' => taken, 'physical' => physical,
                                              'critical' => critical })
      end

      # Whether to offer the block: they have it, their reaction is ready, and the hit is on them.
      def self.offered?(holder)
        Actions.owned?(holder, NAME) && !TurnState.turn(holder)['reaction'] && TurnState.of(holder)['struck']
      end

      def self.block(scene, out)
        holder = scene.actor.holder
        shield = raised(holder)
        hit = TurnState.of(holder)['struck']

        return Err.new(:no_raised_shield, 'pf2e.shield_block_no_shield') unless shield
        return Err.new(:nothing_to_block, 'pf2e.shield_block_no_hit') unless hit

        blocked = [ shield.hardness.to_i, hit['physical'].to_i ].min
        rest = hit['physical'].to_i - blocked

        Pf2eHP.get_hp_obj(holder).update(:damage => hit['before']['damage'], :temp_hp => hit['before']['temp_hp'])
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
