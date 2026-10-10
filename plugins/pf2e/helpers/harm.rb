module AresMUSH
  module Pf2e

    # Damage and healing, for whoever takes it. Each actor keeps its own hit points - a character's are
    # `Pf2eHP`, which knows about dying, wounds and temporary hit points; a creature's are its stat
    # block's maximum less what it has taken - and works out what it resists before anything lands.
    module Harm

      # `{ 'amount' => what they took after resistances, 'applied' => the resistances that counted,
      #    'fate' => :dead or :spared, where it settled that for a character }`. Whether it may kill is
      # the encounter's to say unless `is_dm` says. `continuing` is the rest of a hit whose first damage
      # has landed, which drops nobody a second time. `about` is what else is so of the damage - silver,
      # magical, in an area (`IWR.facts`) - and `once` the weaknesses the hit has already been felt by.
      def self.damage(holder, amount, kind = nil, is_dm: nil, critical: false, continuing: false, about: [], once: nil)
        Actors.of(holder).damage(amount, kind, :is_dm => is_dm, :critical => critical, :continuing => continuing,
                                               :about => about, :once => once)
      end

      def self.heal(holder, amount, options = [])
        Actors.of(holder).heal(amount, options)
      end

      # `12 / 20`, for whoever may see it.
      def self.hit_points(holder)
        Actors.of(holder).hit_points
      end
    end
  end
end
