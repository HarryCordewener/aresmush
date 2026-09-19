module AresMUSH
  module Pf2e

    # The circumstances a character has switched on.
    #
    # A `RollOption` rule declares a circumstance rather than a number: a Clandestine Cloak declares
    # `clandestine-cloak` and predicates its own bonuses on it, so the cloak works only when the option
    # holds. Two hundred and nineteen rules on the things we stock are declarations of this kind, and
    # eighty-nine of them are asked about by another rule on the same item or feat.
    #
    # Foundry defaults a toggleable option to off and leaves the player to flip it. Here it is on
    # instead, because an item a character is wearing should do what it says without being asked - and a
    # player who wants it off can say so, which is what this store is for. Only a deliberate choice is
    # written down; an option nobody has touched follows the rule's own default.
    module RollOptions

      # `sheet/option <name>` writes one of these. Anything not held follows the declaration.
      OFF = false
      ON = true

      # Every option the character's feats, items and conditions declare, newest source last.
      #
      #   [ { 'option' =>, 'label' =>, 'source' =>, 'domain' =>, 'default' =>, 'on' => } ]
      def self.declared(char)
        chosen = char.pf2_roll_options || {}

        Effects.sources(char).flat_map do |source|
          Rules.of_kind(source, 'RollOption').map do |row|
            declaration(char, source, row, chosen)
          end
        end.compact
      end

      def self.declaration(char, source, row, chosen)
        held = Rules.contribute(row, source, Effects.context(char))

        return nil unless held && held['option']

        # A declaration with circumstances of its own is one we cannot establish, so it is offered and
        # left off rather than presumed.
        reachable = Predicate.test(row['predicate'], Effects.options_of(char, source))

        said = chosen[held['option']]
        on = chosen.key?(held['option']) ? !said.eql?(false) : (held['default'] && reachable)

        # A locked toggle reads as whatever locked it, whatever the player said.
        locked = held['locked_when'] && Predicate.test(held['locked_when'],
                                                       Effects.options_of(char, source))
        on = !!held['locked_to'] if locked

        held.merge('on' => on,
                   'locked' => !!locked,
                   'selected' => selected(held, said),
                   'chosen' => chosen.key?(held['option']),
                   'reachable' => reachable)
      end

      # Which of an option's choices holds. What the player said, if it is one of them; otherwise what
      # the rule selected, or the first - because an option that is on has to be on as *something*.
      def self.selected(held, said)
        values = Array(held['choices']).map { |one| one['value'] }

        return nil if values.empty?
        return said if said.is_a?(String) && values.include?(said)

        values.include?(held['selection'].to_s) ? held['selection'].to_s : values.first
      end

      # The options that hold, as a predicate reads them. One with a choice holds twice: bare, and with the
      # choice after a colon, which is how a rule names the choice it wants.
      #
      # A declaration may say which statistics it is about, and most of the scoped ones are about attacks
      # or damage: Foundry keeps those under the domain they name and a statistic sees only its own
      # (`rule-element/roll-option.ts`). So a figure asks for the options its domains reach, and anything
      # asking without saying - a write, a resistance - sees only what was declared for everything.
      def self.active(char, domains = nil)
        declared(char).select { |one| one['on'] && about?(one['domain'], domains) }.flat_map do |one|
          [ one['option'], one['selected'] ? "#{one['option']}:#{one['selected']}" : nil ]
        end.compact.uniq
      end

      def self.about?(domain, domains)
        return true if domain.nil? || domain.to_s == Domains::ALL

        Domains.matches?(domain, Array(domains))
      end

      # `on` is true, false, or the value of one of the option's choices.
      def self.set(char, option, on)
        held = (char.pf2_roll_options || {}).merge(option.to_s => on.is_a?(String) ? on : !!on)

        char.update(:pf2_roll_options => held)
      end

      # Back to following the declaration, rather than off.
      def self.clear(char, option)
        held = char.pf2_roll_options || {}

        char.update(:pf2_roll_options => held.reject { |name, _| name == option.to_s })
      end

      # What the player may name, matched the way a player would type it.
      def self.find(char, term)
        wanted = Domains.slug(term)

        declared(char).find { |one| Domains.slug(one['option']) == wanted } ||
          declared(char).find { |one| Domains.slug(one['option']).include?(wanted) }
      end
    end
  end
end
