---
toc: Magic In Pathfinder 2e
summary: Other spell-related commands.
aliases:
- spell
- spells
- magic
---

# Magic-Related Commands in Pathfinder 2e
Many characters in Pathfinder 2e have access to magic. This page acts as a reference for magic-related commands.

## Basic Magic Commands
**Commands**:
`spell <spell name>`: Quickly looks up the details of a spell. This command will accept partial matches, but spell details are only given if there is exactly one match. (For a more robust spell search command, see `help spell search` to learn more about the `spell/search` command.)
`magic`: Your magic by class, innate spell access and archetype, and your focus spells. In an encounter, it shows what you have left to cast there since the GM last rested you.
`magic <character>`: Another character's, the same way.

## Preparing Spells
If you're a prepared spellcaster, what you prepare is what a rest in an encounter gives you to cast. For more information about preparing spells and resting and a full list of spell preparation commands, see `help prepare` and `help rest`.

## Learning Spells
If you keep a spellbook (a wizard's spellbook or a witch's familiar) or a book a feat gives you (Esoteric Polymath, Arcane Evolution), you can Learn a Spell to add a common spell of its tradition to it. You roll the tradition's skill (Arcana, Nature, Occultism or Religion) against a DC set by the spell's rank, and pay for the materials:

| Rank | Materials | DC |
|---|---|---|
| Cantrip or 1st | 2 gp | 15 |
| 2nd | 6 gp | 18 |
| 3rd | 16 gp | 20 |
| 4th | 36 gp | 23 |
| 5th | 70 gp | 26 |
| 6th | 140 gp | 28 |
| 7th | 300 gp | 31 |
| 8th | 650 gp | 34 |
| 9th | 1,500 gp | 36 |
| 10th | 7,000 gp | 41 |

You need the full price to try. On a critical success you learn the spell for half the price; on a success, for the full price. On a failure you pay nothing, and on a critical failure you pay half; either way you can't try that spell again until you gain a level. The Magical Shorthand skill feat turns a success into a critical success, and lets you try again after a week. The wizard feat Spellbook Prodigy gives you Magical Shorthand, and turns a critical failure into a failure. Uncommon and rare spells need access from staff.

**Commands**:
`spell/learn <spell name>`: Learns `<spell name>` into your spellbook or book.
`spell/learn <book or class>/<spell name>`: Learns it into the one you name, if you keep more than one.

## Casting Spells
Casting spells depends on what type of spell you'd like to cast. For more information about casting spells and a full list of casting commands, see `help casting`.

## Searching Spells
The `spell/search` command provides a robust search function to help you find spells for your character to learn. See `help spell search` for more information.

To see only the spells you could actually put in a slot - the right tradition, at a rank you can
cast - use `spell/eligible <level>`, or `spell/eligible` on its own to see which traditions you draw on.