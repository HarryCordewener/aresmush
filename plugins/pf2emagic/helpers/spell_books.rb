module AresMUSH
  module Pf2emagic

    # A book of spells a feat keeps beside a repertoire, and the pick made from it each day.
    #
    # Esoteric Polymath and Arcane Evolution both keep one: a spontaneous caster's list of spells
    # beyond the repertoire, from which one is chosen at each daily preparation. A spell already in
    # the repertoire becomes a signature spell that day; one that is not joins the repertoire until
    # the next preparations. The feat's `spell_book` block says what the book holds and which
    # `prepare/<switch>` prepares from it, so no code names either feat.
    module SpellBooks

      # The books the named feats keep. `feat_names` in any case; `feats` is the feat config.
      def self.books_from(feat_names, feats)
        wanted = Array(feat_names).map { |name| name.to_s.upcase }

        (feats || {}).filter_map do |name, details|
          book = details.is_a?(Hash) && details['spell_book']

          next unless book.is_a?(Hash) && wanted.include?(name.to_s.upcase)

          book.merge('feat' => name)
        end
      end

      # The books this character keeps, counting a feat the level-up in progress takes.
      def self.held(char)
        books_from(Pf2e::DraftSheet.of(char).feat_names, Global.read_config('pf2e_feats'))
      end

      def self.for_switch(books, switch)
        Array(books).find { |book| book['switch'].to_s.casecmp?(switch.to_s) }
      end

      # rank => [ spells ]: the spells learned into the book, and the repertoire it holds besides.
      def self.contents(stored, repertoire)
        ranks = ((stored || {}).keys + (repertoire || {}).keys).map(&:to_s).uniq

        ranks.each_with_object({}) do |rank, out|
          out[rank] = (Array((stored || {})[rank] || (stored || {})[rank.to_i]) +
                       Array((repertoire || {})[rank] || (repertoire || {})[rank.to_i])).uniq
        end
      end

      # The book's contents for a live character: what was learned into it, and the current
      # repertoire of the class it supplements.
      def self.contents_for(char, book)
        magic = char.magic

        contents((magic&.spellbook || {})[book['name']], (magic&.repertoire || {})[book['supplements']])
      end

      # Shown when the feat is gained, from the same block the commands read.
      def self.instructions(book)
        t('pf2emagic.spell_book_instructions', :feat => book['feat'], :book => book['name'],
          :switch => book['switch'], :tradition => book['tradition'])
      end
    end

    # Learn a Spell (Player Core p. 230). The decisions, apart from the rolling and the writing.
    module LearnSpell

      # [ price in copper, DC ] for a spell rank, from the Learning a Spell table.
      def self.terms(rank, table)
        key = (table || {}).keys.find { |k| k.to_s == rank.to_s }
        price, dc = key ? table[key] : [ nil, nil ]

        return nil unless price

        { 'price' => Pf2egear.convert_money(price.to_i, 'gp'), 'dc' => dc.to_i }
      end

      OUTCOMES = {
        3 => { 'learned' => true, 'paid' => 'half' },
        2 => { 'learned' => true, 'paid' => 'full' },
        1 => { 'learned' => false, 'paid' => 'none' },
        0 => { 'learned' => false, 'paid' => 'half' }
      }.freeze

      # What a degree of success does. Magical Shorthand makes a success a critical success, and
      # Spellbook Prodigy a critical failure a failure.
      def self.outcome(degree, upgrade_success: false, soften_critical_failure: false)
        degree = 3 if upgrade_success && degree == 2
        degree = 1 if soften_critical_failure && degree.zero?

        OUTCOMES[degree]
      end

      def self.charge(price, paid)
        case paid
        when 'full' then price
        when 'half' then price / 2
        else 0
        end
      end

      # A failed spell can be tried again after the character gains a level, or after the days a
      # feat names (Magical Shorthand's week), whichever is first.
      def self.retry_blocked?(failure, level:, now:, retry_after_days: nil)
        return false unless failure.is_a?(Hash)
        return false if level.to_i > failure['level'].to_i
        return false if retry_after_days && now.to_i >= failure['at'].to_i + retry_after_days.to_i * 86400

        true
      end

      RARE = %w(uncommon rare unique).freeze

      # Whether the attempt may be made, in the order a player would want to hear it.
      GUARDS = [
        {
          'name' => 'on the tradition list',
          'check' => lambda { |ctx|
            traditions = Array(ctx['details']['tradition']).map { |t| t.to_s.downcase }

            next nil if traditions.include?(ctx['target']['tradition'].to_s.downcase)

            Pf2e::Err.new(:wrong_tradition, 'pf2emagic.learn_wrong_tradition',
                          'spell' => ctx['spell'], 'tradition' => ctx['target']['tradition'])
          }
        },
        # An uncommon spell needs access that only the GM can give, so staff add it.
        {
          'name' => 'common',
          'check' => lambda { |ctx|
            next nil unless Array(ctx['details']['traits']).any? { |trait| RARE.include?(trait.to_s.downcase) }

            Pf2e::Err.new(:not_common, 'pf2emagic.learn_not_common', 'spell' => ctx['spell'])
          }
        },
        {
          'name' => 'not known already',
          'check' => lambda { |ctx|
            known = (ctx['known'] || {}).values.flatten

            next nil unless known.any? { |spell| spell.to_s.casecmp?(ctx['spell'].to_s) }

            Pf2e::Err.new(:already_known, 'pf2emagic.learn_already_known', 'spell' => ctx['spell'], 'target' => ctx['target']['name'])
          }
        },
        {
          'name' => 'retry due',
          'check' => lambda { |ctx|
            ctx['blocked'] ? Pf2e::Err.new(:retry_blocked, 'pf2emagic.learn_retry_blocked', 'spell' => ctx['spell']) : nil
          }
        },
        # The materials are needed to make the attempt at all.
        {
          'name' => 'can pay',
          'check' => lambda { |ctx|
            next nil if ctx['money'].to_i >= ctx['price'].to_i

            Pf2e::Err.new(:cannot_afford, 'pf2emagic.learn_cannot_afford',
                          'spell' => ctx['spell'], 'price' => Pf2egear.display_money(ctx['price'].to_i))
          }
        }
      ].freeze

      def self.check(ctx)
        GUARDS.each do |guard|
          failure = guard['check'].call(ctx)

          return failure if failure
        end

        Pf2e::Ok.new(:state => ctx)
      end
    end

    # The spell picked from a book at daily preparations.
    module DailyPick

      #   spell, base    the spell asked for and its own rank
      #   rank           the rank asked for, or nil for the spell's own
      #   book           rank => [ spells ] in the book
      #   repertoire     rank => [ spells ] the class knows
      #   max_rank       the highest rank the class has slots for
      def self.plan(ctx)
        spell = ctx['spell'].to_s
        in_book = (ctx['book'] || {}).values.flatten.find { |name| name.to_s.casecmp?(spell) }

        return Pf2e::Err.new(:not_in_book, 'pf2emagic.pick_not_in_book', 'spell' => spell) unless in_book

        known_rank = (ctx['repertoire'] || {}).find { |_rank, spells| Array(spells).any? { |s| s.to_s.casecmp?(spell) } }

        return Pf2e::Ok.new(:state => { 'as' => 'signature', 'spell' => in_book, 'rank' => known_rank[0].to_s }) if known_rank

        base = ctx['base'].to_s
        cantrip = base.casecmp?('cantrip') || base.to_i.zero?
        rank = cantrip ? 'cantrip' : (ctx['rank'].presence || base).to_s

        unless cantrip
          return Pf2e::Err.new(:rank_too_low, 'pf2emagic.pick_rank_too_low', 'spell' => in_book, 'base' => base) if rank.to_i < base.to_i
          return Pf2e::Err.new(:rank_too_high, 'pf2emagic.pick_rank_too_high', 'rank' => rank) if rank.to_i > ctx['max_rank'].to_i
        end

        Pf2e::Ok.new(:state => { 'as' => 'repertoire', 'spell' => in_book, 'rank' => rank })
      end
    end

    # ------------------------------------------------------------------------------
    # On a live character
    # ------------------------------------------------------------------------------

    # Where a character can write a spell they learn: a book a feat keeps, or the spellbook of a
    # class that prepares from one. Each as { 'name', 'tradition', 'known' }.
    def self.learn_targets(char)
      magic = char.magic

      return [] unless magic

      books = SpellBooks.held(char).map do |book|
        { 'name' => book['name'], 'tradition' => book['tradition'], 'known' => SpellBooks.contents_for(char, book) }
      end

      books + Entries.casting(magic).filter_map do |entry|
        next unless entry['category'].to_s == 'prepared' && Entries.enumerated?(entry['name'])

        { 'name' => entry['name'], 'tradition' => entry['tradition'], 'known' => entry['known'] || {} }
      end
    end

    # The Learn a Spell rules the character's feats change: Magical Shorthand's and Spellbook
    # Prodigy's, each read from the feat's `learn_spell` block.
    def self.learn_spell_rules(char)
      blocks = Pf2e.held_feat_details(char).filter_map { |_name, details| details['learn_spell'] }.select { |b| b.is_a?(Hash) }

      {
        :upgrade_success => blocks.any? { |b| b['upgrade_success'] },
        :soften_critical_failure => blocks.any? { |b| b['soften_critical_failure'] },
        :retry_after_days => blocks.map { |b| b['retry_after_days'] }.compact.map(&:to_i).min
      }
    end

    # Learns a spell with `natural` as the d20. Pays, records the spell or the failure, and answers
    # with what happened. `target_name` names where it goes when there is more than one place.
    def self.learn_spell(char, target_name, spell_name, natural)
      return Pf2e::Err.new(:advancing, 'pf2emagic.learn_while_advancing') if Pf2e::Ledger.drafting?(char)

      targets = learn_targets(char)

      return Pf2e::Err.new(:no_target, 'pf2emagic.learn_no_target') if targets.empty?

      target = if target_name.present?
                 targets.find { |t| t['name'].to_s.casecmp?(target_name.to_s) }
               elsif targets.size == 1
                 targets.first
               end

      unless target
        return Pf2e::Err.new(:which_target, 'pf2emagic.learn_which_target',
                             'targets' => targets.map { |t| t['name'] }.join(', '))
      end

      found = get_spell_details(spell_name)

      return Pf2e::Err.new(:no_spell, 'pf2emagic.learn_no_spell', 'spell' => spell_name) if found.is_a?(String)

      spell, details = found
      rank = details['base_level'].to_i.zero? ? 'cantrip' : details['base_level'].to_i.to_s
      terms = LearnSpell.terms(rank, Global.read_config('pf2e_magic', 'learn_spell'))
      rules = learn_spell_rules(char)
      magic = char.magic
      failures = magic.learn_failures || {}
      failure = failures.find { |name, _| name.to_s.casecmp?(spell) }&.last

      checked = LearnSpell.check(
        'target' => target, 'spell' => spell, 'details' => details, 'known' => target['known'],
        'blocked' => LearnSpell.retry_blocked?(failure, :level => char.pf2_level, :now => Time.now.to_i,
                                               :retry_after_days => rules[:retry_after_days]),
        'money' => char.pf2_money, 'price' => terms['price']
      )

      return checked unless checked.ok?

      skill = Global.read_config('pf2e_magic', 'tradition_skills', target['tradition'].to_s.downcase)
      bonus = Pf2eSkills.get_skill_bonus(char, skill)
      total = natural.to_i + bonus
      degree = Pf2e.degree_index(natural.to_i, total, terms['dc'])
      outcome = LearnSpell.outcome(degree, :upgrade_success => rules[:upgrade_success],
                                           :soften_critical_failure => rules[:soften_critical_failure])
      cost = LearnSpell.charge(terms['price'], outcome['paid'])

      Pf2egear.pay_player(char, -cost, 'Learn a Spell', "Materials for #{spell}") if cost.positive?

      if outcome['learned']
        Pf2e::Ledger.write(char, :source_type => 'learned', :source_ref => "Learn a Spell: #{spell}") do |txn|
          txn.grant('spell_access', 'source' => target['name'], 'rank' => rank, 'spell' => spell)
        end

        failures = failures.reject { |name, _| name.to_s.casecmp?(spell) }
      else
        failures = failures.merge(spell => { 'level' => char.pf2_level, 'at' => Time.now.to_i })
      end

      char.magic.update(:learn_failures => failures)

      Pf2e::Ok.new(:state => {
        'spell' => spell, 'target' => target['name'], 'skill' => skill, 'natural' => natural.to_i,
        'bonus' => bonus, 'total' => total, 'dc' => terms['dc'], 'degree' => degree,
        'learned' => outcome['learned'], 'cost' => cost
      })
    end

    # Picks the day's spell from the book whose switch is named.
    def self.pick_from_book(char, switch, spell_name, rank)
      magic = char.magic
      book = SpellBooks.for_switch(SpellBooks.held(char), switch)

      return Pf2e::Err.new(:no_book, 'pf2emagic.pick_no_book', 'switch' => switch) unless book && magic

      charclass = book['supplements']

      if (magic.daily_pick || {})[charclass].present?
        return Pf2e::Err.new(:already_picked, 'pf2emagic.pick_already_made', 'spell' => magic.daily_pick[charclass]['spell'])
      end

      found = get_spell_details(spell_name)

      return Pf2e::Err.new(:no_spell, 'pf2emagic.learn_no_spell', 'spell' => spell_name) if found.is_a?(String)

      slots = Entries.slots(magic, charclass).keys.map(&:to_s).reject { |r| r.casecmp?('cantrip') }.map(&:to_i)

      planned = DailyPick.plan(
        'spell' => found[0], 'base' => found[1]['base_level'], 'rank' => rank,
        'book' => SpellBooks.contents_for(char, book), 'repertoire' => (magic.repertoire || {})[charclass] || {},
        'max_rank' => slots.max.to_i
      )

      return planned unless planned.ok?

      magic.update(:daily_pick => (magic.daily_pick || {}).merge(charclass => planned.state.merge('book' => book['name'])))

      planned
    end
  end
end
