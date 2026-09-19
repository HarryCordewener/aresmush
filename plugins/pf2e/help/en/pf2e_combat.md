---
toc: Pathfinder Second Edition
summary: Encounter-related commands.
aliases:
- initiative
- init
- tinit
- damage
- heal
- encounter
- combat
---
# Pathfinder 2E Encounters

Invoking encounter mode (also known as _initiative_) changes the time flow of a scene. It is used when time must be closely tracked in order to understand the outcome.

The following commands are used to manage encounter mode in a scene. Note that in order to participate in an encounter, you must join the scene (not just watch).

For all commands, `+e`, "initiative" and "init" are short for "encounter": `+e/view` is `encounter/view`.

Everyone in an encounter has an id, shown by `+e/view` as `#1`, `#2` and so on. An id is never reused
in an encounter, so `#3` is the same goblin all fight long; commands that name someone take the id or
a name only one combatant has. Acting in an encounter - actions, Strikes, spells - is in
`help encounter actions`.

## Encounter commands for participants

`encounter/join <encounter ID>[=<stat>]`: Joins an encounter in progress, using the stat specified by the organizer by default. If the organizer tells you that you should use a different stat, specify <stat>. 
`encounter/view [<encounter ID>]`: View the initiative table for the encounter in question: each combatant's id, initiative, conditions, and the cover and concealment set on them. (Alias `tinit <encounter ID>`)
`+e/creature <#id>`: A creature's name and conditions. The GM sees its whole stat block and hit points.

## Encounter commands for plot runners

`encounter <stat>`: If an encounter is not active in the scene, this command starts an encounter, with you as the organizer. `<stat>` is optional and will default to Perception if not specified.
`+e/add [<count>] <creature>[=<name>]`: Adds creatures from the bestiary - Foundry's bestiaries, six thousand of them - each with its own id, hit points and conditions, and its initiative rolled on its Perception. `+e/add 3 goblin warrior` adds three; `+e/add goblin warrior=Grik` names one. Player characters join with `encounter/join`. (Alias: `jinit`)
`+e/add <name>=ac <n> fort <n> ref <n> will <n> perception <n> hp <n>`: Adds a creature the bestiary lacks, from the numbers on its stat block. It has no Strikes of its own; roll its attacks with `roll`.
`+e/bestiary <words>[/<level>]`: Creatures whose names hold the words, at a level if one is given.
`+e/creature <creature>`: A creature's stat block from the bestiary.
`encounter/mod <encounter ID>=<name>=<new init>`: Sets name's initiative to the new initiative.
`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative backwards one turn. (Alias: `pinit`)
`encounter/scan`: Allows the organizer to view details on all player characters who have joined the encounter. (Alias: `tscan`)
`encounter/end <encounter ID>`: Ends an encounter. Trust given for it, the cover and concealment set in it, and what may be used once an encounter all end with it.
`encounter/restart <encounter ID>`: Restarts an encounter, so long as the scene has not ended.

## Tracking bonuses and penalties
`encounter/bonus <encounter ID> = <bonus description>/<comma-separated list of people to whom it applies>`: Records a bonus that is available to players in the list. Helps keep track of buffs. 
`encounter/penalty <encounter ID> = <penalty description>/<comma-separated list of people to whom it applies>`: Records penalties applicable to players in the list. 
`encounter/expire <description>`: Clears all bonuses and penalties whose descriptions match `<description>`.

**TIP** Consider including the name of the spell that invoked the bonus or penalty in the description. That way, `encounter/expire` can clear all bonuses / penalties associated to the spell with one command. 

## Healing and Damage Commands

Any approved player may use a heal command at any time. To damage a player, you must be a Plotmaster, game admin, or the organizer of an encounter to which the targets are joined.

A target in any of these may be a combatant's id: `damage #3=5 fire`.

`heal <player list> = <amount>`: Heals each character in `<player list>` for `<amount>`, up to their maximum HP.
`damage[/ndc] <player list> = <amount>[ <type>]`: Damages each character in `<player list>` for `<amount>`, after what they resist. The optional `/ndc` is for DM's and admins only, and disables the check to see if a character is dead. It has no effect for organizers without admin or Plotmaster roles.
`condition/set <player>=<condition>[/<value>]`: Sets `<condition>` on `<player>`. `<value>` can be 1-5 to set it. Setting value to 0 for any condition clears it. 

