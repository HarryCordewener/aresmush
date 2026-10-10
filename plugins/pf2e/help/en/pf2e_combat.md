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

`encounter/join [<encounter ID>=][<stat>]`: Joins an encounter, rolling initiative on the statistic its GM named - Perception unless they said otherwise. If the GM tells you to roll something else, name it: Perception, a skill, or an ability, in any case, by its first letters or an ability's three: `encounter/join 12=stealth`, `encounter/join dex`.
`+e/sheet[ <#id or name>][/<section>]`: A character's sheet as they stand in this encounter: their Hit Points, conditions and what they are under, which `sheet` does not show. Sections are those of `sheet`.
`encounter/view [<encounter ID>]`: View the initiative table for the encounter in question: each combatant's id, initiative, conditions, and the cover and concealment set on them. (Alias `tinit <encounter ID>`)
`+e/creature <#id>`: A creature's name and conditions. Its stat block and hit points are its GM's to see.

## Encounter commands for plot runners

Any approved character starts an encounter, and is its GM: whoever started it, or whoever it was handed
to. Staff can run any encounter. A GM's
commands reach their encounter from anywhere: in its scene they address it, and away from it they
address the one encounter the GM runs, or the one chosen with `+e/focus`.

How far an encounter may go depends on who runs it:

- **Anyone** runs one with the creatures of Monster Core and Monster Core 2, each as written or made
  elite or weak. Their encounter does not kill a character or leave one Drained or Doomed: what would
  kill leaves the character unconscious instead, no longer dying, and a Drained or Doomed from a
  creature's ability passes them by. What a character does to themselves still lands.
- **A Plotmaster** - a role with the `kill_pc` permission - adds any creature of the bestiary, and
  creatures of their own making. In their encounter a character at the dying value that is death
  dies, from a hit, persistent damage or a failed recovery check, and Drained and Doomed land.
  `+e/undo` takes a death back like any other change, and `condition/set <who>=dead/0` brings a
  character back.
- **Staff** run any encounter as a Plotmaster does.

`+e/focus [<encounter ID>]`: Which of the encounters you run your commands address while you are away from its scene. With no ID, the only one you run.
`+e/owner [<encounter ID>=]<character>`: Hands the encounter to someone else, who is its GM from then on.

`encounter [<stat>][=<encounter ID>]`: Starts an encounter in the scene, with you as its GM, rolling initiative on `<stat>` (Perception unless you say otherwise). Name an earlier encounter and whoever was in it carries on as they left it: their wounds, conditions, effects and spent spells. Anyone else starts fresh - their own sheet, rested. Started while the party is exploring, it takes over from the exploration: see `help exploration`.
`+e/add [<count>] [elite|weak] <creature>[=<name>]`: Adds creatures from the bestiary - the Remaster's, some three thousand of them - each with its own id, hit points and conditions, and its initiative rolled on its Perception. `+e/add 3 goblin warrior` adds three; `+e/add goblin warrior=Grik` names one; `+e/add 2 elite goblin warrior` adds two with Monster Core's elite adjustment. Player characters join with `encounter/join`. (Alias: `jinit`)
`+e/adjust <#id>[,<#id>...]=elite|weak|normal`: Makes a creature already in the encounter elite or weak, or takes the adjustment off. Elite is two more to its AC, attacks, DCs, saves, Perception and skills, two more damage from its Strikes and abilities (four from what it cannot use every round, and from its spells), more hit points by its level, and a level higher; weak is the same the other way. It keeps the hit points it has lost. Only you are told. This is how one creature serves parties of different levels.
`+e/add [elite|weak] <name>=<description>`: For a Plotmaster or staff: adds a creature of your own making. See **A creature of your own** below.
`+e/bestiary <words>[/<level>]`: Creatures you may add whose names hold the words, at a level if one is given.
`+e/creature <creature>`: A creature's stat block from the bestiary. Not while you are a player in someone else's encounter.
`encounter/mod [<encounter ID>=]<#id or name>=<new init>`: Sets a combatant's initiative. Whoever's turn it is keeps it.
`encounter/remove [<encounter ID>=]<#id or name>`: Takes a combatant out of the order; a creature removed is gone. (Alias: `rminit`)
`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative backwards one turn. (Alias: `pinit`)
`encounter/scan`: For the GM: everyone in the encounter as they stand, by id - each character and creature's hit points, AC, Perception, saves and whether they have a Reactive Strike, a creature's level and whether it is elite or weak, and beneath each what they are immune to, weak to and resist. (Alias: `tscan`)
`+e/level <n>`: Sets the party's level for the encounter's difficulty, which is otherwise the characters' average. `+e/level 0` goes back to the average. `+e/view` shows the difficulty: the threat, from trivial to extreme, and the XP behind it, by GM Core's encounter budget.
`encounter/end <encounter ID>`: Ends an encounter. Trust given for it, the cover and concealment set in it, and what may be used once an encounter all end with it.
`encounter/restart <encounter ID>`: Restarts an encounter, so long as the scene has not ended.

## Running a creature

`+e/as <#id>=strike <target>[=<Strike>]`, `=act <ability>[=<targets>]`, `=cast <spell>=<targets>` and
`=enter <aura>=<targets>` act for a creature. What its stat block gives it is run where the rules can
be:

