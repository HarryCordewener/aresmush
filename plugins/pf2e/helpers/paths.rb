module AresMUSH
  module Pf2e

    # Values an effect may write, and how.
    #
    # `ActiveEffectLike` is the rule element that writes to a path on the character rather than adding a
    # modifier to a figure. A hundred and fifty-nine of them sit on the feats and items we stock, and
    # they are how a feat makes you trained in a skill, how carrying capacity grows, and how the counters
    # that other rules' predicates read get their values.
    #
    # Two things make this a registry rather than a setter. A path is Foundry's - `system.skills.nature.rank`
    # - and has to be translated to wherever the value lives here. And a path we cannot write is refused
    # rather than guessed at: an effect that silently writes nothing is a sheet that is quietly wrong, and
    # one that writes to the wrong place is worse.
    module Paths

      # `ae-like.ts:152`. A mode says how the new value meets the old one. `remove` is `subtract` under
      # another name for a number, which is how their data uses it.
      MODES = {
        'override' => ->(_current, change) { change },
        'add' => ->(current, change) { number(current) + number(change) },
        'subtract' => ->(current, change) { number(current) - number(change) },
        'remove' => ->(current, change) { number(current) - number(change) },
        'multiply' => ->(current, change) { (number(current) * number(change)).truncate },
        'upgrade' => ->(current, change) { [ number(current), number(change) ].max },
        'downgrade' => ->(current, change) { [ number(current), number(change) ].min }
      }.freeze

      # A path an effect may write, as a row: how to read the value now, and how to write it back.
      #
      # `match` is a pattern rather than a literal where the path names a thing - a skill, a class - and
      # the captured name is handed to the reader and the writer.
      KINDS = [
        # A feat that makes you trained, or better, in a skill. Written as a rank rather than a bonus,
        # which is why the mode is `upgrade`: two feats that both train you do not make you an expert.
        {
          'name' => 'skill rank',
          'match' => %r{\Asystem\.skills\.([\w-]+)\.rank\z},
          'read' => ->(char, skill) { Paths.rank_number(Pf2eSkills.get_skill_prof(char, Paths.skill_named(skill))) },
          'write' => ->(char, skill, value) {
            Pf2eSkills.update_skill_for_char(Paths.skill_named(skill), char, Paths.rank_name(value))
          }
        },
        # The DC to recover from dying, which a feat can lower.
        {
          'name' => 'dying recovery DC',
          'match' => %r{\Asystem\.attributes\.dying\.recoveryDC\z},
          'read' => ->(char, _name) { Paths.held(char, 'dying_recovery_dc') },
          'write' => ->(char, _name, value) { Paths.store(char, 'dying_recovery_dc', value) }
        },
        # How much of a night's rest a character gets, which Fast Recovery doubles. Foundry's default is
        # one and their rules add to it, so `Pf2e::DailyHelpers` reads it as one more than what is here.
        {
          'name' => 'recovery multiplier',
          'match' => %r{\Asystem\.attributes\.hp\.recoveryMultiplier\z},
          'read' => ->(char, _name) { Paths.held(char, 'recovery_multiplier') },
          'write' => ->(char, _name, value) { Paths.store(char, 'recovery_multiplier', value) }
        },
        # How much a character can carry before it tells, which Hefty Hauler and its like raise.
        {
          'name' => 'carrying capacity',
          'match' => %r{\Ainventory\.bulk\.(maxAddend|encumberedAfterAddend)\z},
          'read' => ->(char, which) { Paths.held(char, Domains.slug(which)) },
          'write' => ->(char, which, value) { Paths.store(char, Domains.slug(which), value) }
        },
        # Armour proficiency, which is what AC reads. Written with `upgrade`, so two effects that both
        # make you trained in heavy armour do not make you an expert.
        {
          'name' => 'armour proficiency',
          'match' => %r{\Asystem\.proficiencies\.defenses\.([\w-]+)\.rank\z},
          'read' => ->(char, category) { Paths.rank_number((char.combat&.armor_prof || {})[category]) },
          'write' => ->(char, category, value) { Paths.write_armour(char, category, value) }
        },
        # Proficiency with a named kind of attack, which the attack reader consults by the same key.
        {
          'name' => 'attack proficiency',
          'match' => %r{\Asystem\.proficiencies\.attacks\.([\w-]+)\.rank\z},
          'read' => ->(char, key) { Paths.rank_number((char.combat&.weapon_prof || {})[key]) },
          'write' => ->(char, key, value) { Paths.write_weapon_prof(char, key, value) }
        },
        # Facts about the character that no figure reads but a predicate does: whether they can flank
        # alone, how many familiar abilities they have.
        #
        # Named one by one rather than matched by prefix. `system.attributes` is also where hit points and
        # AC live, and those are assembled from the ledger and from effects - an effect writing one
        # directly would be overwritten by the next fold, so the registry must not offer it.
        {
          'name' => 'fact',
          'match' => %r{\Asystem\.attributes\.(flanking\.canFlank|flanking\.canGangUp|flanking\.flankable
                        |familiarAbilities\.value)\z}x,
          'read' => ->(char, name) { Paths.held(char, Domains.slug(name)) },
          'write' => ->(char, name, value) { Paths.store(char, Domains.slug(name), value) }
        },
        # Counters and flags that exist so another rule can ask about them: how many dedications of a
        # class you have, how many forms you know, how many temporary hit points a rage gives. A formula
        # reads them back as `@actor.flags.system.<name>` - Rage's temporary hit points are exactly that
        # - so they are kept under the path's own spelling, which is how `Effects.build_context` finds
        # them.
        {
          'name' => 'counter',
          'match' => %r{\Aflags\.system\.([\w.]+)\z},
          # Read as it stands rather than as a number: `override` writes lists and words here as readily
          # as counts, and coercing on the way out would raise on the next read.
          'read' => ->(char, name) { Paths.held(char, Paths.flag(name)) },
          'write' => ->(char, name, value) { Paths.store(char, Paths.flag(name), value) }
        }
      ].freeze

      RANKS = %w{untrained trained expert master legendary}.freeze

      # A flag counts as one or nothing, and a number keeps whatever kind it is: a multiply by a half is
      # meant to halve, so truncating the factor before multiplying would lose the point of it.
      def self.number(value)
        return 1 if value == true
        return 0 if value == false || value.nil?
        return value if value.is_a?(Numeric)
        return 0 unless value.is_a?(String)

        value.include?('.') ? value.to_f : value.to_i
      end

      def self.rank_number(rank)
        RANKS.index(rank.to_s) || 0
      end

      def self.rank_name(value)
        RANKS[value.to_i.clamp(0, RANKS.size - 1)]
      end

      # Foundry slugs a skill; our catalogue capitalises it.
      def self.skill_named(slug)
        (Global.read_config('pf2e_skills') || {}).keys
          .find { |name| Domains.slug(name) == Domains.slug(slug) } || slug.to_s.capitalize
      end

      def self.write_weapon_prof(char, key, value)
        combat = char.combat

        return unless combat

        combat.update(:weapon_prof => (combat.weapon_prof || {}).merge(key => rank_name(value)))
      end

      def self.write_armour(char, category, value)
        combat = char.combat

        return unless combat

        combat.update(:armor_prof => (combat.armor_prof || {}).merge(category => rank_name(value)))
      end

      # Where a value nothing else owns is kept. One hash, because these are derived facts rather than
      # choices: they are rewritten whenever the effects that set them change, and a reader that wants
      # one asks for it by the name the rule wrote.
      def self.store(char, name, value)
        held = (char.pf2_derived || {}).merge(name.to_s => value)

        char.update(:pf2_derived => held)
      end

      FLAG = 'flags.system.'.freeze

      def self.flag(name)
        "#{FLAG}#{name}"
      end

      # Every counter, by its own name, as a formula reads them.
      def self.flags(char)
        (char.pf2_derived || {}).each_with_object({}) do |(key, value), out|
          out[key.delete_prefix(FLAG)] = value if key.start_with?(FLAG)
        end
      end

      def self.held(char, name)
        (char.pf2_derived || {})[name.to_s]
      end

      # The row that can write this path, and the name it captured, or nothing.
      def self.for(path)
        KINDS.each do |row|
          found = row['match'].match(path.to_s)

          return [ row, found.captures.first ] if found
        end

        nil
      end

      def self.writable?(path)
        !self.for(path).nil?
      end

      # What the path would become. Separate from writing it, so a caller can say what an effect does
      # without doing it.
      def self.would_be(char, path, mode, change)
        row, name = self.for(path)

        return nil unless row && MODES.key?(mode.to_s)

        MODES[mode.to_s].call(row['read'].call(char, name), change)
      end

      # Everything the character's feats, items and conditions write, applied in the order the modes run.
      #
      # Called from the materialiser rather than when a feat is gained, because these are derived: a feat
      # that makes you trained in Nature has to say so again after every fold, or the fold would take the
      # rank away. Nothing here is written to the ledger for the same reason - the ledger records what a
      # player chose, and this is what their choices imply.
      #
      # The store is emptied first. An `add` reads what is there and adds to it, so applying the same
      # feats twice without clearing would count Hefty Hauler's two bulk twice - which is the difference
      # between rebuilding derived data and mutating it. A skill rank is not cleared, because a rank is
      # written with `upgrade` and taking the better of a rank and itself is the rank.
      # A creature in an encounter has no sheet to write to: its figures are its stat block's.
      def self.apply_all!(char)
        return 0 if Pf2e.npc?(char)

        char.update(:pf2_derived => {})

        writes = Rules.writes(Effects.sources(char), Effects.options(char), Effects.context(char))

        writes.each { |write| apply!(char, write['path'], write['mode'], write['value']) }

        writes.size
      end

      def self.apply!(char, path, mode, change)
        row, name = self.for(path)

        return false unless row && MODES.key?(mode.to_s)

        row['write'].call(char, name, MODES[mode.to_s].call(row['read'].call(char, name), change))

        true
      end
    end
  end
end
