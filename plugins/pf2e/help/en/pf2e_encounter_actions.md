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

Some actions do more:
    +e/act battle medicine=bram/20
    +e/act reactive strike=#3/longsword
    +e/act shield block
Battle Medicine rolls Medicine against DC 15, or the higher Treat Wounds DC you name for more healing:
20, 30 or 40. Who has been treated today is the GM's to keep track of.
A reaction that is a Strike - Reactive Strike, Opportune Riposte - rolls it with the weapon you name, or
your first that will do. It spends your reaction, and the multiple attack penalty neither applies to it
nor counts it.
An action that is several Strikes - Flurry of Blows - makes them all at the one target, each counting
toward your multiple attack penalty, for what the action costs. One that is a Strike and something more -
Deadly Aim, Combat Assessment, a finisher - makes its Strike with the action's own rules on; the rest is
yours to play.
`+e/act drain bonded item/<spell>` gives a wizard back a spell they prepared today and have cast, to cast
again with `+e/cast`.
An action with a command of its own - Quick Alchemy, Refocus - is refused with that command.
Nimble Dodge, and a reaction like it that raises your AC against an attack, answers a hit you have
just taken: its bonus is put against the attack's roll, and a hit it turns into a miss is undone. A
hit it could turn says so.
Shield Block answers a hit you have just taken while your shield is raised: its Hardness comes off the
hit's physical damage, and you and the shield each take the rest. A hit you could block says so.
Disarm, Grapple, Reposition, Shove and Trip work on nothing more than one size larger than you: two
with Titan Wrestler, and three if you are also legendary in Athletics.

`+e/strike <target>[=<weapon>][/<circumstance>...]` - Strike, with your first equipped weapon or the one
you name (by name or nickname, or an unarmed attack like `fist`). A hit rolls the damage and deals it,
after what the target resists. A bomb you carry is thrown the same way - `+e/strike #3=alchemist's fire`
- and one is spent whatever happens: its persistent damage burns on a hit, and its splash lands on the
target even on a miss, though not a critical one. Who else stands in the splash is the GM's to say.
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
    +e/cast heal=#2/actions 2
A spell that can be cast more than one way takes the way you name: `/actions 2` for Heal's two-action
form, which heals more at range, or a word of the variant's name - `/silver` for silver Needle Darts.
A save that is not basic deals what the spell's own text says for each outcome; where it says nothing
about the damage, the room is shown the damage for the GM to settle.

## Circumstances

`flanking` - The target is off-guard to you: -2 AC.
`range <n>` - Which range increment the target is in: -2 for each past the first. Past the sixth, a
ranged attack cannot reach.
`<number>` - The DC, for an action with no target: `+e/act balance/18`.
Anything else is a circumstance the rules may ask about: `unintelligible`, a skill for Aid, a variant
like `stabilize`.

`silver`, `cold iron`, `holy`, `magical` and the like - What your weapon is made of or carries, which
the game cannot see. A creature weak to it takes more, and a resistance that excepts it does not apply:
`+e/strike #3=longsword/cold iron`.

## Holding and being held

A creature that grabs you holds you, and `+e/view` says who. While you are held:

- Grabbed or restrained, you are immobilized: an action that moves you is refused.
- Grabbed, anything that takes your hands - Interact, most spells - rolls a DC 5 flat check first, and
  is lost on a 4 or less. A spell lost this way is not spent.
- Restrained, you can do nothing with the attack or manipulate trait but Escape or Force Open.
- `+e/act escape` is against whoever holds you, without naming it.
- The hold ends when its turn says, when you Escape, or when whoever holds you drops.

Swallowed or engulfed, you are inside the creature: grabbed there with no end to it, slowed, and
taking its damage at the end of each of your turns. It is off-guard to you. A single blow of piercing
or slashing damage as great as its Rupture value cuts you out, and so does an Escape.

## Afflictions

