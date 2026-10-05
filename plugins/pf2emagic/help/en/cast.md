---
toc: Magic In Pathfinder 2e
summary: Commands used to cast spells.
aliases:
- cast
- casting
- spellcasting
---

# Casting Spells in Pathfinder 2e

Spells are cast in an encounter, from what a rest there gave you: the day's slots, your focus points, and
your innate spells' uses. Outside an encounter there is nothing to cast from. See `help encounter actions`
for the whole grammar.

`+e/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>][/<how>]`

`<spell>`: The spell's name.
`<target>`: Whoever it is cast at, by id or name: `+e/cast fear=#3`.
`rank <n>`: The rank to cast it at, where it can be heightened. Without one, its own.
`class <class>`: Which of your casting classes casts it, where you have more than one.
`<how>`: `focus` for a focus spell, `focusc` for a focus cantrip, `signature` for a signature spell at a
higher rank, `innate` for an innate spell.

    +e/cast glitterdust=#3,#4/rank 2
    +e/cast lay on hands=Bram/focus
    +e/cast daze=#2/innate

## Slots for Certain Spells

Divine Evolution, Primal Evolution and Gifted Power each give you one extra slot a day at your highest
rank, which can only cast certain spells, even ones not in your repertoire. `magic` lists the slot and its
spells.

Cast one of those spells at your highest rank and the feat's slot is spent first. Leave the rank off, and a
spell you could not otherwise cast uses the feat's slot at your highest rank; a spell in your repertoire is
cast at its own rank from an ordinary slot, as usual.

## Refocusing

`+e/refocus` - Refocus in the encounter: see `help rest`.
