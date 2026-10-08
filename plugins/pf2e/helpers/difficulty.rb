module AresMUSH
  module Pf2e

    # How hard an encounter is for its party, and what PF2e would give for it - GM Core's own tables, in
    # `pf2e_rewards.yml`.
    #
    # Each creature is worth XP by its level against the party's; the encounter's XP against the budget
    # for its party size gives its threat. The XP it awards is always that of a group of four, so a bigger
    # party's extra budget comes off again. Treasure is GM Core's Treasure by Encounter for the threat.
    # Staff decide what is actually paid; this only recommends.
    module Difficulty

      def self.table
        Global.read_config('pf2e_rewards') || {}
      end

      # The party's level: what the GM set, or the characters' average, rounded down.
      def self.party_level(levels, set = nil)
        return set.to_i if set.to_i.positive?
        return 0 if levels.empty?

        levels.sum / levels.size
      end

      # A creature more than 4 levels below the party is worth nothing; one more than 4 above is worth
      # the most the table gives, and is past what it plans for.
      def self.creature_xp(level, party_level, table = self.table)
        difference = level.to_i - party_level.to_i

        return 0 if difference < -4

        table['creature_xp'][[ difference, 4 ].min].to_i
      end

      def self.budgets(size, table = self.table)
        table['threats'].map do |row|
          row.merge('budget' => row['budget'] + (size - 4) * row['adjustment'])
        end
      end

      def self.of(creature_levels, character_levels, level: nil, table: self.table)
        party = party_level(character_levels, level)
        size = character_levels.size
        xp = creature_levels.sum { |one| creature_xp(one, party, table) }
        budgets = budgets(size, table)
        rated = budgets.find { |row| xp <= row['budget'] } || budgets.last.merge('name' => 'beyond extreme')

        { 'xp' => xp, 'threat' => rated['name'], 'budget' => rated['budget'], 'party_level' => party,
          'party_size' => size, 'award' => size.zero? ? 0 : [ xp - (size - 4) * rated['adjustment'], 0 ].max,
          'past_the_table' => creature_levels.any? { |one| one.to_i - party > 4 } }
      end

      # What GM Core's Treasure by Encounter gives for this threat at this level, in gold, for four; and what
      # its treasure by level adds per character beyond four over a whole level.
      def self.treasure(rated, table = self.table)
        level = rated['party_level'].to_i.clamp(1, 20)
        row = table['treasure_by_encounter'][level] || {}

        { 'gp' => row[rated['threat'].to_s.sub('beyond ', '')].to_i,
          'per_additional_pc' => rated['party_size'] > 4 ? table['currency_per_additional_pc'][level].to_i : 0 }
      end

      # `Moderate: 80 XP of 80 for a party of 4 at level 3.`
      def self.shown(encounter)
        line(of_encounter(encounter), encounter.party_level.to_i.positive?)
      end

      # A threat is measured against a party, so with no character in it there is none to tell.
      def self.line(rated, set)
        return t('pf2e.difficulty_no_party') if rated['party_size'].to_i.zero?

        t('pf2e.difficulty_line', :threat => rated['threat'].capitalize, :xp => rated['xp'], :budget => rated['budget'],
                                  :size => rated['party_size'], :level => rated['party_level'],
                                  :set => set ? t('pf2e.difficulty_set') : '')
      end

      # What PF2e recommends for the encounter, and what staff have paid.
      def self.recommended(encounter)
        rated = of_encounter(encounter)
        treasure = treasure(rated)
        paid = (encounter.awarded || {}).map do |name, held|
          t('pf2e.award_paid_line', :name => name, :xp => held['xp'].to_i,
                                    :money => Pf2egear.display_money(held['money'].to_i).strip)
        end

        accomplishments = table['accomplishment_xp'].map { |kind, xp| "#{kind} #{xp}" }.join(', ')
        lines = [ t('pf2e.award_title', :id => encounter.id), shown(encounter),
                  t('pf2e.award_xp', :xp => rated['award'], :accomplishments => accomplishments),
                  t('pf2e.award_treasure', :gp => treasure['gp']) ]
        lines << t('pf2e.award_extra_pc', :gp => treasure['per_additional_pc']) if treasure['per_additional_pc'].positive?
        lines << t('pf2e.award_past_table') if rated['past_the_table']
        lines << t('pf2e.award_how', :id => encounter.id)

        (lines + (paid.empty? ? [ t('pf2e.award_none_paid') ] : paid)).join('%r')
      end

      # An encounter as it stands.
      def self.of_encounter(encounter)
        listed = Combatants.all(encounter).select(&:holder)
        creatures, characters = listed.partition(&:creature?)

        of(creatures.map { |one| one.holder.pf2_level }, characters.map { |one| one.holder.pf2_level },
           :level => encounter.party_level)
      end
    end
  end
end
