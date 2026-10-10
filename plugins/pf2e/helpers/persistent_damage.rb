module AresMUSH
  module Pf2e

    # Persistent damage: a burn, a bleed, acid eating away. It is dealt at the end of each of the
    # character's or creature's turns, and then a flat check against its DC decides whether it stops.
    #
    # Foundry keeps one condition per kind of damage and ends every one of that kind on a successful
    # recovery (`actor/base.ts` `decreaseCondition`); the rules say the same kind does not stack, and the
    # higher applies. The check is a flat check whose domain is `pd-recovery-check`, so fortune on it -
    # Orchard's Endurance - reaches it the way fortune reaches any other check, and its DC is 15 unless
    # an alteration of `pd-recovery-dc` says otherwise.
    module PersistentDamage

      DC = 15

      # How Foundry names the condition, so a predicate about it reads the same fact.
      SLUG = 'persistent-damage'.freeze

      # The condition that says so on a sheet.
      CONDITION = 'Persistent'.freeze

      def self.held(char)
        Array(char.pf2_persistent)
      end

      # Adds persistent damage of a kind. Where the character already takes that kind, the one worth more
      # on average is kept.
      def self.add(char, formula, type, dc = DC)
        type = Domains.slug(type)
        held = held(char)
        mine = held.find { |one| one['type'] == type }

        return Ok.new(:state => held) if mine && Pf2e.average(mine['formula']) >= Pf2e.average(formula)

        list = held.reject { |one| one['type'] == type } + [ { 'formula' => formula.to_s, 'type' => type,
                                                             'dc' => dc.to_i } ]

        char.update(:pf2_persistent => list)
        Pf2e.set_condition(char, CONDITION) unless (char.pf2_conditions || {}).key?(CONDITION)

        Ok.new(:state => list)
      end

      def self.remove(char, type)
        list = held(char).reject { |one| one['type'] == Domains.slug(type) }

        char.update(:pf2_persistent => list)
        Pf2e.remove_condition(char, CONDITION) if list.empty?

        Ok.new(:state => list)
      end

      # The end of the character's turn: each kind is dealt, and then its flat check is rolled.
      # Answers what happened, for whoever tells the room.
      def self.end_of_turn(char)
        return [] if Pf2e.dead?(char)

        held(char).flat_map do |one|
          dealt = Pf2e.roll_formula(one['formula'])

          standing = Acting.still_up(char)
          dropped = Acting.report
          taken = Harm.damage(char, dealt, one['type'], :about => [ 'persistent' ])
          Acting.dropped(Combatants::Combatant.new(char, char.name, nil), standing, dropped, taken)

          check = recovery(char, one)
          events = [ Turns.event('pf2e.persistent_dealt', 'name' => char.name, 'amount' => dealt,
                                 'type' => one['type']) ] + dropped['lines']

          if check['success']
            remove(char, one['type'])
            events << Turns.event('pf2e.persistent_ended', 'name' => char.name, 'type' => one['type'],
                                  'die' => check['die'], 'dc' => check['dc'])
          else
            events << Turns.event('pf2e.persistent_continues', 'name' => char.name, 'type' => one['type'],
                                  'die' => check['die'], 'dc' => check['dc'])
          end

          events
        end
      end

      # The flat check that ends it: a d20 against its DC, rolled twice where fortune or misfortune reaches
      # a recovery check.
      def self.recovery(char, one)
        dc = Alterations.apply(char, 'condition', { 'recovery_dc' => one['dc'] || DC },
                               :options => [ "item:slug:#{SLUG}", "item:damage:type:#{one['type']}" ])['recovery_dc'].to_i
        options = Effects.options(char, DOMAINS) + [ "item:damage:type:#{one['type']}" ]
        keep = Rules.roll_twice(Effects.sources(char), DOMAINS, options)
        dice = Pf2e.roll_dice(keep ? 2 : 1, 20)
        die = keep == 'keep-lower' ? dice.min : dice.max

        { 'die' => die, 'dc' => dc, 'success' => die >= dc }
      end

      DOMAINS = [ 'pd-recovery-check', 'check', 'flat-check' ].freeze
    end

    # A formula of persistent damage as an outcome scales it: each term's dice and number doubled, or
    # halved where that comes out whole, and otherwise the whole halved as it is rolled (`1d6/2`). Nothing
    # at all for a scale of 0.
    def self.scaled_formula(formula, factor)
      return nil if factor.to_f.zero?
      return formula.to_s if factor == 1

      terms = formula.to_s.delete(' ').scan(/[+-]?[^+-]+/).map do |term|
        sign = term.start_with?('-') ? '-' : '+'
        body = term.delete_prefix('+').delete_prefix('-')
        dice = body.match(/\A(\d*)d(\d+)\z/i)
        count = dice ? (dice[1].empty? ? 1 : dice[1].to_i) : body.to_i
        scaled = count * factor

        return "#{formula}/#{(1 / factor.to_f).round}" unless scaled == scaled.floor

        "#{sign}#{scaled.to_i}#{dice ? "d#{dice[2]}" : ''}"
      end

      terms.join.delete_prefix('+')
    end

    # A formula of dice as a number: `2d6+3`. What an effect says it deals.
    def self.roll_formula(formula)
      whole, divisor = formula.to_s.split('/')
      return (roll_formula(whole) / divisor.to_i) if divisor.to_i.positive?

      formula.to_s.delete(' ').scan(/[+-]?[^+-]+/).sum do |term|
        sign = term.start_with?('-') ? -1 : 1
        body = term.delete_prefix('+').delete_prefix('-')

        if (dice = body.match(/\A(\d*)d(\d+)\z/i))
          sign * roll_dice(dice[1].empty? ? 1 : dice[1].to_i, dice[2].to_i).sum
        else
          sign * body.to_i
        end
      end
    end

    # What a formula comes to on average, which is how two of the same kind are compared.
    def self.average(formula)
      whole, divisor = formula.to_s.split('/')
      return (average(whole) / divisor.to_i) if divisor.to_i.positive?

      formula.to_s.delete(' ').scan(/[+-]?[^+-]+/).sum do |term|
        sign = term.start_with?('-') ? -1 : 1
        body = term.delete_prefix('+').delete_prefix('-')

        if (dice = body.match(/\A(\d*)d(\d+)\z/i))
          sign * (dice[1].empty? ? 1 : dice[1].to_i) * (dice[2].to_i + 1) / 2.0
        else
          sign * body.to_f
        end
      end
    end
  end
end
