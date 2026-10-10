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

      TOLD = /\(?(?<formula>#{FORMULA})\)? (?<type>[a-z]+) damage[^%]{0,200}?\(DC (?<dc>\d+) (?:basic )?(?<save>Fortitude|Reflex|Will)/

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
      DEPENDS = /\balready\b|\bunless\b|\bwhile\b|(?<!\bfor )\bas long as\b|\bif (?!it fails|the (?:creature|target) fails)/i

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
      #
      # `actions` is how many were spent on it, where what it deals is by that.
      def self.saving(text, actions = nil)
        text = text.to_s
        found = text.match(SAVE)

        return nil if found.nil? || text.match?(AFFLICTION)

        lines = text.split('%r').map(&:strip)
        paragraphs = lines.filter_map { |line| (hit = line.match(PARAGRAPH)) && [ LABELS[hit[1]], hit[2].strip ] }.to_h
        # An outcome with no paragraph of its own is the one beside it: a critical failure is a failure.
        paragraphs['criticalFailure'] ||= paragraphs['failure'] if paragraphs['failure']
        paragraphs['criticalSuccess'] ||= paragraphs['success'] if paragraphs['success']
        basic = !found[:basic].nil?
        outcomes = paragraphs.any? ? paragraphs.transform_values { |words| conditions_in(words) }.reject { |_k, held| held.empty? } :
                                     spoken_outcomes(text, basic)

        { 'dc' => found[:dc].to_i, 'save' => found[:save].downcase, 'basic' => basic,
          'damage' => by_actions(text).fetch(actions) { by_actions(text).values.first || dealt(text, basic) },
          'persistent' => burning(text), 'outcomes' => outcomes, 'outcome_text' => paragraphs,
          'immune' => immune_after(text) }
      end

      # The persistent damage whoever fails the save also takes: `Creatures that fail the save also take
      # 1d4 persistent fire damage`.
      def self.burning(text)
        text.scan(/\bfail[^.%]*?(#{FORMULA})\)? persistent ([a-z]+) damage/i).map { |formula, type| [ formula.delete(' '), type ] }
      end

      # The damage the words deal against the save: `takes 1d6 piercing damage`. Damage a sentence gives to
      # one outcome alone is that outcome's - and what whoever does not succeed takes is a failure's,
      # unless the save is basic, where it is the save's own to scale.
      def self.dealt(text, basic = false)
        plain = sentences(text).reject { |sentence| spoken_of(sentence) || closing(sentence) || (!basic && sentence.match?(SUCCEED_OR)) }
                               .join(' ')
        found = plain.match(DEALS)

        found && found[:type] != 'persistent' ? [ [ found[:formula].delete(' '), found[:type] ] ] : []
      end

      # What an ability that takes one to three actions deals for each number of them, where its words
      # list that line by line: `2 (2d6+9) bludgeoning damage`.
      #
      #   { 1 => [ [ '1d8', 'bludgeoning' ], [ '1d6', 'sonic' ] ], 2 => [ [ '2d6+9', 'bludgeoning' ] ] }
      def self.by_actions(text)
        lines = text.to_s.split('%r').map(&:strip)

        return {} unless lines.first.to_s.match?(/\A1 to [23]\z/)

        lines.each_with_object({}) do |line, out|
          found = line.match(/\A([123]) (.*\bdamage\b.*)\z/)
          dealt = found ? found[2].scan(DEALS).map { |formula, type| [ formula.delete(' '), type ] } : []

          out[found[1].to_i] = dealt if dealt.any?
        end
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

      # ------------------------------------------------------------------------------
      # Outcomes a sentence gives
      #
      #   must succeed at a Fortitude save or become Sickened 1 (plus Slowed 1 ... on a critical failure)
      #   On a failure, a creature becomes Frightened 2 (or Frightened 3 on a critical failure).
      #   A creature that fails this save falls Unconscious.
      #   If the save is a critical failure, the triggering creature also takes 1d6 bludgeoning damage.

      SUCCEED_OR = /must succeed (?:at|on) [^.]*?(?:save|saving throw)[^.]*? or (?<else>[^.(]*)(?:\((?<aside>[^)]*)\))?/i

      # How a sentence says which outcome it is about, most particular first.
      OPENS = [
        [ 'criticalFailure', /\A(?:on a critical failure|if the save is a critical failure|if (?:it|the creature|the target|a creature) critically fails|a creature that critically fails)\b/i ],
        [ 'criticalSuccess', /\Aon a critical success\b/i ],
        [ 'failure', /\A(?:on a failure|on a failed save|if (?:it|the creature|the target|a creature) fails|a creature that fails|(?:those|creatures) that fail)\b/i ],
        [ 'success', /\A(?:on a success|a creature that succeeds)\b/i ]
      ].freeze

      # ... or closes: `becoming Frightened 2 on a failure`, which is then about its last clause.
      CLOSES = [
        [ 'criticalFailure', /\bon a critical failure\z/i ],
        [ 'failure', /\bon a (?:failure|failed save)\z/i ],
        [ 'success', /\bon a success\z/i ]
      ].freeze

      # An aside that is about an outcome, and not a formula in brackets.
      ASIDE = /\((?<aside>(?!#{FORMULA}\))[^)]*)\)/
      WORSE = /critical failure|critically fails/i
      DEALS = /\(?(?<formula>#{FORMULA})\)? (?<type>[a-z]+) damage/
      TAKES = /takes? #{DEALS.source}/

      def self.sentences(text)
        text.split('%r').flat_map { |line| line.split(/(?<=[.!?])\s+/) }.map(&:strip).reject(&:empty?)
      end

      # Which outcome a sentence is about, by how it opens.
      def self.spoken_of(sentence)
        OPENS.find { |_outcome, pattern| sentence.match?(pattern) }&.first
      end

      # The outcome a sentence closes with and the clause that is about it, or nothing.
      def self.closing(sentence)
        bare = sentence.sub(ASIDE, '').strip.delete_suffix('.')
        outcome = CLOSES.find { |_outcome, pattern| bare.match?(pattern) }&.first

        outcome && [ outcome, "#{bare.split(/,\s*/).last} #{sentence[ASIDE]}" ]
      end

      # `basic` is that the save is a basic one, whose damage is its own and no outcome's.
      def self.spoken_outcomes(text, basic = false)
        out = {}

        sentences(text).each do |sentence|
          outcome = spoken_of(sentence)
          body = sentence

          if (found = sentence.match(SUCCEED_OR))
            outcome = 'failure'
            body = "#{found[:else]} #{found[:aside] ? "(#{found[:aside]})" : ''}"
          elsif outcome.nil? && (found = closing(sentence))
            outcome, body = found
          end

          next if outcome.nil?

          aside = body[ASIDE, :aside].to_s
          said = body.sub(ASIDE, '').sub(OPENS.assoc(outcome).last, '')

          # Past how it opens, what hangs on something else is left to its words.
          next if said.match?(DEPENDS)

          main = leaves(said)
          main = main.reject { |one| one['damage'] } if basic && sentence.match?(SUCCEED_OR)
          worse = aside.match?(WORSE) ? leaves(aside) : []

          out[outcome] = Array(out[outcome]) + main if main.any?

          next unless outcome == 'failure' && worse.any?

          # `plus` and `and` add to what a failure leaves; `or` is what a critical failure leaves instead.
          out['criticalFailure'] = aside.match?(/\A\s*(?:plus|and)\b/i) ? main + worse : worse
        end

        # What a critical failure adds, it adds to a failure; with nothing said of it, it is a failure.
        if out['failure']
          also = Array(out['criticalFailure'])
          said_instead = also.any? { |one| one['condition'] && out['failure'].any? { |held| held['condition'] == one['condition'] } }
          out['criticalFailure'] = said_instead ? also : out['failure'] + also
        end

        out
      end

      # What a stretch of words leaves on whoever it is about: conditions, and damage it says they take.
      def self.leaves(words)
        taken = words.to_enum(:scan, TAKES).map { { 'damage' => $~[:formula].delete(' '), 'type' => $~[:type] } }
                     .reject { |one| one['type'] == 'persistent' }

        conditions_in(words) + taken
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

      # How often an ability may be used, where its words say so on a line of their own - `Frequency once
      # per round` - as the catalogue gives an action's: `{ 'max' => 1, 'per' => 'round' }`, a minute and
      # ten minutes as `TurnState` names them.
      FREQUENCY = /\AFrequency (once|twice|one|two|three|four|five|\d+)(?: times?)? (?:per|every) (round|turn|minute|10 minutes|hour|day)\b/i
      TIMES = { 'once' => 1, 'one' => 1, 'twice' => 2, 'two' => 2, 'three' => 3, 'four' => 4, 'five' => 5 }.freeze
      PER = { 'minute' => 'PT1M', '10 minutes' => 'PT10M' }.freeze

      def self.frequency(text)
        found = text.to_s.split('%r').filter_map { |line| line.strip.match(FREQUENCY) }.first

        found && { 'max' => TIMES[found[1].downcase] || found[1].to_i, 'per' => PER[found[2].downcase] || found[2].downcase }
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
