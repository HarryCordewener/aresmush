module AresMUSH
  module Pf2e
    class PF2SkillListCmd
      include CommandHandler

      attr_accessor :term

      def parse_args
        self.term = downcase_arg(cmd.args)
      end

      def handle
        skills = Global.read_config('pf2e_skills')
        skills_list = skills.keys - Global.read_config('pf2e', 'hidden_options')
        skills_list = skills_list.reject { |skill| Pf2e.lore_skill?(skill, skills[skill]) }

        if self.term
          skills_list = skills_list.filter { |skill| skill.downcase.match? self.term }
        end

        template = PF2SkillsListTemplate.new([ [ nil, skills_list ] ], nil, nil, nil, t('pf2e.skills_list_lore_note'))

        client.emit template.render
      end
    end
  end
end
