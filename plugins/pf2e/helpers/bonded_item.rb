module AresMUSH
  module Pf2e

    # A wizard's Drain Bonded Item: a spell they prepared today and have cast is theirs to cast again,
    # once a day. It goes back into the day's slots at the rank it was prepared at, to be cast with
    # `+e/cast` as before.
    module BondedItem

      NAME = 'Drain Bonded Item'.freeze

      def self.drain(scene, words, out)
        holder = scene.actor.holder
        magic = holder.magic
        term = Array(words).map(&:to_s).reject(&:empty?).first

        return Err.new(:name_a_spell, 'pf2e.drain_name_a_spell') unless magic && term

        found = Pf2emagic.get_spell_details(term)

        return Err.new(:no_spell, 'pf2e.drain_nothing', 'spell' => term) if found.is_a?(String)

        spell = found.first
        today = magic.spells_today || {}
        cast = cast_today(magic.spells_prepared || {}, today, spell)

        return Err.new(:not_cast, 'pf2e.drain_nothing', 'spell' => spell) unless cast

        charclass, rank = cast
        today = today.merge(charclass => today[charclass].merge(rank => Array(today[charclass][rank]) + [ spell ]))
        magic.update(:spells_today => today)

        out['lines'] << Telling.event('pf2e.drain_done', :actor => scene.actor.label, :spell => spell, :rank => rank)

        Ok.new(:state => out)
      end

      # The class and rank a spell was prepared at today and has been cast from: prepared there more
      # often than it is left there.
      def self.cast_today(prepared, today, spell)
        prepared.each do |charclass, ranks|
          (ranks || {}).each do |rank, spells|
            next if rank.to_s == 'cantrip'

            left = Array((today[charclass] || {})[rank]).count(spell)

            return [ charclass, rank ] if Array(spells).count(spell) > left && today[charclass]
          end
        end

        nil
      end
    end
  end
end
