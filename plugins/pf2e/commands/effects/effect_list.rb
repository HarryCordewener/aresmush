module AresMUSH
  module Pf2e

    # `effects [<who>]` - what someone is under, and for how long.
    class PF2EffectListCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args) || enactor_name
      end

      def handle
        found = ClassTargetFinder.find(self.target, Character, enactor)

        unless found.found?
          client.emit_failure t('pf2e.char_not_found')
          return
        end

        client.emit PF2EffectListTemplate.new(found.target).render
      end
    end

    # `effect/view <effect>` - what an effect does, before anyone is put under it.
    class PF2EffectViewCmd
      include CommandHandler

      attr_accessor :effect

      def parse_args
        self.effect = trim_arg(cmd.args)
      end

      def required_args
        [ self.effect ]
      end

      def handle
        found = ActiveEffects.find(self.effect)

        return if CharState.emit_error!(client, found)

        client.emit PF2EffectViewTemplate.new(found.state, ActiveEffects.info(found.state)).render
      end
    end

    # `effect/search <words>` - the effects whose names hold all of them.
    class PF2EffectSearchCmd
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
        found = ActiveEffects.catalogue.keys.select { |name|
          self.words.all? { |word| name.downcase.include?(word) }
        }.sort

        if found.empty?
          client.emit_failure t('pf2e.effect_not_found', :effect => self.words.join(' '))
          return
        end

        more = found.size > SHOWN ? t('pf2e.effect_search_more', :count => found.size - SHOWN) : ''

        client.emit_ooc t('pf2e.effect_search_found', :list => found.first(SHOWN).join(', ')) + more
      end
    end
  end
end
