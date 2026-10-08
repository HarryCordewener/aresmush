---
toc: Pathfinder Second Edition
summary: Exploring between fights - activities, Treat Wounds, and how a fight starts from it.
aliases:
- explore
- exploration
- exploring
---
# Pathfinder 2E - Exploring

Between fights the party explores: travelling, searching, recovering. An exploration is an encounter of
its own in the scene, without initiative or turns. What happens in it carries on into the fight that
starts from it, and a fight can be carried on into the next exploration, so wounds, spent spells and
used potions follow the party through the scene.

## For the GM

`+e/explore[=<encounter ID>]`: Starts an exploration in the scene, with you as its GM. Name an earlier
encounter - the fight just finished - and whoever was in it carries on as they left it.
`encounter` (`+e/start`): Started while the party is exploring, the exploration ends and the fight begins,
carrying on from it. Everyone exploring is in the fight at once, rolling initiative as their activity
has it. Add the creatures with `+e/add`.
`encounter/end <encounter ID>`: Ends a fight. Carry on exploring with `+e/explore=<encounter ID>`.
`+e/rest`: A night's rest, for an exploration as for a fight.

## For players

`+e/join`: Joins the exploration. There is no initiative to roll.
`+e/act <activity>`: What you do as you travel: one of Avoid Notice, Defend, Detect Magic, Follow the
Expert, Hustle, Investigate, Repeat a Spell, Scout or Search. `+e/view` shows what everyone is doing.
When a fight starts:
- Avoid Notice rolls Stealth for your initiative instead of Perception.
- Scout gives everyone else +1 to their initiative.
- Defend starts you with your shield raised.
- Anything else rolls Perception, as the GM named.

`+e/act treat wounds=<who>[/<DC>]`: Ten minutes of Medicine: DC 15, or 20, 30 or 40 for more healing.
A success heals 2d8, a critical success 4d8; a critical failure does 1d8 damage. It and anything else
that takes minutes is done while exploring, not in a fight.
`+e/refocus`, `+e/use consumables=<n>[/<who>]`, `+e/cast`: as in a fight.
`roll <skill>[/<DC>]`: Any other check the GM asks for - Perception to notice, Survival to track.
