module AresMUSH
  module Pf2egear
    class PF2EtchPropertyCmd
      include CommandHandler

      attr_accessor :target, :category, :item_index, :rune_name

      def parse_args
          if (args = cmd.args.match(/([^\s=]+)=(\w+)\/(\d+)\/(.*)/))
            self.target = args[1]
            self.category = args[2]
            @item_index = args[3].to_i
            self.rune_name = args[4]
          else
            client.emit_failure t('pf2egear.rune_property_cmd_fail')
            return
          end
      end

      def check_permissions
        # Admin may only swap out runes
        if !enactor.is_admin?
          client.emit_failure t("pf2egear.rune_no_admin")
          return
        end
      end

      def check_character_exists
        if !(@char = Character.find_one_by_name(self.target))
          return t('pf2egear.target_not_found', :name => self.target)
          return nil
        end
      end
      
      def check_item_exists
        found = Pf2egear::Inventory.item(@char, category, @item_index)

        return t(found.key) if found.err?

        @item = found.state

        nil
      end

      # A rune the catalogue does not have is a rune that does nothing: what a rune is worth lives in
      # `pf2e_runes.yml`, and a name nothing matches would etch a word onto the item and no mechanics.
      def check_rune_exists
        @rune = Pf2egear.rune_named(self.rune_name)

        return nil if @rune

        t('pf2egear.rune_property_unknown', :rune_name => self.rune_name)
      end

      # A rune fits the kind of thing it is for, and an item holds as many as its potency rune is worth.
      # Taking one off is always allowed, which is what lets an over-runed item be put right.
      def check_rune_fits
        return nil if etched?

        wanted = Pf2egear.rune_entry(@rune)['kind'].to_s
        kind = Pf2egear::Inventory.canonical(self.category).to_s

        unless kind.start_with?(wanted)
          return t('pf2egear.rune_property_wrong_kind', :rune_name => @rune, :kind => wanted)
        end

        return nil if held_runes.size < Pf2egear.rune_slots(@item)

        t('pf2egear.rune_property_no_slot', :slots => Pf2egear.rune_slots(@item))
      end

      def held_runes
        Array((@item.runes || {}).dig('property', 'list'))
      end

      def etched?
        held_runes.any? { |one| Pf2e::Domains.slug(one) == Pf2e::Domains.slug(@rune) }
      end

      def handle
        # A property rune is a toggle: the list has it or it does not.
        runes = @item.runes || {}
        runes['property'] ||= { 'list' => [] }
        list = held_runes
        operation = etched? ? 'unset' : 'set'

        if etched?
          list = list.reject { |one| Pf2e::Domains.slug(one) == Pf2e::Domains.slug(@rune) }
        else
          list = (list + [ @rune ]).sort
        end

        runes['property']['list'] = list
        @item.update(runes: runes)
        client.emit_success t('pf2egear.rune_property_set', :rune_name => @rune, :operation => operation, :char => self.target.titlecase, :item_name => @item.nickname.nil? ? @item.name : @item.nickname)
      end
    end
  end
end
