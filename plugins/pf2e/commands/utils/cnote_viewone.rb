module AresMUSH
  module Pf2e
    class PF2ViewOneCnoteCmd
      include CommandHandler

      attr_accessor :character, :notename

      def parse_args
        # Argument pattern: [character/]notename
        args = trimmed_list_arg(cmd.args,"/")

        char_specified = args[1] ? true : false

        self.character = char_specified ? args[0] : nil
        self.notename = char_specified ? downcase_arg(args[1]) : downcase_arg(args[0])
      end

      def required_args
        [ self.notename ]
      end

      def 

      def check_permissions
        # Any character may view their own; only people who can see alts can see others'.

        return nil if !self.character
        return nil if enactor.has_permission?('manage_alts')
        return t('dispatcher.not_allowed')
      end

      def handle

        # If no argument, code assumes reference is to self.

        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        # The list of cnotes is a hash on the character. Grab and filter for notename, noting that a partial match can grab more than one key.

        cnotes = char.pf2_cnotes.select { |key, value| key.downcase.include?(self.notename) }

        template = PF2CNoteTemplate.new(char, cnotes, client)

        client.emit template.render

      end

    end
  end
end