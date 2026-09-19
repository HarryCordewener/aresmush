module AresMUSH
  module Pf2e

    # A check rolled against something: the d20, the figure, the DC, and the outcome.
    #
    # `Check` builds what a roll is worth; this throws the die and measures it, the same way for a
    # character and a creature. Everything a rule can do to a roll is asked of the check: fortune rolls
    # twice, Assurance stands in for the die, a keen weapon turns a near miss into a critical hit, and what
    # the roll spent - Guidance's bonus - is spent.
    module Resolve

      # `extra` are modifiers this one roll carries that no figure does: a range increment, an action's
      # own circumstance penalty. They are stacked with the figure's, so a circumstance penalty the
      # action carries does not stack with one the character already has.
      def self.roll(check, dc: nil, extra: [])
        breakdown = restacked(check.breakdown, extra)
        substitution = check.substitution
        keep = substitution ? nil : check.roll_twice

        if substitution
          check.substituted = substitution['slug']
          dice = []
          natural = nil
          face = substitution['value'].to_i
        else
          dice = Pf2e.roll_dice(keep ? 2 : 1, 20)
          natural = keep == 'keep-lower' ? dice.min : dice.max
          face = natural
        end

        total = face + breakdown['total'].to_i
        degree = dc ? Degree.adjusted(Degree.of(total, dc, natural), check.adjustments(check.rolled(total, dc, natural))) : nil

        check.rolled!(total, dc, natural)

        { 'die' => natural, 'dice' => dice, 'kept' => keep, 'substitution' => substitution,
          'modifier' => breakdown['total'].to_i, 'total' => total, 'dc' => dc, 'degree' => degree,
          'breakdown' => breakdown }
      end

      # A figure's modifiers with more added, stacked again.
      def self.restacked(breakdown, extra)
        return breakdown if Array(extra).empty?

        rows = Array(breakdown['modifiers']).map { |row| row.except('enabled') } + Array(extra)

        breakdown.merge(Modifiers.breakdown(breakdown['base'].to_i, rows))
      end

      # A flat check: a d20 against a DC, nothing added.
      def self.flat(dc)
        die = Pf2e.roll_dice(1, 20).first

        { 'die' => die, 'dc' => dc, 'success' => die >= dc }
      end

      # ------------------------------------------------------------------------------
      # Defences

      # What each defence an action names is, as a figure: AC, a save, Perception, or a skill DC.
      def self.defence_figure(against)
        named = against.to_s.downcase

        return [ 'ac', nil ] if %w{ac armor}.include?(named)
        return [ 'perception', nil ] if named == 'perception'
        return [ 'save', named ] if Pf2e::SAVES.include?(named)

        [ 'skill', Stat.skill_named(named) || named.capitalize ]
      end

      # A defence as a DC: AC as it stands, anything else ten more than its modifier. `options` are what
      # is true of the one attacking, as the defender's rules read them; `extra` what this attack alone
      # gives the defender - cover, or the off-guard of being flanked.
      def self.defence(holder, against, options: [], extra: [])
        kind, name = defence_figure(against)
        figure = if Pf2e.npc?(holder)
                   Npcs.stat(holder, kind, name, options)
                 else
                   Stat.of(holder, kind, name, options)
                 end

        return nil unless figure

        figure = restacked(figure, extra)
        dc = kind == 'ac' ? figure['total'].to_i : 10 + figure['total'].to_i

        { 'dc' => dc, 'kind' => kind, 'name' => name, 'breakdown' => figure }
      end

      # What is true of one side, as the other's rules ask about it: Foundry spells what an attacker knows
      # of its target `target:` and what a defender knows of its attacker `origin:`.
      def self.seen_as(holder, prefix)
        Effects.facts(holder).select { |one| one.start_with?('self:') }
                             .map { |one| one.sub(/\Aself:/, "#{prefix}:") }
      end

      # ------------------------------------------------------------------------------
      # Cover and concealment

      COVER = { 'lesser' => 1, 'standard' => 2, 'greater' => 4 }.freeze
      CONCEALMENT = { 'concealed' => 5, 'hidden' => 11, 'undetected' => 11 }.freeze

      # Cover's bonus to AC, and to a Reflex save against an area where the cover is standard or better.
      def self.cover_modifier(level, against = 'ac')
        value = COVER[level.to_s]

        return nil unless value
        return nil if against.to_s != 'ac' && value < COVER['standard']

        { 'source' => "#{level} cover", 'slug' => 'cover', 'type' => 'circumstance', 'value' => value }
      end

      # Being flanked leaves a creature off-guard to the flanker: -2 AC, the same circumstance penalty
      # Off-Guard's own rule gives, so the two do not stack.
      FLANKED = { 'source' => 'off-guard (flanked)', 'slug' => 'off-guard', 'type' => 'circumstance',
                  'value' => -2 }.freeze

      # Two degrees are shown as words.
      WORDS = [ 'critical failure', 'failure', 'success', 'critical success' ].freeze

      def self.word(degree)
        degree ? WORDS[degree] : nil
      end

      # The modifiers that counted, as a player reads them.
      def self.explained(breakdown)
        Array(breakdown['modifiers']).map do |row|
          value = row['value'].to_i
          shown = "#{value.negative? ? '' : '+'}#{value} #{row['type']} (#{row['source']})"

          row['enabled'] ? shown : "#{shown} - does not count"
        end
      end
    end
  end
end
