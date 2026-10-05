require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Narrowing a long option list.
    #
    # The message behind a big pool says "236 eligible options, too many to list here" and names
    # the info command - but that command then hands back six pages, which is barely more use than
    # the refusal was. A filter is what makes the hint actionable.
    describe :info_option_display do

      def lores
        [ 'Architecture Lore', 'Arboreal Lore', 'Baking Lore', 'Dragon Lore', 'Engineering Lore' ]
      end

      # The command as dispatched; the display reads its page, and its words for the next-page hint.
      def cmd(page = 1)
        double(:prefix => nil, :root => 'cg', :switch => 'info', :args => 'Additional Lore', :page => page)
      end

      it "should list a short pool inline" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd)

        expect(display[:text]).to include 'Dragon Lore'
      end

      it "should keep only the options containing the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'arch')

        expect(display[:text]).to include 'Architecture Lore'
        expect(display[:text]).to_not include 'Baking Lore'
      end

      it "should ignore the case of the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'DRAGON')

        expect(display[:text]).to include 'Dragon Lore'
      end

      it "should match anywhere in the name, not only the start" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'bore')

        expect(display[:text]).to include 'Arboreal Lore'
      end

      # Saying "nothing matched dragn" is actionable; an empty list is not, and the old
      # no-options message would have blamed the pool rather than the filter.
      it "should say the filter matched nothing, and name the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'zzz')

        expect(display[:error]).to include 'zzz'
      end

      it "should still say the pool is empty when there was nothing to filter" do
        display = Pf2e.info_option_display('Additional Lore', [], cmd, 'arch')

        expect(display[:error]).to include 'Additional Lore'
      end

      it "should count pages against the filtered list, not the whole pool" do
        many = (1..60).map { |n| "Filler #{n} Lore" } + [ 'Dragon Lore' ]
        display = Pf2e.info_option_display('Additional Lore', many, cmd, 'dragon')

        expect(display[:text]).to include 'Dragon Lore'
        expect(display[:error]).to be_nil
      end

      # A pool too long for one page says how to reach the next one, in the words of the command
      # that asked for it.
      it "should name the command for the next page under a long list" do
        many = (1..60).map { |n| "Filler #{n} Lore" }
        display = Pf2e.info_option_display('Additional Lore', many, cmd)

        expect(display[:text]).to include 'cg/info2 Additional Lore'
      end
    end
  end
end
