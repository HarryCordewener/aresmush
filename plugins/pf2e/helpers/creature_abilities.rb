module AresMUSH
  module Pf2e

    # What a creature's ability deals and the save against it, read from its stat block's words:
    # Constrict's "(2d10+17) bludgeoning, DC 40 Fortitude", or a breath's "deals 12d6 fire damage to each
    # creature within the area (DC 34 Reflex save)".
    #
    # Such a save is basic, as an area's and a Constrict's are. An ability whose words give the outcomes
    # one by one is not, and is left to the GM.
    module CreatureAbilities

      FORMULA = '\d+d\d+(?:\s*[+-]\s*\d+)?'.freeze

      LISTED = /\A\(?(?<formula>#{FORMULA})\)? (?<type>[a-z]+)(?: damage)?, DC (?<dc>\d+) (?:basic )?(?<save>Fortitude|Reflex|Will)/

      TOLD = /(?<formula>#{FORMULA}) (?<type>[a-z]+) damage[^%]{0,200}?\(DC (?<dc>\d+) (?:basic )?(?<save>Fortitude|Reflex|Will)/

      OUTCOMES = /Critical Success|Critical Failure/

      # ------------------------------------------------------------------------------
      # A save and what its outcomes leave

      SAVE = /DC (?<dc>\d+)\s+(?<basic>basic\s+)?(?<save>Fortitude|Reflex|Will)/i
      NAMED_SAVE = /\b(?<save>Fortitude|Reflex|Will)\b(?: saving throw| save)/i
      AFFLICTION = /\bSaving Throw DC\b|\bStage 1\b/

      LABELS = { 'Critical Success' => 'criticalSuccess', 'Success' => 'success', 'Failure' => 'failure',
                 'Critical Failure' => 'criticalFailure' }.freeze
      PARAGRAPH = /\A(Critical Success|Critical Failure|Success|Failure)\s+(.+)\z/m

      # A condition as a stat block names one it means: capitalised, as its link was. One written small is
      # the words talking about it.
      VALUED = %w{Clumsy Doomed Drained Enfeebled Frightened Sickened Slowed Stunned Stupefied}.freeze
      PLAIN = %w{Blinded Confused Controlled Dazzled Deafened Fascinated Fatigued Fleeing Grabbed Immobilized Off-Guard
                 Paralyzed Petrified Prone Restrained Unconscious}.freeze
      CONDITION = /\b(?:(#{VALUED.join('|')}) (\d+)|(#{PLAIN.join('|')}))\b/

      # How long, where the words say it in a way this reads; a minute is ten rounds.
      LASTS = [ [ /\bfor (\d+) rounds?\b/i, ->(found) { "rounds:#{found[1]}" } ],
                [ /\bfor (\d+) minutes?\b/i, ->(found) { "rounds:#{found[1].to_i * 10}" } ],
                [ /\buntil the end of (?:its|their|the creature's|the target's) next turn\b/i, ->(_) { 'its-next-turn-end' } ],
                [ /\buntil the (?:start|beginning) of (?:its|their|the creature's|the target's) next turn\b/i, ->(_) { 'its-next-turn-start' } ] ].freeze

      # Words that make a condition depend on something this does not follow.
      DEPENDS = /\balready\b|\bunless\b|\bwhile\b|\bas long as\b|\bif (?!it fails|the (?:creature|target) fails)/i

      # Whether an ability's words give a save at all, by either reading.
      def self.saves?(text)
        !(saving(text) || damage_save(text)).nil?
      end

      # What an ability's words say of a save and its outcomes, or nothing where they name none:
      #
      #   { 'dc' => 23, 'save' => 'will', 'basic' => false, 'damage' => [ [ '1d6', 'piercing' ] ],
      #     'outcomes' => { 'failure' => [ { 'condition' => 'Frightened', 'value' => 2 } ], ... },
      #     'outcome_text' => { 'failure' => 'The creature is Frightened 2.' },
      #     'immune' => { 'after' => 'any', 'rounds' => 10 } }
      def self.saving(text)
        text = text.to_s
        found = text.match(SAVE)

        return nil if found.nil? || text.match?(AFFLICTION)

        lines = text.split('%r').map(&:strip)
        paragraphs = lines.filter_map { |line| (hit = line.match(PARAGRAPH)) && [ LABELS[hit[1]], hit[2].strip ] }.to_h
        # An outcome with no paragraph of its own is the one beside it: a critical failure is a failure.
        paragraphs['criticalFailure'] ||= paragraphs['failure'] if paragraphs['failure']
        paragraphs['criticalSuccess'] ||= paragraphs['success'] if paragraphs['success']
        outcomes = paragraphs.any? ? paragraphs.transform_values { |words| conditions_in(words) }.reject { |_k, held| held.empty? } :
                                     spoken_outcomes(text)

        { 'dc' => found[:dc].to_i, 'save' => found[:save].downcase, 'basic' => !found[:basic].nil?,
          'damage' => dealt(text), 'persistent' => burning(text), 'outcomes' => outcomes, 'outcome_text' => paragraphs,
          'immune' => immune_after(text) }
      end

      # The persistent damage whoever fails the save also takes: `Creatures that fail the save also take
      # 1d4 persistent fire damage`.
      def self.burning(text)
        text.scan(/\bfail[^.%]*?(#{FORMULA}) persistent ([a-z]+) damage/i).map { |formula, type| [ formula.delete(' '), type ] }
      end

      # The damage the words deal against the save: `takes 1d6 piercing damage`.
      def self.dealt(text)
        found = text.match(/(?<formula>#{FORMULA}) (?<type>[a-z]+) damage/)

        found && found[:type] != 'persistent' ? [ [ found[:formula].delete(' '), found[:type] ] ] : []
      end

      # The conditions a stretch of words leaves, each with how long where its words say.
      def self.conditions_in(words)
        words.to_enum(:scan, CONDITION).map do
          found = Regexp.last_match
          rest = words[found.end(0)..].to_s[/\A[^.;]*/].to_s
          lasts = LASTS.filter_map { |pattern, key| (hit = rest.match(pattern)) && [ hit.begin(0), key.call(hit) ] }.min_by(&:first)
          # A duration belongs to the condition it follows directly, or to the last before it.
          between = lasts ? rest[0, lasts[0]] : ''
          one = { 'condition' => found[1] || found[3] }
          one['value'] = found[2].to_i if found[2]
          one['until'] = lasts[1] if lasts && !between.match?(CONDITION) && one['condition'] != 'Frightened'
          one
        end
      end

      # Outcomes a sentence gives: `must succeed at a Fortitude save or become Sickened 1 (plus Slowed 1 ...
      # on a critical failure)`. A critical failure is the failure and whatever its own clause adds.
      SUCCEED_OR = /must succeed (?:at|on) [^.]*?(?:save|saving throw) or (?<else>[^.(]*)(?:\((?<aside>[^)]*)\))?/i

      def self.spoken_outcomes(text)
        found = text.match(SUCCEED_OR)

        return {} unless found && !found[:else].match?(DEPENDS)

        failure = conditions_in(found[:else])
        worse = found[:aside].to_s.match?(/critical failure|critically fails/i) ? conditions_in(found[:aside]) : []

        return {} if failure.empty?

        { 'failure' => failure, 'criticalFailure' => worse.any? && found[:aside].match?(/\A\s*(?:plus|and)\b/i) ? failure + worse : (worse.any? ? worse : failure) }
      end

      # For how long whoever has saved is immune to it afterwards, and after which outcomes: any, a
      # success, or - said in the critical success's own paragraph - only that.
      def self.immune_after(text)
        line = text.split('%r').map(&:strip).find { |one| one.match?(/temporarily immune/i) }

        return nil unless line

        sentence = line.split(/(?<=\.)\s+/).find { |one| one.match?(/temporarily immune/i) }
        rounds = if (found = sentence.match(/for (\d+) rounds?/i)) then found[1].to_i
                 elsif (found = sentence.match(/for (\d+) minutes?/i)) then found[1].to_i * 10
                 elsif sentence.match?(/until the (?:start|beginning|end) of/i) then 1
                 else 1000
                 end
        after = if line.match?(/\ACritical Success\b/) then 'critical'
                elsif sentence.match?(/\bsucceeds\b|\bsuccess\b/i) && !sentence.match?(/regardless/i) then 'success'
                else 'any'
                end

        { 'after' => after, 'rounds' => rounds }
      end

      #   { 'formula' => '2d10+17', 'type' => 'bludgeoning', 'dc' => 40, 'save' => 'fortitude' }, or nil
      def self.damage_save(text)
        text = text.to_s

        return nil if text.match?(OUTCOMES)

        found = text.match(LISTED) || text.match(TOLD)

        return nil unless found && found[:type] != 'persistent'

        { 'formula' => found[:formula].delete(' '), 'type' => found[:type], 'dc' => found[:dc].to_i,
          'save' => found[:save].downcase }
      end
    end
  end
end
