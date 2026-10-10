module AresMUSH
  module Pf2e

    # What the abilities many creatures share actually do. A stat block gives each as a line of its own
    # figures - `(1d8) bludgeoning, DC 17 basic Fortitude`, `Medium, (1d6+2) bludgeoning, Rupture 9` - and
    # the same words of rules beneath it every time; a row here is those rules, run with those figures.
    #
    #   several   it is aimed at as many as the GM names
    #   refusal   what it needs before it can be used at all, answered as an error where that is missing
    #   run       what it does, into the report
    #
    # An ability with no row is announced with its words, for the GM to run.
    module MonsterAbilities

      SAVES = 'Fortitude|Reflex|Will'.freeze
      SIZES = %w{tiny small medium large huge gargantuan}.freeze

      # The figures on an ability's first line.
      #
      #   { 'damage' => [ [ '1d8+1', 'bludgeoning' ], [ '1d6', 'acid' ] ], 'dc' => 17, 'save' => 'fortitude',
      #     'basic' => true, 'rupture' => 5, 'size' => 'medium', 'escape_dc' => 22, 'words' => [ 'hoof' ] }
      def self.header(text)
        line = text.to_s.split('%r').first.to_s
        out = { 'damage' => [], 'words' => [] }

        line.split(/,\s*/).each do |part|
          part = part.strip

          if (found = part.match(/\ADC (\d+)\s*(basic)?\s*(#{SAVES})/i))
            out.merge!('dc' => found[1].to_i, 'basic' => !found[2].nil?, 'save' => found[3].downcase)
          elsif (found = part.match(/\A\(?(#{CreatureAbilities::FORMULA})\)?\s+([a-z]+)(?:\s+damage)?\b/i))
            out['damage'] << [ found[1].delete(' '), found[2].downcase ]
          elsif (found = part.match(/\ARupture (\d+)/i)) then out['rupture'] = found[1].to_i
          elsif (found = part.match(/\Aescape dc\s*=?\s*(\d+)/i)) then out['escape_dc'] = found[1].to_i
          elsif (found = part.match(/\A(#{SIZES.join('|')})\b/i)) then out['size'] = found[1].downcase
          else out['words'] << part
          end
        end

        out
      end

      def self.formulas(header)
        header['damage'].map { |formula, type| [ formula, type, nil, [ 'damage' ] ] }
      end

      # ------------------------------------------------------------------------------
      # The abilities

      # Constrict: the listed damage to any number of creatures it has grabbed or restrained, each with a
      # basic save against the listed DC.
      CONSTRICT = {
        'several' => true,
        'refusal' => lambda { |use| use.held.empty? ? Err.new(:hold_none, 'pf2e.hold_none', 'actor' => use.actor.label, 'action' => use.name) : nil },
        'run' => lambda do |use|
          use.held.each { |target| use.save(target, use.header) }
        end
      }.freeze

      ROWS = {
        'constrict' => CONSTRICT,
        'greater-constrict' => CONSTRICT
      }.freeze

      def self.row(name)
        ROWS[Domains.slug(name).sub(/-\d+-feet\z/, '')]
      end

      # One use of an ability: who uses it, on whom, and the stat block's entry for it.
      Use = Struct.new(:scene, :name, :own, :targets, :out) do
        def actor
          scene.actor
        end

        def header
          @header ||= MonsterAbilities.header(own['text'])
        end

        # Those it holds among those named, or everyone it holds where nobody is named.
        def held
          holding = Holding.held_by(scene.encounter, actor.label)

          targets.empty? ? holding : holding.select { |one| targets.any? { |named| named.label == one.label } }
        end

        def at(target)
          Acting::Scene.new(scene.encounter, actor, target, scene.enactor, scene.permitted)
        end

        # A target's save against the listed DC, with the listed damage where there is any. Answers the
        # degree.
        def save(target, figures)
          mechanics = { 'save' => figures['save'], 'basic' => figures['basic'], 'traits' => Array(own['traits']) }

          Acting.spell_save(at(target), name, mechanics, figures['dc'], MonsterAbilities.formulas(figures), out)
        end
      end

      # Uses a creature's ability that has a row: refused where its needs are not met, and otherwise
      # announced, run and paid for.
      def self.use(scene, name, own, targets)
        use = Use.new(scene, name, own, Array(targets), Acting.report)
        refused = row(name)['refusal']&.call(use)

        return refused if refused

        use.out['about'] = DamageAbout.of_ability(own)
        Acting.announce(scene, name, own, use.targets, use.out)
        row(name)['run'].call(use)
        Acting.paid(scene, name, own)

        Ok.new(:state => use.out)
      end
    end
  end
end
