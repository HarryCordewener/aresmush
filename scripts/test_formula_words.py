"""python3 -m unittest scripts/test_formula_words.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from formula_words import in_words  # noqa: E402


class FormulaWords(unittest.TestCase):

    def test_levels_listed_as_steps(self):
        self.assertEqual(
            in_words('takes ternary(gte(@actor.level, 18), 7, ternary(gte(@actor.level, 15), 6, 5))d6 acid damage'),
            'takes 5d6 (6d6 at 15th level, 7d6 at 18th level) acid damage')

    def test_a_rate_per_rank(self):
        self.assertEqual(in_words('takes (@item.rank)d6 bleed damage'), 'takes (1d6 per spell rank) bleed damage')
        self.assertEqual(in_words('takes (floor(@item.rank/2))d8 cold damage'),
                         'takes (1d8 per 2 spell ranks) cold damage')

    def test_a_rate_rounded_up(self):
        self.assertEqual(in_words('You deal ceil(@actor.level/2)d8 piercing damage'),
                         'You deal (1d8 per 2 levels, rounded up) piercing damage')

    def test_a_climb_from_a_base(self):
        self.assertEqual(in_words('regains (1+(max(0,floor(@actor.level/2))))d6 healing Hit Points'),
                         'regains (1d6, plus 1d6 per 2 levels) healing Hit Points')

    def test_a_multiple(self):
        self.assertEqual(in_words('takes 5*@item.level damage', ranked=True), 'takes (5 per spell rank) damage')
        self.assertEqual(in_words('deal (@item.rank -2)*2 electricity damage'),
                         'deal (2 per spell rank above 2) electricity damage')

    def test_a_count_only_spoken(self):
        self.assertEqual(in_words('takes (ceil((@actor.flags.system.blinkCharge - 4)/2))d8 force damage.'),
                         'takes (d8s equal to half of (your blink charge - 4), rounded up) force damage.')

    def test_a_floor_under_a_climb(self):
        self.assertEqual(in_words('takes (max(8, @item.rank*2))d6 mental damage'),
                         'takes (8d6, and 2d6 more every spell rank from rank 5) mental damage')

    def test_a_number_that_steps(self):
        self.assertEqual(in_words('takes (ternary(gte(@item.rank, 10), 115, 100)) void damage'),
                         'takes 100 (115 at rank 10) void damage')

    def test_a_spell_level_read_as_its_rank(self):
        self.assertEqual(in_words('takes (@item.level)d4 persistent spirit damage', ranked=True),
                         'takes (1d4 per spell rank) persistent spirit damage')
        self.assertEqual(in_words('takes (@item.level+2)d6 poison damage', ranked=True),
                         'takes (2d6, plus 1d6 per spell rank) poison damage')

    def test_several_references_read_out(self):
        self.assertEqual(in_words('your Intelligence modifier ((1d6 + @actor.level + @actor.system.abilities.int.mod) healing).'),
                         'your Intelligence modifier ((1d6 + your level + your Intelligence modifier) healing).')

    def test_a_flag_damage_type_and_roll_options_dropped(self):
        self.assertEqual(in_words('deals 13d6[@item.flags.system.rulesSelections.breathWeapon] damage'), 'deals 13d6 damage')
        self.assertEqual(in_words('You regain 2d8 healing vitality|shortLabel Hit Points.'),
                         'You regain 2d8 healing vitality Hit Points.')
        self.assertEqual(in_words('deals max(2, @actor.level)d6[@actor.flags.system.inventor.explode] damage'),
                         'deals (2d6, and 1d6 more every level from 3rd level) damage')
        self.assertEqual(in_words('take (@item.system.damage.dice splash) bludgeoning damage'),
                         'take (its weapon damage dice splash) bludgeoning damage')

    def test_a_flags_own_dice(self):
        self.assertEqual(
            in_words('takes ((@actor.flags.system.sneakAttackDamage.number)d(@actor.flags.system.sneakAttackDamage.faces)) precision damage'),
            'takes (your sneak attack dice) precision damage')
        self.assertEqual(
            in_words('takes 1d6 bludgeoning, (((@actor.flags.system.sneakAttackDamage.number)d(@actor.flags.system.sneakAttackDamage.faces)) precision) bludgeoning damage.'),
            'takes 1d6 bludgeoning, your sneak attack dice precision bludgeoning damage.')

    def test_prose_without_a_formula_is_left_alone(self):
        text = 'The creature takes 2d6+3 fire damage (DC 28 basic Reflex save) and is Frightened 1.'
        self.assertEqual(in_words(text), text)


if __name__ == '__main__':
    unittest.main()
