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

`damage[/ndc] <list>=<amount>[ <kind>[ <what else>...]]`: Damages each of them for `<amount>`. After the kind, say what else is so of the damage - `silver`, `cold iron`, `magical`, `holy`, `area`, `splash`, `spell`, `nonlethal` - for a weakness or a resistance that asks: `damage #3=12 slashing silver`. Naming the kind - `fire`, `cold`, `persistent-damage` - lets anything they are immune to, weak to, or resistant to apply before the damage lands; without one, nothing resists it. From a Plotmaster or staff it may kill a character whose dying value reaches death, unless `/ndc` says not; from anyone else it never does, and leaves them unconscious instead.
`condition/set <list>=<condition>[/<value>]`: Sets `<condition>` on each of them. `<value>` is 1-5; 0 clears the condition. Drained and Doomed are a Plotmaster's or staff's to give a character; anyone running the encounter may lower or clear them. `condition/set <who>=dead` is a Plotmaster's or staff's to say of a character, and `condition/set <who>=dead/0` brings them back, unconscious with no hit points.

## No hit points left

A character reduced to no hit points is dying: Dying 1, or 2 from a critical hit, and one more for each
point of Wounded. From then on they act directly before whoever's turn they fell in. They roll a
recovery check as each of their turns starts, and can do nothing meanwhile but answer the hit that
dropped them with a reaction that could have stopped it.

- **A nonlethal blow** knocks them out and does not kill: unconscious with no hit points, not dying,
  and awake again when healed.
- **Damage of twice their hit points or more in one blow** is death outright, where the encounter may
  kill.
- **`+e/act administer first aid=<who>/stabilize`** is Medicine against 5 more than their recovery DC.
  A success leaves them no longer dying, unconscious still, and wounded one more; a critical failure
  brings them nearer death.
- **`+e/act administer first aid=<who>/stop bleeding/<dc>`** is against the DC of what made them
  bleed. A success gives them a flat check against DC 10 to end it; a critical failure deals them the
  bleed at once.
- **`+e/act assisted recovery[=<who>][/<kind>][/<dc>]`** spends two actions putting out what burns or
  staunching what bleeds: another flat check now, against its DC or the one the GM allows.