A venom, a disease or a curse has stages. You save as you catch it - a failure is stage 1, a critical
failure stage 2 - and again at the end of your turn when a stage counted in rounds has had its time:
down a stage for a success, two for a critical success, up one for a failure, two for a critical
failure. Below stage 1 you are free of it. What a stage does to you is yours while you are at it, and
`+e/view` names the affliction beside each condition it gave you. Your turn's reminder says when a
save is due.

## What happens

A consequence the action states outright happens: a successful Trip knocks the target prone, a
Demoralize leaves them frightened.

    Aria uses Trip on Goblin Warrior #3: Athletics 23 (15 +8) vs Reflex DC 17 - success.
      Goblin Warrior #3 is now Prone.

## Taking it back

Every change in an encounter goes on its history, and the GM can take changes back and put them back,
one at a time. Nothing is rolled again: putting a change back puts back what happened.

`+e/undo` - The GM takes back the last change.
`+e/redo` - The GM puts back the change they last took back. Anything new that happens first ends it.
`+e/history [<encounter id>]` - Every change in the encounter, and where undo and redo stand.

An encounter's history ends with it: once it has ended, nothing in it can be taken back.

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

Concealment is set on the target for everyone, where the rules make it a matter of who is looking: a
creature hidden from one character can be in plain sight of another who has darkvision. When that
matters, leave the target's concealment unset and let the one it is hidden from say so for their own
attack - the GM or a trusted player can add `/hidden` to a single roll.

## For the GM

`+e/trust <name>`, `+e/untrust <name>` - Who may set cover and concealment. Trust lasts the encounter.
`+e/as <combatant>=<act|strike|cast|enter|leave> <what>` - Act for a creature, or anyone in the
encounter, with the same commands:
    +e/as #3=strike aria
    +e/as #3=strike aria=shortbow/range 2
    +e/as #5=act demoralize=aria
    +e/as #6=cast fear=aria
A creature's own abilities are used by name: `+e/as #3=act goblin scuttle`. Its abilities' rules
apply by themselves - a bonus to its saves, extra damage on a Strike, fast healing, an aura to place
with `+e/as #3=enter <aura>=<ids>`.
An ability whose words say what it deals and the save against it - a Constrict, a breath weapon - rolls
each target's save and deals the damage, basic: `+e/as #6=act magma breath=#1,#2,aria`. What else its
words say is yours to apply.

Where a creature's Strike lists Grab, Knockdown or Push, a hit says so and names the command:
`+e/as #3=act knockdown=#1`. Each is a Grapple, Trip or Shove of its own that neither takes nor adds
to the multiple attack penalty; the Improved form is a free action.

`+e/option <combatant>=<option>[/on|off|default]` - A circumstance a creature's own rules declare, such
as Air Scamp's fast healing only in open air. Each is on until you switch it off. With no option
named, lists them.
A creature's turn reminder, and its hit points after it is hurt, go to you alone.

## What you carry

As you enter an encounter, it takes a copy of what you carry: your gear, what you wear, wield and have
invested, and your money. Everything in the encounter works from that copy - your sheet there, your
Strikes and AC, what you use - so what you buy or sell outside meanwhile is no part of it.

`+e/gear [<who>]` - What you carry in the encounter here.
`+e/use <category>=<number>[/<use>]` - Use an item you carry there: drink a potion, spend a charge.
`+e/use consumables=<number>[/<who>]` - Drink a potion, elixir or mutagen, or give it to someone else in
the fight. A healing potion heals by its dice - vitality heals the living, and does nothing for the
undead - and an elixir or mutagen puts its effect on whoever takes it.
`+e/equip <category>=<number>` - Draw a weapon, put on armour, strap on a shield.
`+e/unequip <category>=<number>` - Stow it again.

`+e/loot <who>=<consumable>[/<quantity>]` - Staff, and the trusted GMs an admin has named, give someone a
consumable from the catalogue, for this encounter. An encounter's own GM does not give things out.

The numbers are the ones `+e/gear` shows. When the encounter ends, the consumables you used of your own
come off your own inventory. The rest of the copy - your money, and anything the encounter gave you -
stays with the encounter. An encounter that carries on from another carries its copy on.
