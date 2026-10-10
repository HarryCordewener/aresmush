---
toc: Pathfinder Second Edition
summary: Healing and damage-related commands.
aliases:
- damage
- heal
- condition
---
# Pathfinder 2E - Damage and Healing

Damage, healing and conditions happen in an encounter, to a character as they stand in it. A character's
own sheet stays whole: `sheet` shows them as they are, and `+e/sheet` shows them in the encounter here,
with what it has done to them. Outside an encounter these commands have nobody to change.

A target may be a combatant's id from `+e/view`: `damage #3=5 fire`.

## Anyone in the encounter

`heal <list>=<amount>[ <action>]`: Heals each of them for `<amount>`, up to their maximum Hit Points. Name the action - `treat wounds` - and a bonus to healing from it applies.

## The GM

`damage[/ndc] <list>=<amount>[ <kind>]`: Damages each of them for `<amount>`. Naming the kind - `fire`, `cold`, `persistent-damage` - lets anything they are immune to, weak to, or resistant to apply before the damage lands; without one, nothing resists it. From a Plotmaster or staff it may kill a character whose dying value reaches death, unless `/ndc` says not; from anyone else it never does, and leaves them unconscious instead.
`condition/set <list>=<condition>[/<value>]`: Sets `<condition>` on each of them. `<value>` is 1-5; 0 clears the condition. Drained and Doomed are a Plotmaster's or staff's to give a character; anyone running the encounter may lower or clear them.
