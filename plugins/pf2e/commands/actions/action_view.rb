module AresMUSH
  module Pf2e

    # `action <name>` - what an action is and does. Where it puts an effect on whoever uses it, the display
    # says how to take that effect on.
    class PF2ActionViewCmd
      include CommandHandler

      attr_accessor :action

      def parse_args
        self.action = trim_arg(cmd.args)
      end

      def required_args
        [ self.action ]
      end

      def handle
        found = Actions.find(self.action)

        return if CharState.emit_error!(client, found)

        client.emit PF2ActionViewTemplate.new(enactor, found.state).render
      end
    end

    # `action/use <name>[/<option>...]` - use an action. One that puts an effect on its user does so, and
    # the options are what `effect/add` takes after the effect's name: `rank 6`, `value 2`, an answer.
    class PF2ActionUseCmd
      include CommandHandler

      attr_accessor :action, :options

      def parse_args
        parts = cmd.args.to_s.split('/').map(&:strip)

        self.action = parts.shift
        self.options = parts
      end

      def required_args
        [ self.action ]
      end

      def handle
        scene = enactor_room.scene
        encounter = scene ? PF2Encounter.scene_active_encounter(scene) : nil
        used = Actions.use(enactor, self.action, :options => self.options, :encounter => encounter)

        return if CharState.emit_error!(client, used)

        name = used.state['action']
        effect = used.state['effect']
        message = if effect
                    t('pf2e.action_used_effect', :name => enactor.name, :action => name, :cost => Actions.cost(name),
                                                 :effect => effect.name,
                                                 :lasts => ActiveEffects.remaining(effect))
                  else
                    t('pf2e.action_used', :name => enactor.name, :action => name, :cost => Actions.cost(name))
                  end

        enactor_room.emit message
        Scenes.add_to_scene(scene, message) if scene
        PF2Encounter.send_to_encounter(encounter, message) if encounter
      end
    end

    # `action/search <words>` - the actions whose names hold all of them.
    class PF2ActionSearchCmd
      include CommandHandler

      attr_accessor :words

      def parse_args
        self.words = trim_arg(cmd.args).to_s.downcase.split
      end

      def required_args
        [ self.words.empty? ? nil : self.words ]
      end

      # Enough to choose from; a search matching more than this wants another word.
      SHOWN = 30

      def handle
        found = Actions.catalogue.keys.select { |name| self.words.all? { |word| name.downcase.include?(word) } }.sort

        if found.empty?
          client.emit_failure t('pf2e.action_not_found', :action => self.words.join(' '))
          return
        end

        more = found.size > SHOWN ? t('pf2e.effect_search_more', :count => found.size - SHOWN) : ''

        client.emit_ooc t('pf2e.action_search_found', :list => found.first(SHOWN).join(', ')) + more
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # `action/available [<mode>]` or `action/available/<mode>` - the actions this character can use, in
    # one mode of play - combat, exploration, downtime, or just their reactions - or in all of them.
    class PF2ActionAvailableCmd
      include CommandHandler

      attr_accessor :mode

      def parse_args
        named = cmd.switch.to_s.split('/', 2)[1] || cmd.args

        @named = named.to_s.strip
        self.mode = Actions.mode(@named)
      end

      def check_mode
        return nil if @named.empty? || self.mode

        t('pf2e.action_mode_unknown', :mode => @named, :modes => Actions::MODES.keys.join(', '))
      end

      def handle
        client.emit PF2ActionAvailableTemplate.new(enactor, self.mode).render
      end
    end
  end
end
