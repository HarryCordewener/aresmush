module AresMUSH
  module Pf2emagic
    class PF2DisplayPreparedCmd
      include CommandHandler

      attr_accessor :caster_class

      def parse_args
        self.caster_class = titlecase_arg(cmd.args)
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
        return nil
      end

      def handle
        magic = enactor.magic

        unless magic && Pf2emagic.is_caster?(enactor)
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        # A class whose only preparations are through a feat (Split Slot, Spell Mastery) is listed too.
        prepared_spells = magic.spells_prepared.dup
        ((magic.slot_pairs || {}).keys + (magic.mastered_spells || {}).keys).each { |cc| prepared_spells[cc] ||= {} }

        if prepared_spells.empty?
          client.emit_failure t('pf2emagic.no_prepared_spells')
          return
        end

        if self.caster_class
          class_spells = prepared_spells[self.caster_class] || {}

          if class_spells.empty? && !prepared_spells.key?(self.caster_class)
            client.emit_failure t('pf2emagic.no_prepared_spells_class', :cc => self.caster_class)
            return
          end

          # Keep the { class => { rank => spells } } shape the template expects.
          prepared_spells = { self.caster_class => class_spells }
        end

        template = PF2DisplayPreparedSpellsTemplate.new(enactor, prepared_spells, client)

        client.emit template.render

      end

    end
  end
end
