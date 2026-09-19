---
toc: Pathfinder Second Edition
summary: Acting in an encounter - actions, Strikes and spells against a target.
aliases:
- encounter actions
- act
- strike
- cast
- cover
- conceal
- trust
- why
---
# Pathfinder 2E - Acting in an Encounter

The map is in another app, and nothing here can see it. So what the map would have told the game -
who you are targeting, that you flank, which range increment they are in, what cover they have - is
said in words, and the game does the arithmetic from there: your check against the target's real
defence, your multiple attack penalty, the target's cover and concealment, and what the outcome does.

Every roll is open: the room sees each roll and what it was against.

## The shape of every command

    +e/<verb> <what>=<who>/<circumstance>/<circumstance>

`<who>` is a combatant's id from `+e/view` - `#3` - or a name only one of them has. What comes after
each `/` is a circumstance.

## Doing things

`+e/act <action>[=<target>][/<circumstance>...]` - Use an action.
    +e/act trip=#3
    +e/act demoralize=#3/unintelligible
    +e/act raise a shield
    +e/act aid=bram/athletics
An action that rolls a check - Trip, Demoralize, Grapple, Feint, Escape, Seek and the rest - rolls it
against the target's defence and says how it went. An action that puts an effect on you - Rage, Take
Cover, a stance - puts you under it. Anything else is announced.

`+e/strike <target>[=<weapon>][/<circumstance>...]` - Strike, with your first equipped weapon or the one
you name (by name or nickname, or an unarmed attack like `fist`). A hit rolls the damage and deals it,
after what the target resists.
    +e/strike #3
    +e/strike #3=longsword/flanking
    +e/strike #4=shortbow/range 2

`+e/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>]` - Cast a spell. It is spent the way
`cast` spends it - a slot, a focus point, a use - and refused if you have none. Add `/focus`,
`/innate` or `/signature` for those kinds of casting. A spell attack rolls against each target's AC;
a save is rolled by each target against your DC, a basic save halving and doubling the damage; and
what an outcome leaves - Fear's frightened, Slow's slowed - is left on them.
    +e/cast fear=#3
    +e/cast fireball=#3,#4,#5/rank 4

## Circumstances

`flanking` - The target is off-guard to you: -2 AC.
`range <n>` - Which range increment the target is in: -2 for each past the first. Past the sixth, a
ranged attack cannot reach.
`<number>` - The DC, for an action with no target: `+e/act balance/18`.
Anything else is a circumstance the rules may ask about: `unintelligible`, a skill for Aid, a variant
like `stabilize`.

## What happens

A consequence the action states outright happens: a successful Trip knocks the target prone, a
Demoralize leaves them frightened. Every change prints the command that reverses it:

    Aria uses Trip on Goblin Warrior #3: Athletics 23 (15 +8) vs Reflex DC 17 - success.
      Goblin Warrior #3 is now Prone.
        (undo: condition/set #3=Prone/0)

A condition that lasts only a while - Feint's off-guard, Slow's slowed - ends on its own at the right
turn. Frightened eases by one at the end of each of its holder's turns.

`+e/why` - Every modifier of your last roll, and of the defence it was against.

## Your turn

`+e/turn [<who>]` - How many actions you have used this turn, whether your reaction is spent, and what
your next attack's penalty is. Nothing is refused: the GM can always say yes.
When your turn starts you are told what matters: your actions, what you are under and for how long,
persistent damage, and your auras.

`+e/enter <aura>=<target>,<target>` - Who the map shows inside one of your auras. They are put under
what it does, following its own terms for allies and enemies.
`+e/leave <aura>=<target>` - Someone has left it; what it put on them ends.

## Cover and concealment

Cover and concealment are the target's, set on it by the GM or a player the GM has trusted this
encounter. Every attack and check against the target reads them until someone changes them.

`+e/cover <target>=<none|lesser|standard|greater>` - +1, +2 or +4 to AC; standard and greater to a
Reflex save against an area too.
`+e/conceal <target>=<none|concealed|hidden|undetected>` - An attack against it rolls a flat check
first: DC 5 concealed, DC 11 hidden or undetected. Against an undetected target, the GM says whether
you guessed its square.

## For the GM

`+e/trust <name>`, `+e/untrust <name>` - Who may set cover and concealment. Trust lasts the encounter.
`+e/as <combatant>=<act|strike|cast|enter|leave> <what>` - Act for a creature, or anyone in the
encounter, with the same commands:
    +e/as #3=strike aria
    +e/as #3=strike aria=shortbow/range 2
    +e/as #5=act demoralize=aria
    +e/as #6=cast fear=aria
A creature's own abilities are used by name: `+e/as #3=act goblin scuttle`.
A creature's turn reminder, and its hit points after it is hurt, go to you alone.