- **A Strike's follow-up** - Grab, Knockdown, Push and their Improved forms - is offered when the Strike
  that lists it hits, and is its very next action: `+e/as #5=act grab=#2`. A Grab on someone it already
  holds tightens the hold to the end of its next turn, without a roll.
- **Constrict** crushes everyone it holds, or those you name among them. **Swallow Whole** needs it to
  hold the target; **Engulf** and **Trample** take every target you name. **Rend** needs two hits
  running with its listed Strike. **Ferocity** is offered when it drops.
- **An ability that calls for a save** - a breath, a gaze, a swarm's bites - is aimed at as many as you
  name, and each rolls it: `+e/as #5=act flame breath=#1,#2,#3`. What its outcomes name is left on
  them, and damage in its words is dealt by the save.
- **An aura with a save** - Frightful Presence, Stench - is rolled by whoever you put inside it with
  `+e/as #5=enter frightful presence=#1,#2`. Whoever has saved is immune for as long as its words say.
- **A venom or disease** on its Strike is saved against as the Strike hits, and runs its stages from
  there. `+e/affliction <who>=<name>/<stage>` moves it by hand: a stage counted in days, a cure with 0.
- **An ability that Strikes each of several targets** - a hydra's Storm of Jaws - Strikes each one you
  name under the one penalty, which moves on once they are all made. One whose Strike follows a failed
  save - a harpy's Hungry Winds - rolls the save, and Strikes whoever fails.
- **An ability that takes one action or more** - a troop's attack, `1 to 3` on its first line - deals
  what the actions you spend deal: `+e/as #5=act shambling onslaught=#1,#2/actions 2`. One, unless you say.
- **A shield** on its stat block is raised and blocked with as a character's is: `+e/as #5=act raise a
  shield`, and `+e/as #5=act shield block` when a hit it could block says so. `+e/creature #5` shows
  what the shield has taken.
- **Hardness** comes off each hit it takes, and adamantine as hard as it halves that: `damage #5=12
  slashing adamantine`.
- **A troop** loses a segment as its hit points fall below each threshold, which is then the most it has.
- **What its dropping triggers** - a vampire's Mist Escape, Ferocity - is offered as it drops, and is
  all it can still do.
- **A breath that takes rounds to come back**, a reaction already spent, and an ability used more often
  than its Frequency allows are yours to allow: you are told when the breath is back, and warned if you
  use any of them early.
- **What it is for good** - a zombie's Slowed 1 and its having no reactions - is on it from the start,
  and stays whatever is cleared.
