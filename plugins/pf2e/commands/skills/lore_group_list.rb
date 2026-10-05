module AresMUSH
  module Pf2e
    class PF2LoreGroupListCmd
      include CommandHandler

      attr_accessor :group_name

      def parse_args
        self.group_name = downcase_arg(cmd.args)
      end

      def handle
        unless self.group_name
          template = PF2SkillsListTemplate.new([ [ nil, Pf2e.lore_group_index ] ], t('pf2e.lore_groups_title'),
                                               nil, nil, alias_block)
          client.emit template.render
          return
        end

        group = Pf2e.find_lore_group(self.group_name)

        unless group
          client.emit_failure t('pf2e.lore_group_not_found', :group => self.group_name)
          return
        end

        paginator = Pf2e.lore_group_page(group, cmd.page)

        if paginator.out_of_bounds?
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        title = t('pf2e.lore_group_title', :group => Pf2e.lore_group_display_name(group))
        template = PF2SkillsListTemplate.new(paginator.page_items, title, paginator, cmd)

        client.emit template.render
      end

      # The index's Aliases section, headed like a lore group's sections. Nil when no group has one.
      def alias_block
        lines = Pf2e.lore_group_alias_lines
        return nil if lines.empty?

        heading = "#{Global.read_config('pf2e', 'title_color')}#{t('pf2e.lore_group_aliases_heading')}%xn"

        ([ heading ] + lines).join("%r")
      end
    end
  end
end
