module AresMUSH
  module Pf2e

    # Things a character can do: Take Cover, Rage, a monk's stance.
    #
    # The catalogue (`pf2e_actions.yml`, from Foundry's actions pack and the feats that are actions) says
    # what each costs and what it puts on whoever uses it - Foundry's `selfEffect`. Using one that has
    # an effect puts the character under it, through `ActiveEffects` like any other effect, so everything
    # the effect does and how long it lasts is already handled.
    module Actions

      # What an action costs, as a sheet says it.
      COSTS = { 1 => 'one action', 2 => 'two actions', 3 => 'three actions' }.freeze
      TYPES = { 'reaction' => 'reaction', 'free' => 'free action', 'passive' => 'passive' }.freeze

      def self.catalogue
        Global.read_config('pf2e_actions') || {}
      end

      def self.info(name)
        catalogue[name] || {}
      end

      # The action a player means, by the name they typed.
      def self.find(term)
        wanted = Domains.slug(term)
        names = catalogue.keys

        exact = names.find { |name| Domains.slug(name) == wanted }

        return Ok.new(:state => exact) if exact

        close = names.select { |name| Domains.slug(name).include?(wanted) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:not_found, 'pf2e.action_not_found', 'action' => term) if close.empty?

        Err.new(:ambiguous, 'pf2e.action_ambiguous', 'action' => term, 'options' => close.first(8).join(', '))
      end

      # An exploration or downtime activity costs no actions - Foundry files it as passive - but it is
      # something a character does, so it is an activity rather than nothing.
      def self.cost(name)
        entry = info(name)

        return 'activity' if entry['type'] == 'passive' && activity?(entry)

        TYPES[entry['type']] || COSTS[entry['cost'].to_i] || 'one action'
      end

      def self.activity?(entry)
        exploration?(entry) || downtime?(entry)
      end

      # ------------------------------------------------------------------------------
      # Whose it is

      # Whether the character can use an action. The basic, skill, exploration and downtime actions are
      # everyone's. Anything else - a class's, an archetype's, a heritage's - and any feat that is an
      # action, is theirs if a feat or feature of theirs has its name: the Rage class feature is what gives
      # a barbarian Rage, at the level the class grants it and not before.
      def self.usable(char, name)
        entry = info(name)

        return Ok.new(:state => name) if entry['for'] == 'everyone' || owned?(char, name)

        Err.new(:not_yours, 'pf2e.action_not_yours', 'action' => name)
      end

      def self.owned?(char, name)
        wanted = Domains.slug(name)
        held = (char.pf2_feats || {}).values.flatten + (char.pf2_features || {}).values.flatten

        held.any? { |one| Domains.slug(one) == wanted }
      end

      # ------------------------------------------------------------------------------
      # What a character has

      # The modes of play an action belongs to, by the traits Foundry gives it: an exploration activity
      # and a downtime activity say so, and anything else that costs actions is for an encounter.
      MODES = {
        'combat' => ->(entry) { !exploration?(entry) && !downtime?(entry) },
        'exploration' => ->(entry) { exploration?(entry) },
        'downtime' => ->(entry) { downtime?(entry) },
        'reactions' => ->(entry) { entry['type'] == 'reaction' }
      }.freeze

      # What a player may call a mode, onto the mode.
      ALIASES = { 'encounter' => 'combat', 'reaction' => 'reactions' }.freeze

      def self.mode(named)
        return nil if named.to_s.strip.empty?

        wanted = named.to_s.strip.downcase

        MODES.key?(wanted) ? wanted : ALIASES[wanted]
      end

      def self.exploration?(entry)
        Array(entry['traits']).include?('exploration')
      end

      def self.downtime?(entry)
        Array(entry['traits']).include?('downtime')
      end

      # Every action the character can use, in a mode of play or in all of them, by name. Something passive
      # is not used, so it is not listed - unless it is an exploration or downtime activity, which is.
      def self.available(char, mode = nil)
        keep = mode ? MODES[mode] : ->(_entry) { true }

        catalogue.select { |name, entry|
          (entry['type'] != 'passive' || activity?(entry)) && keep.call(entry) && usable(char, name).ok?
        }.keys.sort
      end

      # ------------------------------------------------------------------------------
      # Using one

      # The character uses an action. Where it puts an effect on them, they are now under it; `options` are
      # what they say about that effect, as `ActiveEffects.apply` takes them.
      #
      #   Ok state: { 'action' => name, 'effect' => the effect put on them, or nil }
      def self.use(char, term, options: [], encounter: nil)
        found = find(term)

        return found if found.err?

        name = found.state
        allowed = usable(char, name)

        return allowed if allowed.err?

        effect_name = info(name)['self_effect']

        return Ok.new(:state => { 'action' => name, 'effect' => nil }) unless effect_name

        applied = ActiveEffects.apply(char, effect_name, :options => options, :applied_by => char.name,
                                                         :encounter => encounter)

        return applied if applied.err?

        Ok.new(:state => { 'action' => name, 'effect' => applied.state })
      end
    end
  end
end
