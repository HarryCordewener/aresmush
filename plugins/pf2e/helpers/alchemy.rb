module AresMUSH
  module Pf2e

    # An alchemist's preparations.
    #
    # What they will make is a list on their sheet, the way a prepared caster's spells are: `alchemy/prepare`
    # writes it, and a rest turns it into the day's items, which last until their next preparations. Their
    # infused reagents are the budget - each batch makes two items - and what a rest does not spend is left
    # for Quick Alchemy, which makes one item in the moment, to hand for the turn.
    module Alchemy

      def self.settings
        Global.read_config('pf2e_crafting', 'alchemy') || {}
      end

      def self.per_batch
        settings['items_per_batch'].to_i.clamp(1, 10)
      end

      # Their reagents as `[ total, allocated, remaining ]`, which a rest refreshes.
      def self.reagents(holder)
        Array((holder.pf2_reagents || {})['alchemist'])
      end

      def self.alchemist?(holder)
        reagents(holder).any? || Array((holder.pf2_features || {})['charclass_features']).any? { |one| one.to_s.casecmp?('Advanced Alchemy') }
      end

      def self.batches(holder)
        reagents(holder).first.to_i
      end

      # How many batches of reagents their preparations give them a day: an alchemist's level and
      # Intelligence, and anyone else's level, the reagents a dedication grants.
      def self.capacity(holder)
        level = holder.pf2_level.to_i

        return level unless (holder.pf2_base_info || {})['charclass'] == 'Alchemist'

        level + Pf2eAbilities.abilmod(Pf2eAbilities.get_score(holder, 'Intelligence'))
      end

      def self.left(holder)
        reagents(holder).last.to_i
      end

      def self.spend!(holder, batches)
        total, allocated, remaining = reagents(holder)

        holder.update(:pf2_reagents => (holder.pf2_reagents || {}).merge(
          'alchemist' => [ total.to_i, allocated.to_i, [ remaining.to_i - batches, 0 ].max ]))
      end

      # What they have said they will make: `{ "Alchemist's Fire (Lesser)" => 2 }`.
      def self.plan(char)
        char.pf2_alchemy_plan || {}
      end

      def self.planned(char)
        plan(char).values.sum(&:to_i)
      end

      # An item is theirs to prepare where it is alchemical, no higher level than they are, and they know
      # its formula; and they can only prepare what their reagents will make.
      def self.prepare!(char, name, quantity)
        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(char)

        found = Crafting.entry('consumables', name)

        return found if found.err?

        named, info = found.state

        return Err.new(:not_alchemical, 'pf2e.alchemy_not_alchemical', 'item' => named) unless alchemical?(info)
        return Err.new(:too_high, 'pf2e.alchemy_too_high', 'item' => named, 'level' => info['level']) if info['level'].to_i > char.pf2_level.to_i
        return Err.new(:no_formula, 'pf2e.alchemy_no_formula', 'item' => named) unless Crafting.known?(char, 'consumables', named)

        wanted = plan(char).merge(named => plan(char)[named].to_i + quantity.to_i).reject { |_name, many| many.to_i < 1 }

        return Err.new(:no_reagents, 'pf2e.alchemy_no_reagents', 'items' => capacity(char) * per_batch) if
          wanted.values.sum(&:to_i) > capacity(char) * per_batch

        char.update(:pf2_alchemy_plan => wanted)

        Ok.new(:state => wanted)
      end

      def self.alchemical?(info)
        Array(info['traits']).map(&:to_s).map(&:downcase).include?('alchemical')
      end

      def self.clear!(char, name = nil)
        char.update(:pf2_alchemy_plan => name ? plan(char).reject { |one, _many| one.casecmp?(name) } : {})
      end

      # A rest: the day's preparations are made, and the reagents they took are spent. Answers what was
      # made, as events for whoever tells it.
      def self.at_rest!(holder)
        prepared = plan(holder)

        return [] if prepared.empty? || !alchemist?(holder)

        made = prepared.map do |name, many|
          found = Crafting.entry('consumables', name)

          next nil if found.err?

          Equipment.grant!(holder, 'consumables', found.state.first, many.to_i, found.state.last,
                           :granted_by => 'advanced alchemy', :expires => 'rest')

          "#{many} #{found.state.first}"
        end.compact

        spend!(holder, (prepared.values.sum(&:to_i).to_f / per_batch).ceil)

        [ Turns.event('pf2e.alchemy_prepared', 'name' => holder.name, 'items' => made.join(', ')) ]
      end

      # Quick Alchemy, in an encounter: a batch for one item, to hand until their next turn.
      def self.quick!(holder, name)
        return Err.new(:not_alchemist, 'pf2e.alchemy_not_alchemist') unless alchemist?(holder)

        found = Crafting.entry('consumables', name)

        return found if found.err?

        named, info = found.state

        return Err.new(:not_alchemical, 'pf2e.alchemy_not_alchemical', 'item' => named) unless alchemical?(info)
        return Err.new(:too_high, 'pf2e.alchemy_too_high', 'item' => named, 'level' => info['level']) if info['level'].to_i > holder.pf2_level.to_i
        return Err.new(:no_formula, 'pf2e.alchemy_no_formula', 'item' => named) unless Crafting.known?(holder, 'consumables', named)
        return Err.new(:no_reagents_left, 'pf2e.alchemy_none_left') unless left(holder).positive?

        Equipment.grant!(holder, 'consumables', named, 1, info, :granted_by => 'quick alchemy', :expires => 'turn')
        spend!(holder, 1)

        Ok.new(:state => named)
      end
    end
  end
end
