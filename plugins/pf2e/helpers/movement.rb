module AresMUSH
  module Pf2e

    # A character's speeds: Speed and what makes it up, the special movement types and where each
    # comes from, and the status bonuses that depend on the moment.
    #
    # Worked out whenever they are shown rather than stored. The ancestry's Speed and a heritage's
    # movement are what chargen wrote to pf2_movement; everything else is a `movement` list on a feat,
    # a feat choice's option, or the class, read from config. So speeds follow level and feats, and a
    # rollback has nothing to undo.
    #
    # A `movement` entry is one of:
    #
    #   increase: 5          land Speed, untyped; `group:` makes only the largest in a group count
    #   swim: 15             a movement type at that Speed, or `land` for equal to your Speed
    #   status_bonus: 10     with `when:` - unarmored, panache or no_panache
    #
    # with an optional `prereq`, read by meets_prereqs?, and on a class entry a `level` and a `source`.
    module Movement

      TYPES = %w(swim climb fly burrow).freeze

      # What each status bonus depends on, and how it reads. Only `unarmored` can be judged - by the
      # armor equipped - so it is the only one ever added to Speed; panache is not tracked.
      WHEN = {
        'unarmored' => "+%{bonus}-foot status bonus when you're not wearing armor",
        'panache' => "+%{bonus}-foot status bonus to your Speeds while you have panache",
        'no_panache' => "+%{bonus}-foot status bonus to your Speeds while you don't have panache"
      }.freeze

      # ------------------------------------------------------------------------------
      # Working them out
      # ------------------------------------------------------------------------------

      # `entries` are movement entries each carrying its `source`, already checked against their
      # prereqs. `combat` is csheet's view: armor's penalty applies, and the unarmored bonus does when
      # no armor is worn. `armor` is { name, penalty, min_str, category }, or nil for none.
      def self.compute(ancestry_speed, entries, combat: false, armor: nil, strength: 10)
        parts = [ [ 'ancestry', ancestry_speed.to_i, :base ] ]

        increases(entries).each { |source, amount| parts << [ source, amount, :increase ] }

        permanent = parts.sum { |_s, amount, _k| amount }
        conditional = conditional_bonuses(entries)

        unarmored = armor.nil? || armor['category'].to_s.casecmp?('unarmored')
        penalty = combat ? armor_penalty(armor, strength) : 0

        if combat && unarmored && conditional['unarmored']
          parts << [ conditional['unarmored']['source'], conditional['unarmored']['bonus'], :status ]
        end

        parts << [ armor['name'], penalty, :armor ] if penalty < 0

        total = parts.sum { |_s, amount, _k| amount }

        {
          # The penalty is already among the parts; what it adds is the 5-foot floor.
          'land' => penalty < 0 ? [ total, 5 ].max : total,
          'parts' => parts,
          'special' => special(entries, permanent, penalty),
          'conditional' => WHEN.keys.map { |key| conditional[key] }.compact
        }
      end

      # Increases as [ source, amount ]. Within a group only the largest counts, since those feats
      # say their increase is not cumulative with the others'.
      def self.increases(entries)
        grouped, loose = entries.select { |e| e['increase'] }.partition { |e| e['group'] }

        best = grouped.group_by { |e| e['group'] }.values.map { |group| group.max_by { |e| e['increase'].to_i } }

        (loose + best).map { |e| [ e['source'], e['increase'].to_i ] }
      end

      # Each movement type at its best source.
      def self.special(entries, land, penalty)
        TYPES.filter_map do |type|
          offered = entries.select { |e| e.key?(type) }.map do |e|
            speed = e[type].to_s.casecmp?('land') ? land : e[type].to_i

            { 'type' => type, 'speed' => speed, 'source' => e['source'] }
          end

          best = offered.max_by { |o| o['speed'] }

          best && best.merge('speed' => penalized(best['speed'], penalty))
        end
      end

      # The highest status bonus of each kind, since status bonuses do not stack.
      def self.conditional_bonuses(entries)
        entries.select { |e| e['status_bonus'] && WHEN.key?(e['when'].to_s) }
          .group_by { |e| e['when'].to_s }
          .transform_values do |list|
            top = list.max_by { |e| e['status_bonus'].to_i }

            { 'when' => top['when'].to_s, 'bonus' => top['status_bonus'].to_i, 'source' => top['source'] }
          end
      end

      # Armor's Speed penalty, 5 feet less once the character meets its Strength.
      def self.armor_penalty(armor, strength)
        return 0 unless armor

        penalty = armor['penalty'].to_i
        penalty += 5 if penalty < 0 && strength.to_i >= armor['min_str'].to_i

        [ penalty, 0 ].min
      end

      # A penalty never takes a speed below 5 feet.
      def self.penalized(speed, penalty)
        penalty < 0 ? [ speed + penalty, 5 ].max : speed
      end

      # ------------------------------------------------------------------------------
      # Reading them off a character
      # ------------------------------------------------------------------------------

      def self.for(char, combat: false)
        stored = char.pf2_movement || {}
        armor = combat ? Pf2eCombat.get_equipped_armor(char) : nil

        compute(stored['base_speed'], entries_for(char),
          :combat => combat,
          :armor => armor && {
            'name' => armor.name, 'penalty' => armor.speed_penalty,
            'min_str' => armor.min_str, 'category' => armor.category
          },
          :strength => Pf2eAbilities.get_score(char, 'Strength'))
      end

      def self.entries_for(char)
        level = char.pf2_level.to_i

        (heritage_entries(char) + feat_entries(char) + class_entries(char, level)).select do |entry|
          entry['prereq'].nil? || Pf2e.meets_prereqs?(char, entry['prereq'], level)
        end
      end

      # What chargen wrote beside the ancestry's Speed.
      def self.heritage_entries(char)
        heritage = char.pf2_base_info['heritage']

        (char.pf2_movement || {}).filter_map do |key, speed|
          type = key.to_s.downcase
          next unless TYPES.include?(type)

          { type => speed.to_i, 'source' => "#{heritage} heritage" }
        end
      end

      # From the feats on the sheet, and from the option chosen for a feat's choice.
      def self.feat_entries(char)
        config = Global.read_config('pf2e_feats') || {}

        (char.pf2_feats || {}).values.flatten.uniq.flat_map do |name|
          key = config.keys.find { |k| k.to_s.casecmp?(name.to_s) }
          details = key && config[key]
          next [] unless details.is_a?(Hash)

          options = ((details['feat_choice'] || {})['options'] || {})
          chosen = options.is_a?(Hash) ? Pf2e.choice_labels_for(char, key) : []

          lists = [ details['movement'] ] + chosen.map { |label| (options[label] || {})['movement'] }

          lists.compact.flatten.map { |entry| { 'source' => key }.merge(entry) }
        end
      end

      def self.class_entries(char, level)
        Array(Global.read_config('pf2e_class', char.pf2_base_info['charclass'], 'movement'))
          .select { |entry| entry['level'].to_i <= level }
      end

      # ------------------------------------------------------------------------------
      # Saying them
      # ------------------------------------------------------------------------------

      # "25 feet", or the total and what makes it up once anything does.
      def self.speed_text(result)
        parts = result['parts']

        return "#{result['land']} feet" if parts.size == 1

        described = parts.map do |source, amount, kind|
          case kind
          when :base then "#{amount}-ft from #{source}"
          when :status then "+#{amount} ft status bonus while unarmored (#{source})"
          else "#{amount.negative? ? '-' : '+'}#{amount.abs} ft from #{source}"
          end
        end

        "#{result['land']}-ft (#{described.join(', ')})"
      end

      def self.special_text(result)
        list = result['special'].map { |s| "#{s['speed']}-ft #{s['type']} speed (#{s['source']})" }

        list.empty? ? 'None.' : list.join('; ')
      end

      def self.conditional_text(result)
        list = result['conditional'].map do |c|
          "#{format(WHEN[c['when']], :bonus => c['bonus'])} (#{c['source']})"
        end

        list.empty? ? 'None.' : list.join('; ')
      end

      def self.conditional?(result)
        !result['conditional'].empty?
      end
    end
  end
end
