---
toc: Pathfinder Second Edition
summary: Actions - seeing what one does, and using it.
aliases:
- action
- actions
---
# Pathfinder 2E - Actions

An action is something a character does: Take Cover, Rage, a monk's stance, a reaction. The actions
are Foundry VTT's own for Pathfinder 2e - the basic, skill and class actions, and every feat that is an
action - so an action is here under the name you would expect.

### Seeing them
`action <name>` - What an action costs, how often it can be used, and what it does. Where using it puts
an effect on you, the display names the effect, how long it lasts, and the command that takes it on.
`action/search <words>` - The actions whose names hold all of those words.
`action/available [<mode>]` - The actions you can use, grouped by what they cost. Name a mode to see only
that one: `combat` (or `encounter`), `exploration`, `downtime`, or `reactions`. `action/available/combat`
works as well. An action marked `*` puts an effect on you when you use it.

### Using them
`action/use <name>[/<option>...]` - Use an action. The room is told, and where the action puts an effect
on you - Rage, Take Cover, a stance - you are now under it, and it lasts and ends the way `effects`
describes.

The options after the name are what only you know about the effect, the same as `effect/add` takes:
`rank <n>`, `value <n>`, or an answer to what the effect asks.

    action/use rage
    action/use mountain stance

The basic, skill, exploration and downtime actions are everyone's. Any other - a class's, an
archetype's, a heritage's, and any feat that is an action - is yours if you have the feat or feature it
comes from: a barbarian has Rage because they have the Rage class feature.

In an encounter, `+e/act` does all of this and more: it rolls an action's check against its target
and applies what the outcome does. See `help encounter actions`. How often an action has been used is
counted there, and shown rather than refused.
