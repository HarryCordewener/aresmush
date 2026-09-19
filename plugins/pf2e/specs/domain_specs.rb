require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a statistic answers to. An effect names a domain, so "a penalty to everything" is one row
    # rather than a line per statistic, and a skill added later is covered without touching the effect.
    describe Domains do

      it "should give a save its own name, its group and its attribute" do
        expect(Domains.for('save', 'Fortitude', 'Constitution'))
          .to include 'fortitude', 'saving-throw', 'con-based', 'all'
      end

      it "should give a skill the attribute-specific check group as well" do
        expect(Domains.for('skill', 'Athletics', 'Strength'))
          .to include 'athletics', 'skill-check', 'str-skill-check', 'str-based', 'all'
      end

      # A lore's name is the player's invention, so an effect reaches every lore through the group
      # rather than by naming any of them.
      it "should let an effect reach every lore at once" do
        expect(Domains.for('lore', 'Dragon Lore')).to include 'dragon-lore', 'lore-skill-check'
      end

      it "should slug a multi-word name" do
        expect(Domains.for('lore', 'Holy Order of Ea Lore')).to include 'holy-order-of-ea-lore'
      end

      # Every check and every DC takes a penalty written against `all`. Hit points and speed are
      # neither, and a Frightened character's hit points do not move.
      it "should put every check and DC in all" do
        %w{ac perception save skill lore class_dc spell_dc spell_attack attack}.each do |kind|
          expect(Domains.for(kind, 'Something', 'Wisdom')).to include('all'), kind
        end
      end

      it "should keep hit points and speed out of it" do
        expect(Domains.for('hp')).to_not include 'all'
        expect(Domains.for('speed')).to_not include 'all'
      end

      # AC's list carries `dex-based` whatever attribute it ends up reading, which is what lets Clumsy
      # penalise it while an effect offers some other attribute for the figure itself.
      it "should give AC the list Foundry gives it" do
        expect(Domains.for('ac')).to eq [ 'all', 'ac', 'dex-based' ]
      end

      it "should omit the attribute domain when the statistic reads no attribute" do
        expect(Domains.for('hp').grep(/-based/)).to eq []
      end

      # Foundry's own lists for these two carry no attribute domain, so an effect reaches them by
      # naming them rather than by naming an attribute.
      it "should give perception and a lore the lists Foundry gives them" do
        expect(Domains.for('perception')).to eq [ 'perception', 'all', 'check', 'perception-check' ]
        expect(Domains.for('lore', 'Dragon Lore'))
          .to eq [ 'dragon-lore', 'skill-check', 'lore-skill-check', 'int-skill-check', 'all',
                   'check', 'dragon-lore-check' ]
      end

      # A roll is not a figure, and a rule may name either: Armored Stealth adjusts the armour penalty
      # on `stealth-check`, which is what their data says (`statistic/statistic.ts:314`).
      it "should give a check its own name with -check after it" do
        expect(Domains.for('skill', 'Stealth', 'Dexterity')).to include 'check', 'stealth-check'
      end

      it "should give a save one too" do
        expect(Domains.for('save', 'Fortitude', 'Constitution')).to include 'check', 'fortitude-check'
      end

      # Hit points and a speed are not rolled, so neither is a check.
      it "should not make a figure answer to a check" do
        expect(Domains.for('hp')).to_not include 'check'
        expect(Domains.for('speed')).to_not include 'check'
      end

      # An attack's domains come off the weapon, so an effect can reach one sword, every sword of a
      # group, every ranged attack or every attack at all.
      describe "an attack" do
        def sword
          { 'id' => 'abc123', 'name' => 'Longsword', 'group' => 'sword', 'base' => 'longsword',
            'prof' => 'expert', 'ranged' => false }
        end

        it "should name the weapon itself, its kind and its group" do
          expect(Domains.for('attack', sword, 'Strength'))
            .to include 'abc123-attack', 'longsword-attack', 'sword-group-attack-roll',
                        'longsword-base-attack-roll', 'melee-attack-roll', 'strike-attack-roll',
                        'attack-roll', 'attack', 'check', 'all', 'expert-attack', 'str-based',
                        'str-attack'
        end

        it "should say ranged for a ranged weapon" do
          ranged = Domains.for('attack', sword.merge('ranged' => true), 'Dexterity')

          expect(ranged).to include 'ranged-attack-roll'
          expect(ranged).to_not include 'melee-attack-roll'
        end
      end

      describe "damage" do
        def sword
          { 'id' => 'abc123', 'name' => 'Longsword', 'group' => 'sword', 'base' => 'longsword',
            'ranged' => false }
        end

        # `{item|id}-damage` is how a rune says "this sword", and the resolved selector is exactly
        # this domain.
        it "should name the weapon by its id" do
          expect(Domains.for('damage', sword, 'Strength')).to include 'abc123-damage'
        end

        it "should name the groups an effect reaches damage through" do
          expect(Domains.for('damage', sword, 'Strength'))
            .to include 'longsword-damage', 'sword-weapon-group-damage', 'melee-strike-damage',
                        'melee-damage', 'weapon-damage', 'strike-damage', 'damage', 'str-damage'
        end

        # Damage is not a check, so nothing written against `all` reaches it: Frightened does not
        # reduce damage.
        it "should not answer to all" do
          expect(Domains.for('damage', sword, 'Strength')).to_not include 'all'
        end
      end

      it "should refuse a kind of statistic it does not know rather than answer nothing" do
        expect { Domains.for('vibes') }.to raise_error(ArgumentError, /vibes/)
      end

      describe "matching an effect against a statistic" do
        it "should match when the selector names one of the domains" do
          expect(Domains.matches?('all', Domains.for('save', 'Will', 'Wisdom'))).to be true
        end

        it "should match when a selector naming several hits one" do
          expect(Domains.matches?([ 'hp', 'fortitude' ], Domains.for('save', 'Fortitude', 'Constitution')))
            .to be true
        end

        it "should not match a domain the statistic does not have" do
          expect(Domains.matches?('dex-based', Domains.for('save', 'Fortitude', 'Constitution')))
            .to be false
        end

        it "should read a selector written the way a person would write it" do
          expect(Domains.matches?('Saving Throw', Domains.for('save', 'Will', 'Wisdom'))).to be true
        end
      end
    end
  end
end
