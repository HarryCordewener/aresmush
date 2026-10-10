module AresMUSH
  module Pf2e

    # Disarm, Grapple, Reposition, Shove and Trip are tried on nothing more than one size larger than
    # whoever tries them. Titan Wrestler makes that two sizes, and three for someone legendary in
    # Athletics.
    module SizeLimit

      ACTIONS = %w{disarm grapple reposition shove trip}.freeze
      WORDS = { 1 => 'one size', 2 => 'two sizes', 3 => 'three sizes' }.freeze
      FEAT = 'Titan Wrestler'.freeze

      # How many sizes larger than them their target may be.
      def self.most(holder)
        return 1 unless Actions.owned?(holder, FEAT)

        Actors.of(holder).proficiency('skill', 'Athletics') == 'legendary' ? 3 : 2
      end

      # The refusal of an action aimed at something too large for it, or nothing.
      def self.refusal(scene, name)
        return nil unless scene.target && ACTIONS.include?(Domains.slug(name))

        most = most(scene.actor.holder)
        larger = MonsterAbilities.size_of(scene.target.holder) - MonsterAbilities.size_of(scene.actor.holder)

        return nil if larger <= most

        Err.new(:too_large, 'pf2e.act_too_large', 'action' => name, 'target' => scene.target.label,
                                                  'actor' => scene.actor.label, 'most' => WORDS[most])
      end
    end
  end
end
