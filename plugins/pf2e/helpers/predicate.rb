module AresMUSH
  module Pf2e

    # "Only in these circumstances" - Foundry's predicate language, read rather than reinvented.
    #
    # A modifier without one always applies. Most item bonuses have one, because most item bonuses are
    # conditional: Skeleton Key gives its +2 to picking a lock, not to Thievery generally, and a
    # Dancing Scarf helps you dance. Ignoring that is not a rounding error - it is an item strictly
    # better than the rules allow, and our own hand-written bonuses had ten of them.
    #
    # A predicate is a list of statements tested against a set of **options**: strings describing the
    # circumstance, like `action:pick-a-lock`, `item:trait:visual` or `self:level:7`. Every statement
    # has to hold. A statement is
    #
    #   * an **atom** - a string, true when the option set contains it;
    #   * a **compound** - `and` `or` `nor` `nand` `xor` `not` `if`/`then` `iff`;
    #   * a **comparison** - `eq` `gt` `gte` `lt` `lte`, over two operands.
    #
    # A comparison's operands may be numbers or option prefixes. A prefix resolves by scanning the
    # options for `prefix:<number>`, so `{ gte: [ 'self:level', 5 ] }` holds when the options carry
    # `self:level:7`. Foundry's own rule (`predication.ts:88`) is that some left value must satisfy
    # the comparison against every right value, which is what makes a prefix matching nothing false
    # rather than true.
    #
    # `predicate_specs.rb` holds this against every predicate in Foundry's shipped packs, from a corpus
    # in `specs/support/`. A structure we have read wrongly fails there rather than quietly handing a
    # player a bonus they have not earned.
    module Predicate

      # `and` and friends take a list of statements; `not` takes one statement.
      COMPOUND = {
        'and' => ->(parts, options) { parts.all? { |part| true?(part, options) } },
        'nand' => ->(parts, options) { !parts.all? { |part| true?(part, options) } },
        'or' => ->(parts, options) { parts.any? { |part| true?(part, options) } },
        'nor' => ->(parts, options) { !parts.any? { |part| true?(part, options) } },
        'xor' => ->(parts, options) { parts.count { |part| true?(part, options) } == 1 },
        'not' => ->(part, options) { !true?(part, options) },
        'iff' => ->(parts, options) {
          parts.all? { |part| true?(part, options) } || parts.none? { |part| true?(part, options) }
        }
      }.freeze

      LIST_COMPOUND = %w{and nand or nor xor iff}.freeze

      # `if`/`then` is the one statement with two keys rather than one: material implication, false
      # only when the antecedent holds and the consequent does not (`predication.ts:112`).
      CONDITIONAL = ->(statement, options) {
        !(true?(statement['if'], options) && !true?(statement['then'], options))
      }

      COMPARISON = {
        'gt' => ->(left, right) { left > right },
        'gte' => ->(left, right) { left >= right },
        'lt' => ->(left, right) { left < right },
        'lte' => ->(left, right) { left <= right }
      }.freeze

      # `eq` is not in the table above because it does not compare numbers. Foundry reads it as a
      # string comparison when the right operand is a string, and otherwise as a lookup of
      # `left:right` in the options (`predication.ts:65`).
      EQ = 'eq'.freeze

      # An empty predicate holds. That is what makes an unconditional modifier the same code path as a
      # conditional one.
      def self.test(predicate, options = [])
        statements = Array(predicate)

        return true if statements.empty?

        unless valid?(statements)
          Global.logger.warn "PF2e predicate #{statements.inspect} is malformed; treating it as unmet."
          return false
        end

        held = options.is_a?(Set) ? options : Set.new(Array(options).map(&:to_s))

        statements.all? { |statement| true?(statement, held) }
      end

      def self.true?(statement, options)
        case statement
        when String then options.include?(statement)
        when Hash then compound?(statement, options) || compare(statement, options)
        else false
        end
      end

      def self.compound?(statement, options)
        return CONDITIONAL.call(statement, options) if conditional?(statement)

        key, body = statement.first

        return false unless COMPOUND.key?(key.to_s)

        LIST_COMPOUND.include?(key.to_s) ? COMPOUND[key.to_s].call(Array(body), options)
                                         : COMPOUND[key.to_s].call(body, options)
      end

      def self.compare(statement, options)
        key, operands = statement.first
        key = key.to_s

        return equal?(operands, options) if key == EQ
        return false unless COMPARISON.key?(key)

        left = numbers(operands.first, options)
        right = numbers(operands.last, options)

        left.any? { |one| right.all? { |other| COMPARISON[key].call(one, other) } }
      end

      def self.equal?(operands, options)
        left, right = operands

        right.is_a?(String) ? left.to_s == right : options.include?("#{left}:#{right}")
      end

      # What an operand is worth. A number is itself; a string is a prefix, and its values are the
      # numbers the options carry under it. A prefix the options say nothing about has no values, and
      # a comparison over no values is false.
      def self.numbers(operand, options)
        return [ operand ] if operand.is_a?(Numeric)

        pattern = /\A#{Regexp.escape(operand.to_s)}:([^:]+)\z/

        options.map { |held| pattern.match(held) }.compact
               .map { |found| Integer(found[1], exception: false) || Float(found[1], exception: false) }
               .compact
      end

      # ------------------------------------------------------------------------------

      # Whether the structure is one this language has. A malformed predicate is refused rather than
      # guessed at, because the alternative is a condition nobody checked reading as met.
      def self.valid?(predicate)
        predicate.is_a?(Array) && predicate.all? { |statement| statement?(statement) }
      end

      def self.statement?(statement)
        case statement
        when String then !statement.empty?
        when Hash
          conditional?(statement) ||
            (statement.size == 1 && (compound_shape?(statement) || comparison_shape?(statement)))
        else false
        end
      end

      def self.conditional?(statement)
        statement.size == 2 && statement.key?('if') && statement.key?('then') &&
          statement?(statement['if']) && statement?(statement['then'])
      end

      def self.compound_shape?(statement)
        key, body = statement.first
        key = key.to_s

        return false unless COMPOUND.key?(key)
        return statement?(body) if key == 'not'

        body.is_a?(Array) && body.all? { |part| statement?(part) }
      end

      # Exactly two operands, the left a string and the right a string or a number.
      def self.comparison_shape?(statement)
        key, operands = statement.first

        return false unless COMPARISON.key?(key.to_s) || key.to_s == EQ
        return false unless operands.is_a?(Array) && operands.size == 2

        operands.first.is_a?(String) && (operands.last.is_a?(String) || operands.last.is_a?(Numeric))
      end
    end
  end
end
