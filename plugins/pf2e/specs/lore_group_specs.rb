require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # skills/lore <group> lists the lores in one of the groups named in pf2e_options.yml. Only those
    # groups answer, not every lore_groups tag, and a group with sections comes back split by them.
    describe "the lore groups" do

      let(:skills) do
        {
          'Arcana' => { 'key_abil' => 'Intelligence' },
          'Radan Lore' => { 'lore_groups' => [ 'deity' ] },
          'Althean Lore' => { 'lore_groups' => [ 'Deity' ] },
          'Secret Lore' => { 'lore_groups' => [ 'deity' ], 'hidden' => true },
          'Joke Lore' => { 'lore_groups' => [ 'deity' ] },
          'Bardic Lore' => { 'key_abil' => 'Intelligence' },
          'Shadow Town Lore' => { 'lore_groups' => [ 'planar', 'shadow plane' ] },
          'Bright Town Lore' => { 'lore_groups' => [ 'planar', 'light plane' ] },
          'Lost Town Lore' => { 'lore_groups' => [ 'planar' ] }
        }
      end

      let(:lists) do
        {
          'craft' => { 'name' => 'Crafting', 'aliases' => [ 'crafting', 'smithing' ] },
          'deity' => {},
          'planar' => {
            'aliases' => [ 'planes' ],
            'sections_per_page' => 2,
            'sections' => { 'light plane' => 'Light Planes', 'shadow plane' => 'Shadow Planes' }
          }
        }
      end

      before do
        allow(Global).to receive(:read_config).with('pf2e_skills').and_return(skills)
        allow(Global).to receive(:read_config).with('pf2e', 'lore_group_lists').and_return(lists)
        allow(Global).to receive(:read_config).with('pf2e', 'hidden_options').and_return([ 'Joke Lore' ])
      end

      describe "lore_skills" do
        it "should give every lore but the hidden ones when no group is asked for" do
          expect(Pf2e.lore_skills).to eq [ 'Althean Lore', 'Bardic Lore', 'Bright Town Lore', 'Joke Lore',
                                           'Lost Town Lore', 'Radan Lore', 'Shadow Town Lore' ]
        end

        it "should match a group whatever its case" do
          expect(Pf2e.lore_skills('DEITY')).to eq [ 'Althean Lore', 'Joke Lore', 'Radan Lore' ]
        end
      end

      describe "find_lore_group" do
        it "should find a group by its name or an alias" do
          expect(Pf2e.find_lore_group('Deity')).to eq 'deity'
          expect(Pf2e.find_lore_group('planes')).to eq 'planar'
        end

        it "should not answer to a tag that is not a listed group" do
          expect(Pf2e.find_lore_group('shadow plane')).to be_nil
        end
      end

      describe "lore_group_sections" do
        it "should give a group without sections as one list, leaving out hidden options" do
          expect(Pf2e.lore_group_sections('deity')).to eq [ [ nil, [ 'Althean Lore', 'Radan Lore' ] ] ]
        end

        it "should split a group by its sections in the order listed, with the rest under Other" do
          expect(Pf2e.lore_group_sections('planar')).to eq [
            [ 'Light Planes', [ 'Bright Town Lore' ] ],
            [ 'Shadow Planes', [ 'Shadow Town Lore' ] ],
            [ 'Other', [ 'Lost Town Lore' ] ]
          ]
        end
      end

      # City is sixty-odd lores; paged by whole sections, so no region splits across two pages.
      describe "lore_group_page" do
        it "should put whole sections on a page, in the order listed" do
          page = Pf2e.lore_group_page('planar', 1)

          expect(page.page_items.map(&:first)).to eq [ 'Light Planes', 'Shadow Planes' ]
          expect(page.total_pages).to eq 2
        end

        it "should carry what is left onto a shorter last page" do
          expect(Pf2e.lore_group_page('planar', 2).page_items).to eq [ [ 'Other', [ 'Lost Town Lore' ] ] ]
        end

        it "should be out of bounds past the last page" do
          expect(Pf2e.lore_group_page('planar', 3).out_of_bounds?).to eq true
        end

        it "should keep a group without sections_per_page on one page" do
          page = Pf2e.lore_group_page('deity', 1)

          expect(page.total_pages).to eq 1
          expect(page.page_items).to eq [ [ nil, [ 'Althean Lore', 'Radan Lore' ] ] ]
        end
      end

      # Lores are off the plain skills list, so the list has to say where they went.
      describe "the pointer to skills/lore" do

        def emitted_by(klass, args)
          client = double
          text = nil
          allow(client).to receive(:emit) { |msg| text = msg }

          handler = klass.new(client, double(:args => args, :page => 1), double)
          handler.parse_args
          handler.handle
          text
        end

        before do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_skills').and_return(skills)
          allow(Global).to receive(:read_config).with('pf2e', 'lore_group_lists').and_return(lists)
          allow(Global).to receive(:read_config).with('pf2e', 'hidden_options').and_return([ 'Joke Lore' ])
        end

        it "should be under the plain skills list" do
          text = emitted_by(PF2SkillListCmd, nil)

          expect(text).to include 'Arcana'
          expect(text).to include 'skills/lore'
          expect(text).to include 'help skills'
        end

        it "should give the index its groups and an Aliases section" do
          text = emitted_by(PF2LoreGroupListCmd, nil)

          expect(text).to include 'Crafting'
          expect(text).to include 'Aliases'
          expect(text).to include 'is an alias for Planar Lores'
        end

        it "should title a group by its display name" do
          expect(emitted_by(PF2LoreGroupListCmd, 'smithing')).to include 'Crafting Lores'
        end

        it "should not be under a lore group's list" do
          text = emitted_by(PF2LoreGroupListCmd, 'deity')

          expect(text).to include 'Radan Lore'
          expect(text).to_not include 'help skills'
        end
      end

      describe "lore_group_display_name" do
        it "should use the configured name" do
          expect(Pf2e.lore_group_display_name('craft')).to eq 'Crafting'
        end

        it "should capitalize the key when there is no name" do
          expect(Pf2e.lore_group_display_name('deity')).to eq 'Deity'
        end
      end

      describe "lore_group_index" do
        it "should list each group by its display name, in the order listed" do
          expect(Pf2e.lore_group_index).to eq [ 'Crafting', 'Deity', 'Planar' ]
        end
      end

      describe "lore_group_alias_lines" do
        it "should give one line per alias, naming the group it stands for" do
          lines = Pf2e.lore_group_alias_lines

          expect(lines.size).to eq 2
          expect(lines[0]).to include 'Smithing'
          expect(lines[0]).to include 'Crafting Lores'
          expect(lines[1]).to include 'Planes'
          expect(lines[1]).to include 'Planar Lores'
        end

        # 'crafting is an alias for Crafting Lores' tells the player nothing.
        it "should leave out an alias that only repeats the display name" do
          expect(Pf2e.lore_group_alias_lines.join).to_not match(/%xcCrafting%xn/)
        end
      end
    end
  end
end
