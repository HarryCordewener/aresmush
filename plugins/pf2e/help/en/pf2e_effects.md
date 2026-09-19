---
toc: Pathfinder Second Edition
summary: Effects a character is under for a while - spells, stances, potions.
aliases:
- effect
- effects
---
# Pathfinder 2E - Effects

An effect is what a spell, a feat or an item leaves behind for a while: *heroism*'s bonus for ten
minutes, a barbarian's rage, a potion's resistance for an hour. Its numbers go straight into the sheet
and every roll - a character under *heroism* rolls with the bonus without anyone adding it - and it ends
by itself when its time is up.

The effects are Foundry VTT's own for Pathfinder 2e, two thousand of them, so most things a spell or
feat leaves behind are already here under the name you would expect.

### Seeing them
`effects [<name>]` - What someone is under, how long each has left, and their conditions.
`effect/view <effect>` - What an effect does, how long it lasts, and what it asks when it is applied.
`effect/search <words>` - The effects whose names hold all of those words.

### Applying and ending them
`effect/add <names>=<effect>[/<option>...]` - Put one or more characters under an effect.
`effect/remove <names>=<effect>` - End it early.

These are for a DM, or the organizer of the encounter the characters are in.

The options after an effect's name are what only the one applying it knows:

* `rank <n>` - the rank a spell was cast at. *Heroism* at 6th rank is a +2 bonus rather than +1.
* `value <n>` - for an effect that counts something, how many.
* anything else answers what the effect asks: `fire` for which energy *resist energy* resists.

    effect/add Aria Bram=heroism/rank 6
    effect/add Bram=resist energy/rank 4/fire

### How long they last
An effect applied during an encounter keeps time with it. A round is a turn of the order, a minute is
ten rounds, and the count runs from the turn it was applied on - so "until the start of your next turn"
is the turn of whoever applied it, as the rules say. An effect that could not outlast the fight - one
measured in rounds, in minutes, or "until the end of the encounter" - ends when the encounter does.

A night's rest ends anything shorter than a day, and counts a night off anything measured in days. An
effect applied outside an encounter has no clock to run on, so it lasts until the next rest or until
someone ends it.

### What an effect brings with it
Some effects make you something as well - off-guard, prone, clumsy - and some conditions do too: a
grabbed character is off-guard, and a dying one is unconscious, blinded and prone. What was brought
along goes when the thing that brought it does, except where the rules say otherwise: you wake from
unconsciousness still on the ground. The sheet says what brought a condition, as `Off-Guard (Grabbed)`.
