module AresMUSH
  module Pf2e

    # The formula language Foundry's pf2e system writes its effects in, read rather than reinvented.
    #
    # An effect says what it is worth as an expression: `@actor.level` for Toughness's hit points,
    # `ternary(gte(@actor.level,17),3,2)` for a rank that improves at 17th. We adopt the grammar so a
    # converted feat carries its formula across as data. Inventing our own shape would mean
    # hand-translating the two thousand formulas their data ships, and a wrong sign or a dropped floor
    # is a number that looks right and is not.
    #
    # Dentaku does the tokenising, the precedence and the tree, and it is taught Foundry's syntax
    # rather than fed a rewritten copy of it. `install!` registers two scanners and asks for
    # case-sensitive identifiers, so `@actor.flags.sneakAttackDamage` and
    # `@actor.system.proficiencies.attacks.advanced-firearms-crossbows.rank` arrive at the parser as
    # single identifiers spelled exactly as the data spells them. A formula string is never edited on
    # its way in, and an identifier is the verbatim source text - which is also what tells a reference
    # from a bare word, since Foundry marks every reference with `@` or braces.
    #
    # Dentaku's scanner registry is global to the gem and the `math` command shares it, so the two
    # scanners are gated: each carries a condition that holds only while `reading` is on the stack, and
    # `math` goes on seeing the grammar it always saw. The flag is thread-local because sheet work can
    # run under `EventMachine.defer`.
    #
    # `ternary`, `gte` and the rest are Foundry's names for things Dentaku spells differently or not at
    # all, so they are registered as functions. `max` and `min` it already has.
    #
    # Nothing here evaluates Ruby: Dentaku parses arithmetic over a fixed function set, so an
    # expression cannot reach the host, and a function we have not registered is refused rather than
    # guessed at.
    #
    # `formula_specs.rb` holds this against every formula in Foundry's shipped packs, from a corpus in
    # `specs/support/`. That corpus is the guard against having read the grammar wrongly: a construct
    # we misunderstand fails there, loudly, instead of quietly resolving to zero in front of a player.
    module Formula

      class Invalid < StandardError; end

      # `{item|flags.pf2e.rulesSelections.skill}` - a value fetched from somewhere other than the
      # actor. The pipe is what keeps this clear of Dentaku's own `{1,2}` array literal.
      INTERPOLATION = /\{[^{}|]*\|[^{}]*\}/
      SEGMENT = /[\w-]+|#{INTERPOLATION}/
      REFERENCE = /@(?:#{SEGMENT})(?:\.(?:#{SEGMENT}))*/

      # `when` answers nothing when its test fails, and `match` takes the first answer that is not
      # nothing (`scripts/hooks/load.ts:149`). Nothing has to be a number here, since Dentaku's
      # arithmetic is numeric, and a NaN is the one number that cannot be mistaken for an answer: it
      # propagates through any arithmetic it touches rather than quietly reading as zero. Every use in
      # their shipped data has `when` directly inside `match`, so a NaN never escapes one.
      NOTHING = Float::NAN

      # Foundry's functions, from where they are registered (`scripts/hooks/load.ts:140`). Comparisons
      # answer 1 and 0, which is what their JavaScript booleans are worth in arithmetic. `clamped` is a
      # misspelling of clamp appearing once in the shipped data; accepting it costs nothing, and
      # refusing it would fail an import over someone else's slip.
      FUNCTIONS = {
        :floor => [ :numeric, ->(value) { value.floor } ],
        :ceil => [ :numeric, ->(value) { value.ceil } ],
        :round => [ :numeric, ->(value) { value.round } ],
        :abs => [ :numeric, ->(value) { value.abs } ],
        :sign => [ :numeric, ->(value) { value <=> 0 } ],
        :gte => [ :numeric, ->(left, right) { left >= right ? 1 : 0 } ],
        :gt => [ :numeric, ->(left, right) { left > right ? 1 : 0 } ],
        :lte => [ :numeric, ->(left, right) { left <= right ? 1 : 0 } ],
        :lt => [ :numeric, ->(left, right) { left < right ? 1 : 0 } ],
        :eq => [ :numeric, ->(left, right) { left == right ? 1 : 0 } ],
        :ne => [ :numeric, ->(left, right) { left == right ? 0 : 1 } ],
        :ternary => [ :numeric, ->(test, yes, no) { test.zero? ? no : yes } ],
        :clamp => [ :numeric, ->(value, low, high) { value.clamp(low, high) } ],
        :clamped => [ :numeric, ->(value, low, high) { value.clamp(low, high) } ],
        :btwn => [ :numeric, ->(value, low, high) { value >= low && value <= high ? 1 : 0 } ],
        :when => [ :numeric, ->(test, then_value) { test.zero? ? NOTHING : then_value } ],
        # Variadic, so Dentaku is handed one argument: it passes an array for a splat-shaped lambda.
        :match => [ :numeric, ->(*answers) { answers.flatten.find { |one| !one.to_f.nan? } || 0 } ]
      }.freeze

      def self.value(formula, context = {})
        evaluate(formula, context).first
      end

      # A value that may be a word rather than arithmetic - a size, `tiny` - read as the word when it is
      # one and as a number otherwise.
      def self.value_or_word(formula, context = {})
        return formula if formula.is_a?(Numeric)
        return formula.to_s if formula.to_s.match?(/\A[a-z]+\z/i)

        value(formula, context)
      end

      # The paths the formula asked for that the context did not hold. A reference resolving to nothing
      # counts as zero, which is what Foundry does - and is also how a mistyped path hides, so a caller
      # that wants to know can ask.
      def self.unresolved(formula, context = {})
        evaluate(formula, context).last
      end

      # Whether Dentaku can read it at all, without needing a context to resolve against.
      def self.parses?(formula)
        names(formula.to_s).all? { |name| reference?(name) }
      rescue StandardError
        false
      end

      def self.evaluate(formula, context)
        text = formula.to_s
        flat = flatten(context)
        missing = []

        bound = names(text).each_with_object({}) do |name, out|
          out[name] = reference?(name) ? held(name, flat, missing) : nil
        end

        [ compute(text, bound.compact, missing.uniq), missing.uniq ]
      end

      # ------------------------------------------------------------------------------

      # Dentaku reads `when` as part of its own `case … when … end` syntax, so the word never reaches
      # the function scanner. Foundry's `when` is a function, and this claims it as one - emitting the
      # same pair of tokens Dentaku's own function scanner does.
      KEYWORD_FUNCTIONS = /(?:when)\s*\(/

      GRAMMAR = :pf2e_formula_grammar

      # Both scanners decline unless this reader asked for them, which is what keeps Foundry's grammar
      # off the `math` command: a scanner's condition is the gem's own way of making one conditional,
      # and an inactive interpolation scanner leaves `{` to the array scanner that has always had it.
      ACTIVE = ->(_last_token) { !Thread.current[GRAMMAR].nil? }

      # Teaches Dentaku Foundry's two reference syntaxes. The scanners have to sit ahead of the array
      # scanner, which would otherwise take an interpolation's opening brace, so the whole ordered list
      # is re-registered rather than appended to.
      #
      # `register_scanners` sends each id to the class, which is why these are singleton methods.
      def self.install!
        scanner = Dentaku::TokenScanner

        scanner.define_singleton_method(:pf2e_reference) { new(:identifier, REFERENCE, nil, ACTIVE) }
        scanner.define_singleton_method(:pf2e_interpolation) { new(:identifier, INTERPOLATION, nil, ACTIVE) }
        scanner.define_singleton_method(:pf2e_keyword_function) do
          new(:function, KEYWORD_FUNCTIONS, lambda { |raw|
            name = raw.gsub('(', '').strip.downcase

            [ Dentaku::Token.new(:function, name.to_sym, name),
              Dentaku::Token.new(:grouping, :open, '(') ]
          }, ACTIVE)
        end

        ids = scanner.available_scanners
        ours = [ :pf2e_reference, :pf2e_interpolation, :pf2e_keyword_function ]
        scanner.register_scanners(ids.insert(ids.index(:numeric), *ours))
      end

      # Foundry's grammar, for the duration of the block. Nested because `evaluate` reads the names and
      # then computes, and both tokenise.
      def self.reading
        outer = Thread.current[GRAMMAR]
        Thread.current[GRAMMAR] = true

        yield
      ensure
        Thread.current[GRAMMAR] = outer
      end

      # Every identifier the formula names, spelled as the formula spells it. Anything Dentaku cannot
      # tokenise or parse is refused here, so a caller sees one error class whether the formula was
      # unreadable or merely wrong.
      def self.names(text)
        reading { calculator.ast(text).dependencies }
      rescue Dentaku::Error, Dentaku::ArgumentError => problem
        raise Invalid, "#{problem.class}: #{problem.message} in #{text.inspect}"
      end

      # Foundry marks a reference with `@` or with braces, always, so a bare word is a formula that
      # does not say what it means - malformed rather than merely unresolved. Keeping that distinction
      # is what makes a nonsense formula loud: Dentaku reads `` `ls` `` as an identifier, and binding it
      # to zero would have swallowed it.
      def self.reference?(name)
        name.start_with?('@', '{')
      end

      # What the context holds for one reference. An interpolation inside a path resolves first and
      # becomes a segment of it: `@actor.skills.{item|…}.rank` is two lookups, not one.
      NUMBER = /\A[+-]?\d+(?:\.\d+)?\z/

      def self.held(name, flat, missing)
        key = if name.start_with?('{')
                source, _, inner = name[1..-2].partition('|')
                "#{source}.#{inner}"
              else
                name[1..].gsub(INTERPOLATION) { |brace| interpolate(brace, flat, missing) }
              end

        return flat[key] if flat[key].is_a?(Numeric)
        # A choice's answer is kept as the text it was chosen as, so Aid's `-1` arrives as a string.
        return flat[key].include?('.') ? flat[key].to_f : flat[key].to_i if flat[key].to_s.match?(NUMBER)

        missing << key

        0
      end

      def self.interpolate(brace, flat, missing)
        source, _, inner = brace[1..-2].partition('|')
        key = "#{source}.#{inner}"
        held = flat[key]

        return held.to_s unless held.nil?

        missing << key

        ''
      end

      def self.compute(text, bound, missing)
        normalise(reading { calculator.evaluate!(text, bound) })
      rescue ZeroDivisionError
        # Only a reference that resolved to nothing divides by zero here - no shipped formula divides
        # by a literal. `unresolved` already names it, and raising would take a whole sheet render down
        # over one bad path.
        0
      rescue Dentaku::UnboundVariableError => problem
        raise Invalid, "#{text.inspect} names #{Array(problem.unbound_variables).join(', ')}, " \
                       "which is not a reference"
      rescue StandardError => problem
        raise Invalid, "#{problem.class}: #{problem.message} in #{text.inspect}"
      end

      # Whole answers stay whole, so `18 + @actor.level` reads as an integer on a sheet and Dentaku's
      # BigDecimal does not leak out.
      def self.normalise(result)
        raise Invalid, "not a number: #{result.inspect}" unless result.is_a?(Numeric)

        whole = result.to_i

        whole == result ? whole : result.to_f
      end

      # A nested context to the dotted keys a formula names: { 'actor' => { 'level' => 5 } } becomes
      # { 'actor.level' => 5 }.
      def self.flatten(context, prefix = nil, out = {})
        (context || {}).each_pair do |key, held|
          path = [ prefix, key ].compact.join('.')

          if held.is_a?(Hash)
            flatten(held, path, out)
          else
            out[path] = held
          end
        end

        out
      end

      def self.calculator
        @calculator ||= begin
          install!

          Dentaku::Calculator.new(:case_sensitive => true).tap do |calc|
            FUNCTIONS.each_pair { |name, (type, body)| calc.add_function(name, type, body) }
          end
        end
      end
    end
  end
end
