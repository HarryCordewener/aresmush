module AresMUSH
  module Pf2e

    # What it takes to recall what a creature is: the DC of its level, harder for one that is rarer, and
    # the skills that know its kind.
    module Knowledge

      # The DC of each level, from -1 to 25.
      LEVEL_DCS = [ 13, 14, 15, 16, 18, 19, 20, 22, 23, 24, 26, 27, 28, 30, 31, 32, 34, 35, 36, 38, 39, 40, 42, 44, 46, 48, 50 ].freeze

      RARITY = { 'uncommon' => 2, 'rare' => 5, 'unique' => 10 }.freeze

      # Which skills identify a creature, by its traits.
      SKILLS = {
        'aberration' => %w{Occultism}, 'animal' => %w{Nature}, 'astral' => %w{Occultism}, 'beast' => %w{Arcana Nature},
        'celestial' => %w{Religion}, 'construct' => %w{Arcana Crafting}, 'dragon' => %w{Arcana}, 'dream' => %w{Occultism},
        'elemental' => %w{Arcana Nature}, 'ethereal' => %w{Occultism}, 'fey' => %w{Nature}, 'fiend' => %w{Religion},
        'fungus' => %w{Nature}, 'humanoid' => %w{Society}, 'monitor' => %w{Religion}, 'ooze' => %w{Occultism},
        'plant' => %w{Nature}, 'shade' => %w{Religion}, 'spirit' => %w{Occultism}, 'time' => %w{Occultism},
        'undead' => %w{Religion}
      }.freeze

      # What knows of a creature with no kind of its own.
      OTHERWISE = %w{Society}.freeze

      def self.level_dc(level)
        LEVEL_DCS[(level.to_i + 1).clamp(0, LEVEL_DCS.size - 1)]
      end

      def self.dc(level, rarity = nil)
        level_dc(level) + RARITY[rarity.to_s.downcase].to_i
      end

      def self.skills(traits)
        found = Array(traits).flat_map { |trait| SKILLS[Domains.slug(trait)] || [] }.uniq.sort

        found.empty? ? OTHERWISE : found
      end

      # The DC to recall what someone is, and the skills that would know.
      def self.of(holder)
        rarity = Actors.of(holder).creature? ? holder.stat_block['rarity'] : nil

        { 'dc' => dc(holder.pf2_level, rarity), 'skills' => skills(holder.pf2_traits) }
      end
    end
  end
end
