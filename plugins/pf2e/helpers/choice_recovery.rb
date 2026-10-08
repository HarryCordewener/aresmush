module AresMUSH
  module Pf2e

    # What a character chose for a feat or a class, for one approved before choices were kept in the
    # ledger, read back from what the choice left on their sheet.
    #
    # Each choice they hold with nothing recorded is tried against every option it offers: an option is
    # the one chosen where everything it grants is on the sheet - Domain Initiate's Family domain, by its
    # focus spell - and no other option's is. That one is recorded as a `make_choice` at the level the
    # feat was taken. A choice that granted nothing to read, as Assurance's skill grants nothing, or that
    # two options would explain, is answered as unresolved, for staff to set with
    # `admin/set <character>/choice = <choice>: <what was chosen>`.
    #
    # One character at a time, or `recover_all!` from tinker. A choice already recorded is left alone.
    module ChoiceRecovery

      def self.recover!(char)
        out = { 'recovered' => {}, 'unresolved' => [] }

        held(char).each_pair do |name, takings|
          recorded = Pf2e.choice_labels_for(char, name)

          next if recorded.size >= takings

          block = Pf2e.find_choice_block(char, name)

          next unless block

          options = Array(Pf2e.choice_options(char, name, block)) - recorded
          chosen = options.select { |option| left?(char, block, name, option) }

          if chosen.size == 1
            record!(char, name, chosen.first)
            out['recovered'][name] = chosen.first
          else
            out['unresolved'] << name
          end
        end

        out
      end

      # Every character, with what was recovered and what staff are left to set.
      def self.recover_all!(characters: Character.all)
        characters.each_with_object({ 'recovered' => {}, 'unresolved' => {}, 'refused' => {} }) do |char, out|
          next unless Ledger.finalized?(char)

          found = recover!(char)
          out['recovered'][char.name] = found['recovered'] unless found['recovered'].empty?
          out['unresolved'][char.name] = found['unresolved'] unless found['unresolved'].empty?
        rescue StandardError => e
          out['refused'][char.name] = e.message
        end
      end

      # The choices they hold, by how many times: a feat once per taking, a class's choice once.
      def self.held(char)
        feats = (char.pf2_feats || {}).values.flatten.select { |feat| Pf2e.feat_choice_block_for(feat) }.tally

        Pf2e.class_choice_blocks(char).keys.each_with_object(feats) { |name, out| out[name] ||= 1 }
      end

      # Whether an option's grants are all on the sheet. An option that grants nothing the sheet can show
      # is not evidence of anything.
      def self.left?(char, block, name, option)
        return feats(char).include?(option.to_s.downcase) if Pf2e.choice_grants_feat?(block)

        checks = checks_for(char, Pf2e.choice_grants(char, block, option, name))

        checks.any? && checks.all?
      end

      def self.checks_for(char, grants)
        return [] unless grants.is_a?(Hash)

        focus = Pf2emagic::Entries.all_focus(char.magic).map(&:downcase)
        trained = char.skills.to_a.reject { |one| one.prof_level.to_s == 'untrained' }.map { |one| one.name.downcase }

        checks = []
        ((grants['magic_stats'] || {})['focus_spell'] || {}).each_value do |spells|
          Array(spells).each { |spell| checks << focus.include?(spell.to_s.downcase) }
        end
        Array(grants['feat']).each { |feat| checks << feats(char).include?(feat.to_s.downcase) }
        Array(grants['skill']).each { |skill| checks << trained.include?(skill.to_s.downcase) }
        checks
      end

      def self.feats(char)
        (char.pf2_feats || {}).values.flatten.map { |feat| feat.to_s.downcase }
      end

      # Recorded at the level the feat was taken, so a rollback past it takes the choice back too.
      def self.record!(char, name, label)
        taken = Ledger.rows(char).find { |row| row['kind'] == 'grant_feat' && row['payload']['feat'].to_s.casecmp?(name) }
        level = taken ? [ taken['effective_level'].to_i, 1 ].max : 1

        Ledger.write(char, :source_type => 'imported', :source_ref => 'choice read back from the sheet',
                           :effective_level => level, :granted_by => 'Choice recovery') do |txn|
          txn.grant('make_choice', 'choice' => name, 'label' => label)
        end
      end
    end
  end
end
