module AresMUSH
  module Pf2emagic

    # A spell slot a feat adds at the highest rank the class casts, which only certain spells may use:
    # Divine Evolution's heal or harm, Primal Evolution's summons, Gifted Power's mystery spells. Each
    # may cast a spell that is not in the repertoire.
    #
    #   bonus_slot:
    #     spells: [ Heal, Harm ]                      # named outright
    #     spells_from: [ mystery, divine_access ]     # or worked out from the character
    #
    # The day's uses are kept in spells_today['bonus slots'], feat => uses left, which a rest refills.
    # The rank is not stored: it is the highest the class has slots at when the spell is cast.
    module BonusSlots

      TODAY = 'bonus slots'.freeze

      # Where `spells_from` looks. Each takes the character and their class.
      SOURCES = {
        # The spells the class's specialty grants: an oracle's mystery. A cantrip cannot go in a slot.
        'mystery' => lambda { |char, charclass|
          specialty = Global.read_config('pf2e_specialty', charclass.to_s, (char.pf2_base_info || {})['specialize'].to_s)

          Pf2e::Advancement::Repertoire.granted(specialty, char.pf2_level).reject do |spell|
            found = Pf2emagic.get_spell_details(spell)

            found.is_a?(Array) && found[1]['base_level'].to_i.zero?
          end
        },
        # Divine Access's cleric spells.
        'divine_access' => lambda { |char, charclass| Array(Pf2e.deity_choice_spells(char)[charclass]) },
        # Mysterious Repertoire's spell from another tradition.
        'off_list' => lambda { |char, charclass| Pf2emagic.off_list_picks(char, charclass) }
      }.freeze

      # feat => its details, for the character's feats that add a slot.
      def self.held(char)
        Pf2e::DraftSheet.of(char).feat_names.map(&:to_s).uniq(&:downcase).each_with_object({}) do |name, out|
          found = Pf2e.get_feat_details(name)
          next unless found.is_a?(Array) && found[1]['bonus_slot'].is_a?(Hash)

          out[found[0]] = found[1]
        end
      end

      # A class feat's slot is that class's: a sorcerer casting through an archetype does not spend it.
      def self.for_class?(details, charclass)
        classes = Array(details['assoc_charclass'])

        classes.empty? || classes.any? { |c| c.to_s.casecmp?(charclass.to_s) }
      end

      # The spells one feat's slot may cast.
      def self.eligible(char, charclass, block)
        named = Array(block['spells']).map(&:to_s)

        found = Array(block['spells_from']).flat_map do |source|
          reader = SOURCES[source.to_s]

          unless reader
            Global.logger.error "A bonus slot draws its spells from '#{source}', which is not one of #{SOURCES.keys.join(', ')}."
            next []
          end

          Array(reader.call(char, charclass))
        end

        (named + found).uniq(&:downcase)
      end

      # A rest's uses: one for each feat that adds a slot.
      def self.fresh(char)
        held(char).keys.each_with_object({}) { |feat, out| out[feat] = 1 }
      end

      # The feats whose slot still has a use today and may cast the spell.
      def self.usable(char, charclass, spell)
        left = ((char.magic&.spells_today || {})[TODAY] || {})

        held(char).select do |feat, details|
          next false unless left[feat].to_i.positive? && for_class?(details, charclass)

          eligible(char, charclass, details['bonus_slot']).any? { |s| s.casecmp?(spell.to_s) }
        end.keys
      end

      # [ feat, uses left, spells ] for each of a class's slots, for the magic display.
      def self.summary(char, charclass)
        left = ((char.magic&.spells_today || {})[TODAY] || {})

        held(char).select { |_feat, details| for_class?(details, charclass) }.map do |feat, details|
          [ feat, left[feat].to_i, eligible(char, charclass, details['bonus_slot']) ]
        end
      end

      def self.spend(magic, feat)
        today = magic.spells_today || {}
        uses = today[TODAY] || {}

        uses[feat] = uses[feat].to_i - 1
        today[TODAY] = uses

        magic.update(:spells_today => today)
      end
    end
  end
end
