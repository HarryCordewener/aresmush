module AresMUSH
  module Pf2e

    # PF2e's bonus arithmetic: a figure is a base plus a list of modifiers, and the modifier's type
    # decides which of them count.
    #
    # The type is the whole reason this is not a sum. Two +1 item bonuses are one +1, because the rules
    # say the highest of a type applies and the rest do not - so a character wearing a ring and under a
    # spell that both grant an item bonus gets the better of the two, not their total.
    #
    # A modifier that does not count is switched off rather than dropped. That is what lets a sheet
    # print "+2 item (ring of protection), +1 item (spell, overridden)" instead of a bare total, and it
    # is the difference between a player being able to check our arithmetic and having to trust it.
    module Modifiers

      # Foundry's seven (`actor/modifiers.ts:29`), which are the rules' own.
      TYPES = %w{ability circumstance item potency proficiency status untyped}.freeze

      UNTYPED = 'untyped'.freeze
      ABILITY = 'ability'.freeze

      # Which of a type's modifiers count. A row per type that does not follow the ordinary rule, and
      # the ordinary rule for everything else.
      STACKING = {
        # Untyped modifiers always stack: each is its own thing and none overrides another.
        UNTYPED => ->(group) { group },

        # Attribute modifiers never stack with each other - the best one applies alone. This is what
        # makes "use your best attribute for AC" need no special case: offer both, take the better.
        ABILITY => ->(group) { [ group.max_by { |row| value_of(row) } ].compact }
      }.freeze

      # The highest bonus and the lowest penalty of the type both apply. A zero is neither, so it
      # counts for nothing either way.
      ORDINARY = lambda do |group|
        bonuses = group.select { |row| value_of(row) > 0 }
        penalties = group.select { |row| value_of(row) < 0 }

        [ bonuses.max_by { |row| value_of(row) }, penalties.min_by { |row| value_of(row) } ].compact
      end

      # Applies the rules that change a modifier rather than adding one, before any stacking decides which
      # of them count - a modifier raised from +1 to +3 has to be raised before it is compared with the
      # others, or the comparison is against the wrong number.
      #
      # An adjustment with no slug reaches every modifier the statistic has
      # (`rules/helpers.ts:47`); one with a slug reaches only the modifier of that name. `suppress` drops
      # the modifier outright, and `maxApplications` caps how many modifiers one adjustment may change.
      def self.adjust(modifiers, adjustments)
        counts = {}

        Array(modifiers).each_with_object([]) do |row, out|
          applicable = Array(adjustments).select { |one| reaches?(one, row, counts) }

          next if applicable.any? { |one| one['suppress'] }

          out << applicable.reduce(row) { |held, one| applied(held, one, counts) }
        end
      end

      # An adjustment may ask about the modifier it is adjusting rather than about the character: a feat
      # that lessens armour's speed penalty is written as `penalty:slug:armor-speed-penalty` and
      # `{lte: ["penalty:value", -5]}`. Those facts are true of the modifier, so they are supplied here
      # and nowhere else.
      def self.facts_of(row)
        kind = value_of(row).negative? ? 'penalty' : 'bonus'

        [ kind, 'modifier' ].flat_map do |prefix|
          [ "#{prefix}:slug:#{row['slug']}",
            "#{prefix}:type:#{row['type']}",
            "#{prefix}:value:#{value_of(row)}" ]
        end
      end

      def self.reaches?(adjustment, row, counts)
        return false unless adjustment['slug'].nil? || adjustment['slug'].to_s == row['slug'].to_s
        return false unless Predicate.test(adjustment['when'], facts_of(row) + Array(adjustment['held']))

        limit = adjustment['max']

        limit.nil? || counts.fetch(adjustment.object_id, 0) < limit.to_i
      end

      def self.applied(row, adjustment, counts)
        counts[adjustment.object_id] = counts.fetch(adjustment.object_id, 0) + 1

        return row if adjustment['value'].nil?

        changed = Paths::MODES.fetch(adjustment['mode'], Paths::MODES['override'])
                              .call(value_of(row), adjustment['value'])

        row.merge('value' => changed.to_i,
                  'source' => adjustment['relabel'] || row['source'])
      end

      def self.stack(modifiers)
        rows = Array(modifiers).map { |row| row.merge('enabled' => false) }

        rows.group_by { |row| type_of(row) }.each_pair do |type, group|
          (STACKING[type] || ORDINARY).call(group).each { |row| row['enabled'] = true }
        end

        rows
      end

      def self.total(modifiers)
        Array(modifiers).select { |row| row['enabled'] }.sum { |row| value_of(row) }
      end

      # A figure and its arithmetic together, which is what a sheet wants: a caller that only needs the
      # number reads `total`, and one that shows a player where it came from reads `modifiers`.
      def self.breakdown(base, modifiers)
        stacked = stack(modifiers)

        { 'base' => base, 'modifiers' => stacked, 'total' => base + total(stacked) }
      end

      def self.value_of(row)
        row['value'].to_i
      end

      # An unrecognised type is treated as untyped, and says so. Untyped is the permissive reading -
      # it always counts - so a config typo shows up as a number that is too big rather than a bonus
      # that silently went missing.
      def self.type_of(row)
        type = row['type'].to_s.downcase

        return type if TYPES.include?(type)

        Global.logger.warn "PF2e modifier from #{row['source'].inspect} has unknown type #{row['type'].inspect}; treating as untyped."

        UNTYPED
      end
    end
  end
end
