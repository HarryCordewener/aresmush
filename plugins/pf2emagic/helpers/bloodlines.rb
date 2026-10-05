module AresMUSH
  module Pf2emagic

    # A rank key as a repertoire keeps it, from a gift table's '0' or a level block's 'cantrip'.
    def self.gift_rank_key(rank)
      rank.to_s.casecmp?('cantrip') || rank.to_s == '0' ? 'cantrip' : rank.to_s
    end

    # rank => [ spell ] from the table a bloodline names for its 1st-level choice, at the ranks
    # asked for. Empty for a bloodline with no such table or a character with no choice made.
    def self.gift_spells_for(charclass, bloodline, option, ranks)
      info = Global.read_config('pf2e_specialty', charclass.to_s, bloodline.to_s) || {}
      table = info['choice_spells'] && Global.read_config('pf2e_subclass', info['choice_spells'], option.to_s)

      return {} unless table.is_a?(Hash)

      Array(ranks).each_with_object({}) do |rank, out|
        key = table.keys.find { |k| gift_rank_key(k) == gift_rank_key(rank) }
        spell = key && table[key]

        out[gift_rank_key(rank)] = [ spell ] if spell.present?
      end
    end

    # The gift spells a character's own bloodline choice decides, at the ranks a level block lists.
    def self.choice_gift_spells(char, ranks)
      base = char.pf2_base_info || {}

      gift_spells_for(base['charclass'], base['specialize'], base['specialize_info'], ranks)
    end

    # Every sorcerous gift spell a bloodline grants: its level blocks' own, and its 1st-level
    # choice's. What Greater Crossblooded Evolution chooses from.
    def self.all_gift_spells(charclass, bloodline, option)
      info = Global.read_config('pf2e_specialty', charclass.to_s, bloodline.to_s) || {}
      blocks = [ info['chargen'] ] + (info['advance'] || {}).values

      listed = blocks.flat_map { |block| ((block || {})['magic_stats'] || {})['addrepertoire'].to_h.values.flatten }
      table = info['choice_spells'] && Global.read_config('pf2e_subclass', info['choice_spells'], option.to_s)

      (listed + (table.is_a?(Hash) ? table.values : [])).compact.map(&:to_s).uniq
    end

    # The blood magic a character knows: their own bloodline's, and one per bloodline a choice
    # shares it from (Crossblooded Evolution). Each { bloodline, name, text, damage }.
    def self.blood_magic(char)
      base = char.pf2_base_info || {}
      charclass = base['charclass']

      held = [ [ base['specialize'], base['specialize_info'] ] ] + Pf2e.shared_bloodlines(char)

      held.filter_map do |bloodline, option|
        magic = (Global.read_config('pf2e_specialty', charclass.to_s, bloodline.to_s) || {})['blood_magic']

        next unless magic.is_a?(Hash)

        {
          'bloodline' => bloodline,
          'name' => magic['name'],
          'text' => magic['text'],
          'damage' => (magic['damage_by_choice'] || {})[option.to_s]
        }
      end
    end
  end
end
