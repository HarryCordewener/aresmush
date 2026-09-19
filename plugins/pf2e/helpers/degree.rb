module AresMUSH
  module Pf2e

    # How well a check went, as something that can be reasoned about rather than a coloured string.
    #
    # `get_degree` decided the outcome and formatted it in one breath, which is fine for printing a roll
    # and no use to anything that has to *change* the outcome. A hundred and fifty rule elements in
    # Foundry's data do exactly that - Assurance turns a failure into a success, a Deafened character's
    # auditory Perception check drops to a critical failure - so the outcome has to exist as a value
    # before any of them can be read.
    #
    # Four outcomes, numbered as Foundry numbers them (`degree-of-success.ts:175`), so a rule saying
    # `one-degree-better` is arithmetic on that number.
    module Degree

      CRITICAL_FAILURE = 0
      FAILURE = 1
      SUCCESS = 2
      CRITICAL_SUCCESS = 3

      # In outcome order, which is also the order an adjustment keyed by outcome is matched in.
      NAMES = %w{criticalFailure failure success criticalSuccess}.freeze

      SLUGS = %w{critical-failure failure success critical-success}.freeze

      # `adjust-degree-of-success.ts:42`. A number shifts the outcome by that much; a name sets it
      # outright.
      ADJUSTMENTS = {
        'two-degrees-better' => 2,
        'one-degree-better' => 1,
        'one-degree-worse' => -1,
        'two-degrees-worse' => -2,
        'to-critical-failure' => CRITICAL_FAILURE,
        'to-failure' => FAILURE,
        'to-success' => SUCCESS,
        'to-critical-success' => CRITICAL_SUCCESS
      }.freeze

      OUTRIGHT = %w{to-critical-failure to-failure to-success to-critical-success}.freeze

      # The outcome of rolling `total` against `dc`, before anything adjusts it.
      #
      # Ten over is a critical success and ten under a critical failure; a natural twenty shifts the
      # outcome one better and a natural one shifts it one worse, which is a shift of the degree rather
      # than a separate outcome of its own.
      def self.of(total, dc, die = nil)
        base = if total - dc >= 10 then CRITICAL_SUCCESS
               elsif total >= dc then SUCCESS
               elsif total - dc <= -10 then CRITICAL_FAILURE
               else FAILURE
               end

        natural(base, die)
      end

      def self.natural(degree, die)
        return shift(degree, 1) if die == 20
        return shift(degree, -1) if die == 1

        degree
      end

      def self.shift(degree, amount)
        (degree + amount).clamp(CRITICAL_FAILURE, CRITICAL_SUCCESS)
      end

      # The outcome after every adjustment that applies to it.
      #
      # An adjustment is keyed by the outcome it applies to, or by `all`. The first one that matches
      # wins, which is why they are tried in a fixed order rather than all applied
      # (`degree-of-success.ts:78`).
      def self.adjusted(degree, adjustments)
        found = matching(degree, adjustments)

        return degree unless found

        apply(degree, found)
      end

      def self.matching(degree, adjustments)
        Array(adjustments).each do |adjustment|
          [ 'all', NAMES[degree] ].each do |key|
            named = adjustment[key]

            return named if named && allowed?(degree, named)
          end
        end

        nil
      end

      # A check that already went as well as it can cannot be improved, and one that went as badly as it
      # can cannot be worsened. Foundry skips the adjustment rather than clamping it, which matters
      # because a later adjustment then gets its turn.
      def self.allowed?(degree, named)
        amount = ADJUSTMENTS[named.to_s]

        return false unless amount
        return true if OUTRIGHT.include?(named.to_s)
        return false if degree == CRITICAL_SUCCESS && amount.positive?
        return false if degree == CRITICAL_FAILURE && amount.negative?

        true
      end

      def self.apply(degree, named)
        amount = ADJUSTMENTS[named.to_s]

        OUTRIGHT.include?(named.to_s) ? amount : shift(degree, amount)
      end

      def self.name(degree)
        NAMES[degree]
      end

      def self.slug(degree)
        SLUGS[degree]
      end

      def self.success?(degree)
        degree >= SUCCESS
      end
    end
  end
end
