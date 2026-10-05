---
toc: Magic In Pathfinder Second Edition
summary: Preparing spells.
aliases:
- prepare
- unprepare
- prepared
---

# Preparing Spells in Pathfinder Second Edition

Some classes record spells and cantrips in a spellbook, or otherwise 'prepare' spells for the day.

**Important!** What you prepare is what you have to cast in your next encounter: it starts you with it, and each rest the GM gives you there prepares it again. See `help rest`.

**Commands**:
`prepare <caster class>/<level> = <spell name>`: Prepares `<spell name>` at the defined level, optionally at a higher `<level>` than its default level. Preparing at a higher level than a spell's base level heightens the spell to that level. (You can't prepare a spell lower than its default level.) Omitting the `<level>` switch will prepare the spell at its base level.
`unprepare <caster class>/<level> = <spell name>`: Removes `<spell name>` at the defined `<level>` from your prepared list.
`prepare <caster class>/<cantrip> = <spell name>`: Prepares the cantrip `<spell name>`.
`unprepare <caster class>/<cantrip> = <spell name>`: Removes the cantrip `<spell name>` from your prepared list.
`prepared [<caster class>]`: Shows your currently prepared spell list. If `<caster class>` is omitted, it will show you all spell lists. 

## A cleric's deity spells

A cleric can prepare their deity's cleric spells as if they were on the divine list, even ones from another tradition or uncommon ones. `magic` lists them under your Divine Font.

## Preparing from a book: Esoteric Polymath and Arcane Evolution

A bard with **Esoteric Polymath** keeps a Book of Occult Spells, and a sorcerer with **Arcane Evolution** keeps a list of arcane spells. Each holds every spell in your repertoire, plus any spell you learn into it with `spell/learn` (see `help spells`). Each day, before you `rest`, you pick one spell from it:

- A spell already in your repertoire becomes a **signature spell** until your next rest.
- A spell that isn't joins your **repertoire** until your next rest, at its own rank or a higher one you have slots for.

You make one pick between rests. If you took Esoteric Polymath, every spell that has been in your repertoire since stays in your book, even one you later swap out.

**Commands**:
`prepare/esotericpolymath <spell name>`: Picks `<spell name>` from your Book of Occult Spells.
`prepare/esotericpolymath <rank> = <spell name>`: Picks a spell that isn't in your repertoire, adding it at `<rank>`.
`prepare/arcaneevolution <spell name>`: Picks `<spell name>` from your Arcane Evolution list.
`prepare/arcaneevolution <rank> = <spell name>`: Picks a spell that isn't in your repertoire, adding it at `<rank>`.

## Two spells in one slot, and mastered spells: Split Slot, Spell Combination and Spell Mastery

A wizard with one of these feats prepares through its own switch. `prepared` and `magic` show what you have, and each takes effect when you next `rest`.

- **Split Slot**: two spells in one slot, at least one rank below your highest. Cast either one and the other is lost.
- **Spell Combination**: two spells in one slot of rank 3 or higher, one such slot per rank. Both are cast together, at two ranks below the slot. Both spells must target only one creature (or be able to), and both must work the same way: both by spell attack, both by the same save, or both automatically. The code doesn't check this yet, so keep to it yourself.
- **Spell Mastery**: up to four spells from your spellbook, each at a different rank of 9 or lower, prepared at every rest in slots of their own. Change them whenever you like; the change takes effect at your next rest.

**Commands**:
`prepare/splitslot <rank> = <spell>, <spell>`: Prepares two spells in one slot of `<rank>`.
`unprepare/splitslot`: Empties that slot.
`prepare/spellcombination <rank> = <spell> + <spell>`: Prepares a combined spell in a slot of `<rank>`.
`unprepare/spellcombination <rank>`: Empties the combination slot of `<rank>`.
`prepare/spellmastery [<rank> =] <spell>`: Masters `<spell>`, at its own rank or at `<rank>`. A spell already mastered at that rank is replaced.
`unprepare/spellmastery <spell>`: Stops mastering `<spell>`.

To cast from one of these slots, cast the spell as usual. A combined spell is cast by naming either of its spells.

## Preparing sets of spells

Prepared casters may also choose to prepare standard sets, or many spells at once.

**Commands**:
`spellset/add <set name> = <spell name>/<level>`: Adds a spell to a set with name `<set name>`. `<set name>` may contain spaces or special characters except for = or /. If `<set name>` does not exist, this command will create it, otherwise it will add that spell to the list.
`spellset/list [<set name>]`: If `<set name>` is provided, shows the prepared spells in set `<set name>`. If not, shows a list of available sets. 
`spellset/clear <set name>`: Deletes the set `<set name>`.
`spellset/rem <set name> = <spell name>/<level>`: Removes `<spell name>` from set `<set name>`.
`spellset/ready <set name>`: Clears all existing prepared spells and replaces it with the contents of `<set name>`.