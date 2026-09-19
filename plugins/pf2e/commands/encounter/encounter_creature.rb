module AresMUSH
  module Pf2e

    # A creature's stat block as text, the way a GM reads one at the table.
    module StatBlock

      def self.lines(name, block, npc: nil, gm: true)
        lines = [ "%xh#{name}%xn  Creature #{block['level']}  #{traits(block)}" ]

        if npc
          conditions = Pf2e.condition_labels(npc, false)
          lines << "#{t('pf2e.creature_hp')}: #{gm ? Harm.hit_points(npc) : t('pf2e.creature_hp_hidden')}" \
                   "#{conditions.empty? ? '' : "  #{t('pf2e.creature_conditions')}: #{conditions.join(', ')}"}"
          effects = ActiveEffects.on(npc).map(&:name)
          lines << "#{t('pf2e.creature_effects')}: #{effects.join(', ')}" if effects.any?
        end

        return lines unless gm

        lines << "Perception #{signed(block['perception'])}#{senses(block)}"
        lines << "Skills #{(block['skills'] || {}).map { |skill, value| "#{skill} #{signed(value)}" }.join(', ')}" if block['skills']
        lines << "AC #{block['ac']}; Fort #{signed(saves(block, 'fortitude'))}, Ref #{signed(saves(block, 'reflex'))}, " \
                 "Will #{signed(saves(block, 'will'))}"
        lines << "HP #{block['hp']}#{block['hp_details'] ? " (#{block['hp_details']})" : ''}#{iwr(block)}"
        lines << "Speed #{(block['speeds'] || {}).map { |kind, feet| kind == 'land' ? "#{feet} feet" : "#{kind} #{feet} feet" }.join(', ')}"

        Array(block['strikes']).each do |strike|
          damage = Array(strike['damage']).map { |formula, type, category| [ formula, category, type ].compact.join(' ') }
          lines << "#{strike['range'].to_i.positive? ? 'Ranged' : 'Melee'} #{strike['name']} #{signed(strike['bonus'])} " \
                   "(#{Array(strike['traits']).join(', ')}), #{damage.join(' plus ')}" \
                   "#{Array(strike['effects']).any? ? " plus #{strike['effects'].join(', ')}" : ''}"
        end

        Array(block['spellcasting']).each do |casting|
          spells = (casting['spells'] || {}).map { |rank, names| "#{rank == '0' ? 'Cantrips' : "Rank #{rank}"}: #{names.join(', ')}" }
          lines << "#{casting['name']} DC #{casting['dc']}, attack #{signed(casting['attack'])}; #{spells.join('; ')}"
        end

        Array(block['actions']).each do |ability|
          cost = ability['type'] == 'action' ? "[#{ability['cost'] || 1}]" : "[#{ability['type']}]"
          lines << "%xh#{ability['name']}%xn #{cost} #{ability['text']}"
        end

        lines
      end

      def self.signed(value)
        value.to_i.negative? ? value.to_s : "+#{value.to_i}"
      end

      def self.saves(block, name)
        (block['saves'] || {})[name]
      end

      def self.traits(block)
        ([ block['rarity'] == 'common' ? nil : block['rarity'], block['size'] ] + Array(block['traits'])).compact
                                                                                         .map(&:capitalize).join(', ')
      end

      def self.senses(block)
        Array(block['senses']).empty? ? '' : "; #{block['senses'].join(', ')}"
      end

      def self.iwr(block)
        parts = []
        parts << "Immunities #{block['immunities'].join(', ')}" if block['immunities']
        parts << "Weaknesses #{block['weaknesses'].map { |type, value| "#{type} #{value}" }.join(', ')}" if block['weaknesses']
        parts << "Resistances #{block['resistances'].map { |type, value| "#{type} #{value}" }.join(', ')}" if block['resistances']

        parts.empty? ? '' : "; #{parts.join('; ')}"
      end
    end

    # `+e/creature <#id|name|creature>` - a combatant's stat block and state, or a creature from the
    # bestiary. Players see a combatant's name and conditions; the GM sees the whole block.
    class PF2EncounterCreatureCmd
      include CommandHandler

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        gm = encounter ? Combatants.gm?(enactor, encounter) : true

        if encounter
          found = Combatants.find(encounter, self.term)

          if found.ok? && found.state.npc?
            npc = found.state.holder
            return client.emit(StatBlock.lines(npc.name, npc.stat_block, :npc => npc, :gm => gm).join('%r'))
          end
        end

        found = Bestiary.find(self.term)

        return if CharState.emit_error!(client, found)

        client.emit StatBlock.lines(found.state, Bestiary.entry(found.state)).join('%r')
      end
    end

    # `+e/bestiary <words>[/<level>]` - creatures whose names hold the words.
    class PF2EncounterBestiaryCmd
      include CommandHandler

      attr_accessor :words, :level

      LIMIT = 40

      def parse_args
        words, _, level = cmd.args.to_s.partition('/')
        self.words = words.strip
        self.level = level.strip.match?(/\A-?\d+\z/) ? level.strip.to_i : nil
      end

      def required_args
        [ self.words ]
      end

      def handle
        found = Bestiary.search(self.words, self.level)

        return client.emit_failure(t('pf2e.creature_not_found', :creature => self.words)) if found.empty?

        lines = found.first(LIMIT).map { |name, one| "#{name.ljust(40)} Creature #{one['level']}" }
        lines << t('pf2e.bestiary_more', :count => found.size - LIMIT) if found.size > LIMIT

        client.emit lines.join('%r')
      end
    end

    # `+e/add [<count>] <creature>[=<name>]` adds creatures from the bestiary to the encounter, each with
    # its own id and initiative. `+e/add <name>=ac 16 fort 5 ref 7 will 3 perception 2 hp 20` adds one
    # described by its numbers.
    class PF2EncounterAddCmd
      include CommandHandler

      attr_accessor :count, :creature, :name

      def parse_args
        left, _, right = cmd.args.to_s.partition('=')
        found = left.strip.match(/\A(\d+)\s+(.+)\z/)

        self.count = found ? found[1].to_i.clamp(1, 20) : 1
        self.creature = found ? found[2].strip : left.strip
        self.name = right.strip
      end

      def required_args
        [ self.creature ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        cannot = Pf2e.can_modify_encounter(enactor, encounter)

        return client.emit_failure(cannot) if cannot

        described = Combatants.described(self.creature, self.name)
        added = if described
                  [ Combatants.add_npc(encounter, :described => described) ]
                else
                  found = Bestiary.find(self.creature)
                  return if CharState.emit_error!(client, found)

                  self.count.times.map do |index|
                    named = self.name.empty? ? nil : (self.count > 1 ? "#{self.name} #{index + 1}" : self.name)
                    Combatants.add_npc(encounter, :creature => found.state, :name => named)
                  end
                end

        added.each do |one|
          npc = one.state['npc']
          named = npc.name.end_with?("##{npc.number}") ? npc.name : "#{npc.name} (##{npc.number})"
          message = t('pf2e.encounter_add_ok', :roll => one.state['initiative'], :encounter => encounter.id,
                                               :name => named)
          enactor_room.emit message
          PF2Encounter.send_to_encounter(encounter, message)
        end
      end
    end
  end
end
