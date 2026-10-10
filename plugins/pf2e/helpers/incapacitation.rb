module AresMUSH
  module Pf2e

    # The incapacitation trait. What could take a creature out of a fight at a stroke - Charm, Paralyze,
    # a basilisk's gaze - is weaker against one too strong for it: more than twice a spell's rank in
    # level, or of higher level than the creature or item whose effect it is. Such a creature treats its
    # own check to resist as one degree better, and a check made against it as one degree worse.
    module Incapacitation

      TRAIT = 'incapacitation'.freeze

      # Whether the target is too strong for this to take it out. `rank` is a spell's; `source` is who or
      # what does anything else.
      def self.spares?(traits, target, rank: nil, source: nil)
        return false unless Array(traits).map { |trait| Domains.slug(trait) }.include?(TRAIT)

        level = target.pf2_level.to_i

        return level > rank.to_i * 2 if rank

        source ? level > source.pf2_level.to_i : false
      end

      # How far the outcome moves: for the target's own roll (`:theirs`), or for a roll made against them
      # (`:against`).
      def self.shift(spared, whose)
        return 0 unless spared

        whose == :theirs ? 1 : -1
      end
    end
  end
end
