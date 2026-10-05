require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A paged list says how to reach its next page, rebuilt from the command that drew it.
    #
    # feat/search used to spell its own hint out by hand, and every other paged PF2e list said
    # "page 1 of 4" with no word on what to type - the page number goes after the switch
    # ('skills/lore2 city'), which nobody guesses.
    describe "the next-page hint" do

      def paginator(current, total)
        double(:current_page => current, :total_pages => total, :page_footer => 'PAGE BAR')
      end

      def hint_for(text, current = 1, total = 3)
        Pf2e.next_page_hint(Command.new(text), paginator(current, total))
      end

      describe :next_page_hint do
        it "should put the page after the root when there is no switch" do
          expect(hint_for('listxp')).to include 'listxp2'
        end

        it "should keep the arguments" do
          expect(hint_for('listxp Bob')).to include 'listxp2 Bob'
        end

        it "should put the page after the switch, before the arguments" do
          expect(hint_for('skills/lore city')).to include 'skills/lore2 city'
        end

        it "should count on from the page being shown" do
          expect(hint_for('skills/lore2 city', 2)).to include 'skills/lore3 city'
        end

        it "should keep a command prefix" do
          expect(hint_for('+feat/search skill=Athletics')).to include '+feat/search2 skill=Athletics'
        end

        # Shortcuts are applied before a command reaches its handler, so the hint names the full
        # command rather than the shortcut the player typed. It still works when typed.
        it "should name the command as dispatched, after a shortcut has rewritten it" do
          command = Command.new('cg/skill free=Arcana')
          CommandAliasParser.substitute_aliases(nil, command, { 'cg/skill' => 'skill/set' })

          expect(Pf2e.next_page_hint(command, paginator(1, 2))).to include 'skill/set2 free=Arcana'
        end

        it "should say nothing on the last page" do
          expect(hint_for('skills/lore city', 3, 3)).to be_nil
        end

        it "should say nothing when everything fits on one page" do
          expect(hint_for('skills/lore deity', 1, 1)).to be_nil
        end

        it "should say nothing without a command" do
          expect(Pf2e.next_page_hint(nil, paginator(1, 3))).to be_nil
        end
      end

      describe PagedTemplate do

        def footer_for(paginator, cmd)
          template = Class.new { include PagedTemplate }.new
          template.instance_variable_set(:@paginator, paginator)
          template.instance_variable_set(:@cmd, cmd)
          template.page_footer
        end

        it "should be the plain page bar for a template given no command" do
          expect(footer_for(paginator(1, 3), nil)).to eq 'PAGE BAR'
        end

        # %lf, not a drawn rule, so a screen reader is sent nothing for the closing line.
        it "should put the hint under the page bar, closed off by the footer line" do
          footer = footer_for(paginator(1, 3), Command.new('listxp'))

          expect(footer).to start_with 'PAGE BAR%r'
          expect(footer).to include 'listxp2'
          expect(footer).to end_with '%r%lf'
        end

        it "should be the plain page bar on the last page" do
          expect(footer_for(paginator(3, 3), Command.new('listxp3'))).to eq 'PAGE BAR'
        end
      end
    end
  end
end
