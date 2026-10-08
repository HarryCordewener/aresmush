module AresMUSH
  module Pf2e

    class PF2FormulaAddCmd
      include CommandHandler

      attr_accessor :character, :category, :name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_arg3)

        self.character = trim_arg(args.arg1)
        self.category = downcase_arg(args.arg2)
        self.name = trim_arg(args.arg3)
      end

      def required_args
        [ self.character, self.category, self.name ]

      end

      def check_permissions
        return nil if enactor.has_permission?("manage_sheet")
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        found = Pf2e::Crafting.entry(self.category, self.name)

        return if Pf2e::CharState.emit_error!(client, found)

        named = found.state.first

        return client.emit_failure(t('pf2e.formula_known', :formula => named)) if Pf2e::Crafting.known?(char, self.category, named)

        Pf2e::Crafting.learn!(char, self.category, named, :source_type => 'staff', :source_ref => "formula: #{named}",
                                                          :granted_by => enactor.name)

        client.emit_success t('pf2e.updated_ok', :element => 'Formulas', :char => char.name)
      end

    end
  end
end