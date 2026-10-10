module AresMUSH
  module Pf2e

    # The GM's table of an encounter: everyone in it as they stand, by the id they are targeted with.
    # A creature's figures are its stat block's under what it is under now, and what anyone is immune
    # to, weak to or resists is listed beneath them.
    class PF2EncounterScanTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      REACTIVE_STRIKE = 'Reactive Strike'.freeze

      # A row's figures, by who it is a row for.
      CHARACTER = {
        'kind' => ->(char) { char.pf2_base_info['charclass'] },
        'hp' => ->(char) { Pf2eHP.display_character_hp(char) },
        'ac' => ->(char) { Pf2eCombat.calculate_ac(char) },
        'perception' => ->(char) { Pf2eCombat.get_perception(char) },
        'save' => ->(char, save) { Pf2eCombat.get_save_bonus(char, save) },
        'reactive' => ->(char) { Actions.owned?(char, REACTIVE_STRIKE) },
        'iwr' => ->(char) { IWR.of(char) }
      }.freeze

      CREATURE = {
        'kind' => ->(npc) { "#{(npc.stat_block['adjustment'] || 'creature').capitalize} #{npc.stat_block['level']}" },
        'hp' => ->(npc) { Pf2eHP.display_hp(npc.hp_left, npc.max_hp) },
        'ac' => ->(npc) { Npcs.stat(npc, 'ac')['total'] },
        'perception' => ->(npc) { Npcs.stat(npc, 'perception')['total'] },
        'save' => ->(npc, save) { Npcs.stat(npc, 'save', save)['total'] },
        'reactive' => ->(npc) { Array(npc.stat_block['actions']).any? { |one| one['name'] == REACTIVE_STRIKE } },
        'iwr' => ->(npc) { Npcs.iwr(npc) }
      }.freeze

      IWR_WORDS = { 'immunity' => 'Immune', 'weakness' => 'Weak', 'resistance' => 'Resist' }.freeze

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_scan.erb"
      end

      def title
        t('pf2e.encounter_table_title', :id => @encounter.id)
      end

      def header_line
        "%b#{item_color}#{left("#", 4)}#{left("Name", 18)}%b#{left("Kind", 12)}%b#{left("HP", 15)}%b#{left("AC", 3)}%b" \
          "#{left("Per", 4)}%b#{left("Fort", 4)}%b#{left("Ref", 4)}%b#{left("Will", 4)}%b#{left("RS", 2)}%xn"
      end

      # Everyone in the encounter in the order of their ids: a row each, and a line beneath it where
      # there is something they shrug off or that hurts them more.
      def combatant_list
        Combatants.all(@encounter).select(&:holder).sort_by { |one| one.number.to_i }.flat_map do |one|
          # One read block per combatant, because the figures all ask the same questions about the same one.
          AresMUSH::Pf2e::SheetReads.holding(one.holder) { [ row(one), iwr_line(one) ].compact }
        end
      end

      def row(one)
        holder = one.holder
        figures = one.creature? ? CREATURE : CHARACTER
        saves = %w{fortitude reflex will}.map { |save| left(signed(figures['save'].call(holder, save)), 4) }

        "%b#{left(one.ref, 4)}#{left(one.label, 18)}%b#{left(figures['kind'].call(holder), 12)}%b" \
          "#{left(figures['hp'].call(holder), 15)}%b#{left(figures['ac'].call(holder), 3)}%b" \
          "#{left(signed(figures['perception'].call(holder)), 4)}%b#{saves.join('%b')}%b" \
          "#{figures['reactive'].call(holder) ? 'Y' : 'N'}"
      end

      # `Immune poison; Weak fire 5; Resist cold 5, slashing 5`, or nothing.
      def iwr_line(one)
        held = (one.creature? ? CREATURE : CHARACTER)['iwr'].call(one.holder)
        parts = IWR_WORDS.filter_map do |kind, word|
          listed = Array(held[kind]).map { |entry| [ Array(entry['type']).join('/'), entry['value'] ].compact.join(' ') }

          listed.empty? ? nil : "#{word} #{listed.join(', ')}"
        end

        parts.empty? ? nil : "%b#{' ' * 4}#{parts.join('; ')}"
      end

      def signed(value)
        value.to_i.negative? ? value.to_s : "+#{value.to_i}"
      end
    end
  end
end
