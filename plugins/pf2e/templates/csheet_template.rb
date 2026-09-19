module AresMUSH
  module Pf2e

    class PF2CombatSheetTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        @armor = Pf2eCombat.get_equipped_armor(@char)
        @shield = Pf2eCombat.get_equipped_shield(@char)

        super File.dirname(__FILE__) + "/csheet_template.erb"
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def combat_stats
        @char.combat
      end

      def name
        @char.name
      end

      def speed
        AresMUSH::Pf2e::Stat.total(@char, 'speed')
      end

      def movement
        movelist = @char.pf2_movement

        if movelist.size > 2
          return "This character has other forms of movement. Check %x172sheet%xn for details."
        end

        return false
      end

      def hp
        Pf2eHP.display_character_hp(@char)
      end

      def temp_hp
        hp = @char.hp

        return "---" if !hp

        temp_hp = hp.temp_hp

        "#{temp_hp}"
      end

      def class_dc
        return "--" if !combat_stats
        dc = Pf2eCombat.get_class_dc(@char)
        prof = combat_stats.class_dc[0].upcase
        "#{dc} (#{prof})"
      end

      def archetype_class_dcs
        return "--" if !combat_stats

        dcs = Pf2eCombat.get_archetype_class_dcs(@char)
        return "--" if dcs.empty?

        dcs.keys.sort.map do |archetype|
          info = dcs[archetype]
          name = archetype.sub(/ Archetype$/, '')
          prof = info['prof'].to_s[0]&.upcase
          key_abil = info['key_abil'].to_s
          key_abil_short = key_abil.empty? ? "---" : key_abil[0..2].upcase

          "%xh#{name}%xn: #{info['dc']} (#{prof}, #{key_abil_short})"
        end.join(", ")
      end

      def has_archetypes?
        archetype_info = @char.pf2_archetypeinfo || {}
        archetypes = [
          archetype_info['archetype1'],
          archetype_info['archetype2'],
          archetype_info['archetype3'],
          archetype_info['archetype4']
        ].compact.map { |a| a.to_s.strip }.reject(&:empty?)

        !archetypes.empty?
      end

      def perception
        return "--" if !combat_stats
        bonus = Pf2eCombat.get_perception(@char)
        prof = combat_stats.perception[0].upcase
        "#{bonus} (#{prof})"
      end

      def saves
        saves = %w{fortitude reflex will}
        list = []
        saves.each do |s|
          list << format_save(@char, s)
        end

        list
      end

      def ac
        Pf2eCombat.calculate_ac(@char)
      end

      def ac_with_shield
        return ac if !(@shield)

        shield_bonus = @shield.ac_bonus

        ac + shield_bonus
      end

      def unarmed_attacks
        list = []

        attack_list = combat_stats.unarmed_attacks

        attack_list.each do |atk, info|
          list << format_unarmed(@char, atk, info, Pf2eCombat.get_unarmed_prof(@char, atk, info))
        end

        # Attacks a feat or an item granted. Shown alongside the ones the character has by nature,
        # because to a player they are the same thing: something else to hit with.
        Pf2eCombat.granted_strikes(@char).each { |strike| list << format_strike(@char, strike) }

        list
      end

      def format_strike(char, strike)
        damage = Pf2eCombat.damage_breakdown(char, strike['name'], nil, false, [], strike)
        traits = Array(strike['traits']).map { |t| titleize_trait(t) }.join(", ")
        bonus = Pf2e::Stat.total(char, 'attack', strike)

        "#{item_color}#{strike['name']}:%xn #{bonus} (#{strike['prof'][0].upcase}) " \
          "#{damage['formula']}\n#{item_color}From:%xn #{strike['source']}" \
          "#{traits.empty? ? '' : "\n#{item_color}Traits:%xn #{traits}"}%r"
      end

      def weapons
        weapon_list = Pf2egear::Inventory.held(@char, 'weapons')

        list = []

        weapon_list.each_with_index do |w,i|
          next if !w.equipped

          list << format_weapon(char, w, i)
        end

        list
      end

      def crit_spec
        access = Pf2e.crit_spec_access(@char)

        return [] if access.empty?

        access.keys.sort.filter_map do |group|
          effect = Pf2e.crit_spec_effect(group)
          next if effect.blank?

          names = access[group].join(", ")

          wrap_hanging("#{item_color}#{group}%xn - #{names}: #{effect}", 78, 3)
        end
      end

      def crit_spec_sources
        sources = Pf2e.crit_spec_sources(@char)

        return "" if sources.empty?

        " Via #{sources.sort.join(', ')}."
      end

      def wrap_hanging(text, width, indent)
        return "" if text.blank?

        words = text.split(/\s+/)
        lines = []
        current = ""

        words.each do |word|
          candidate = current.empty? ? word : "#{current} #{word}"
          limit = lines.empty? ? width : width - indent

          if visible_length(candidate) <= limit
            current = candidate
          else
            lines << current unless current.empty?
            current = word
          end
        end

        lines << current unless current.empty?

        first = lines.shift
        pad = "%b" * indent

        ([ first ] + lines.map { |l| pad + l }).join("%r")
      end

      def visible_length(text)
        formatted = MushFormatter.format(text)
        AnsiFormatter.strip_ansi(formatted).length
      end

      # What the character is under and how long it has left. Its numbers are already in the figures
      # above; this is where a player sees why.
      def effects
        ActiveEffects.on(@char).sort_by(&:name).map do |effect|
          "#{item_color}#{effect.name}%xn: #{ActiveEffects.remaining(effect)}"
        end
      end

      # Including the ones another brought with it, and saying which: a grabbed character is off-guard,
      # and the sheet should say why.
      def conditions
        labels = Pf2e.condition_labels(@char)

        labels.empty? ? "None active." : labels.join(", ")
      end

      def format_weapon(char,w,i)
        name = w.nickname ? "#{w.nickname} (#{w.name})" : w.name
        strike = Pf2eCombat.attack_descriptor(char, w)
        bonus = Pf2eCombat.get_wpattack_bonus(char, w)
        prof = Pf2eCombat.get_weapon_prof(char, w.name)[0].upcase
        breakdown = Pf2eCombat.damage_breakdown(char, w.name, w)
        traits = w.traits.map { |t| titleize_trait(t) }.join(", ")

        "%b%b#{left(i, 3)}%b#{left(name, 40)}%b#{left("#{bonus} (#{prof})",10)}%b#{left(breakdown['formula'], 22)}" \
          "\n%b%b#{item_color}Critical:%xn #{breakdown['critical']}#{reach(strike)}" \
          "\n%b%b#{item_color}Traits:%xn #{traits}#{etched(strike)}"
      end

      # How far the attack throws, which a feat can extend: Far Shot doubles a range increment and
      # Strong Arm adds ten feet to a thrown weapon's.
      def reach(strike)
        return '' unless strike['range'].to_i.positive?

        "  #{item_color}Range:%xn #{strike['range']} ft."
      end

      # Property runes the attack has the effects of, which is not the same list as the ones etched on
      # it: Ghost Hunter's magical weapon counts as having *ghost touch* against something incorporeal.
      def etched(strike)
        runes = Array(strike['runes'])

        return '' if runes.empty?

        "\n%b%b#{item_color}Runes:%xn #{runes.map { |one| titleize_trait(one) }.join(', ')}"
      end

      def format_save(char,name)
        save = "#{item_color}#{name.capitalize}%xn"
        prof = Pf2eCombat.get_save_from_char(char, name)[0].upcase
        bonus = Pf2eCombat.get_save_bonus(char, name)
        "#{left("#{save}: #{bonus} (#{prof})", 26)}"
      end

      def format_unarmed(char, atk_name, atk_info, unarmed_prof)
        damage = atk_info['damage'] + "%b" + atk_info['damage_type']

        traits = atk_info['traits']

        bonus = Pf2eCombat.get_unarmed_bonus(char, atk_name, atk_info, unarmed_prof)
        p_str = unarmed_prof[0].upcase

        traits = traits.map { |t| titleize_trait(t) }.join(", ")

        "#{item_color}#{atk_name}:%xn #{bonus} (#{p_str}) #{damage}\n#{item_color}Traits:%xn #{traits}%r"
      end


      def titleize_trait(trait)
        trait.to_s.split("_").map { |word| word.sub(/\A[a-z]/) { |c| c.upcase } }.join(" ")
      end

    end
  end
end