- **Its spells** are counted: each preparation of a prepared spell, the slots of a rank for a
  spontaneous caster, once a day for an innate spell unless its stat block says otherwise. Past that
  you are warned, and it is cast.
- **Immunity to magic** keeps out a spell and all it does, but for the spells it names.
- **A circumstance** its stat block makes a toggle - Pack Attack, a charge - is off until you say it
  holds: `/pack attack` on the Strike, or `+e/option #5=pack-attack/on`.
- **Immunities, weaknesses and resistances** apply by what the damage is: a swarm resists a blade and
  is hurt more by a fireball; a devil's resistance lets silver through. `encounter/scan` lists them.
  What a creature is counts without its stat block saying so: a construct, a mindless creature and a
  swarm have their kind's immunities, vitality harms only the undead, and void only the living.
  `damage` tells you what was taken where that is not what you named.
- **The incapacitation trait** moves the outcome a degree for a creature too strong for the effect.

Anything else on its stat block is told with its words when used, for you to run.

## A creature of your own

A Plotmaster or staff describes a creature on one line: its figures first, then whatever else it has,
each part after a semicolon and named by its first word.

`+e/add Bandit Chief=ac 19 hp 45 level 3 fort 9 ref 11 will 7 perception 9 speed 25 str 3 dex 4; skills athletics 9, stealth 11; resist poison 5; weak fire 5; immune sleep; traits humanoid, human; strike shortsword +12 1d6+6 piercing (agile, finesse); ranged shortbow +12 1d6+2 piercing (range 60, deadly d10); ability Hail of Arrows [2]: Each creature in a 15-foot burst takes 3d6 piercing damage (DC 20 basic Reflex save).`

- **Figures**: `ac` and `hp` are needed; `hardness`, `level`, `fort`, `ref`, `will`, `perception`, `speed` (and `fly`, `swim`, `climb`, `burrow`), and its attribute modifiers `str dex con int wis cha`, which stand in for a skill it does not list.
- `skills <skill> <n>, ...`
- `immune <type>, ...`; `weak <type> <n>, ...`; `resist <type> <n>[ except <type>[ or <type>]], ...`: `resist physical 10 except silver`
- `traits <trait>, ...`; `size <size>`; `rarity <rarity>`; `senses <sense>, ...`
- `shield [<name>] <hardness> <hit points>[ +<bonus>]`: `shield 5 20`, raised for +2 to AC unless you say, and blocked with.
- `strike <name> <bonus> <damage> <type>[ plus <damage> <type>][ (<traits>)]`, as many as it has. `ranged` for a ranged one, with `range <feet>` among its traits. `1d4 persistent bleed` is persistent damage.
- `ability <name>[ [<1|2|3|reaction|free|passive>]]: <what it does>`. One whose words give a save rolls it when used with `+e/as <#id>=act <ability>=<targets>`: damage against it - `3d6 fire damage (DC 20 basic Reflex save)` - is dealt by the save, and outcomes written as a stat block writes them, each on a line of its own after `%r` - `Failure The creature is Frightened 2.` - leave the conditions they name.

It fights as a creature from the bestiary does, and can be made elite or weak.

## Bonuses and penalties

A bonus or penalty that lasts a while is an effect: `effect/add <who>=<effect>` puts someone under it -
Bless, Heroism, a potion - and its numbers reach every roll it applies to, and it ends at the right turn
on its own. See `help effects`. A combatant can be named by its id: `effect/add #3=bless`.

## Healing and Damage Commands

Damage, healing and conditions happen to a character as they stand in the encounter: `help heal`.

## Rewards, for staff

`+e/award [<encounter ID>]`: What PF2e recommends for an encounter - its XP, as for a party of four, the accomplishments staff may add, and GM Core's treasure for its threat - and what has been paid for it. A recommendation only.
`+e/award [<encounter ID>=]<character>=<xp>/<amount> <coin>`: Pays a character what staff decide for the encounter: `+e/award 12=Aria=80/135 gp`. It is recorded against the encounter and in the character's XP and money history.
