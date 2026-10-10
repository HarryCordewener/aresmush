module AresMUSH
  module Pf2e

    # A reaction that raises AC against the attack that triggered it - Nimble Dodge's +2. Its feat
    # declares a toggle and an AC bonus predicated on it, which is how the reaction is known.
    #
    # The attack has been rolled and dealt when the player answers it, so a hit on a character is kept on
    # them until the next: the roll, the AC it was against, what they had before it, and - for a critical
    # hit - the damage a plain hit would have dealt, rolled with it. Answering puts the AC bonus against
    # the roll; a hit it turns into a miss is undone, and a critical it turns into a hit is dealt again as
    # a hit.
    module AttackAnswers

      # The AC bonus a reaction of theirs gives when they use it, by the toggle its rules declare: the
      # option, and how much it adds. Nil where the reaction gives none.
      def self.answer(holder, name)
        source = Effects.sources(holder).find { |one| Domains.slug(one['name']) == Domains.slug(name) }

        return nil unless source

        Rules.of_kind(source, 'RollOption').each do |row|
          option = row['option'].to_s

          next unless row['toggleable'] && !option.empty?

          bonus = Resolve.defence(holder, 'ac', :options => [ option ])['dc'] - Resolve.defence(holder, 'ac')['dc']

          return { 'option' => option, 'bonus' => bonus } if bonus.positive?
        end

        nil
      end

      # Whoever is hit keeps the hit: `before` is what it can put back, `calm` what a hit without the
      # critical would have dealt.
      def self.remember(holder, result, calm)
        hp = Pf2eHP.get_hp_obj(holder)

        return TurnState.write(holder, 'attacked' => nil) unless hp

        TurnState.write(holder, 'attacked' => { 'total' => result['total'].to_i, 'die' => result['die'],
                                                'dc' => result['dc'].to_i, 'degree' => result['degree'],
                                                'calm' => calm,
                                                'before' => { 'damage' => hp.damage.to_i, 'temp_hp' => hp.temp_hp.to_i,
                                                              'conditions' => holder.pf2_conditions || {},
                                                              'persistent' => Array(holder.pf2_persistent) } })
      end

      # The reactions they could answer this hit with, and turn it: ready, and enough to change the degree.
      def self.offered(holder)
        hit = TurnState.of(holder)['attacked']

        return [] unless hit && !TurnState.turn(holder)['reaction'] && hit['after'] == standing(holder)

        reactions(holder).select do |name|
          answer = answer(holder, name)

          answer && Degree.of(hit['total'], hit['dc'] + answer['bonus'], hit['die']) < hit['degree']
        end
      end

      # The reactions a character has that answer an attack this way.
      def self.reactions(holder)
        Actions.catalogue.select { |name, entry| entry['type'] == 'reaction' && Actions.owned?(holder, name) }
               .keys.select { |name| answer(holder, name) }
      end

      # What their hit points stand at, which an answer checks has not moved since the hit.
      def self.standing(holder)
        Actors.of(holder).standing
      end

      # The hit as it left them, once it is dealt.
      def self.dealt(holder)
        hit = TurnState.of(holder)['attacked']

        TurnState.write(holder, 'attacked' => hit.merge('after' => standing(holder))) if hit
      end

      def self.use(scene, name, out)
        holder = scene.actor.holder
        hit = TurnState.of(holder)['attacked']
        answer = answer(holder, name)

        return Err.new(:nothing_to_answer, 'pf2e.answer_no_attack', 'action' => name) unless hit && answer
        return Err.new(:too_late, 'pf2e.answer_too_late', 'action' => name) unless hit['after'] == standing(holder)

        dc = hit['dc'] + answer['bonus']
        degree = Degree.of(hit['total'], dc, hit['die'])
        out['lines'] << Telling.event('pf2e.answer_against', :actor => scene.actor.label, :action => name,
                                                            :total => hit['total'], :ac => dc,
                                                            :degree => Telling.degree(degree, true))

        TurnState.write(holder, 'attacked' => nil)

        return Ok.new(:state => out) unless degree < hit['degree']

        put_back(holder, hit['before'])
        TurnState.write(holder, 'struck' => nil)

        if Degree.success?(degree)
          Acting.deal(scene, scene.actor, Array(hit['calm']), out)
        else
          out['lines'] << Telling.event('pf2e.answer_undone', :target => scene.actor.label)
        end

        out['gm'] << Telling.event('pf2e.act_hp_left', :target => scene.actor.label, :hp => Harm.hit_points(holder))

        Ok.new(:state => out)
      end

      def self.put_back(holder, before)
        Pf2eHP.get_hp_obj(holder).update(:damage => before['damage'], :temp_hp => before['temp_hp'])
        holder.update(:pf2_conditions => before['conditions'], :pf2_persistent => before['persistent'])
      end
    end
  end
end
