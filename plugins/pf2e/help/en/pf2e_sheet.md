---
toc: Pathfinder Second Edition
summary: Pathfinder 2E sheets and sheet sections.
aliases:
- sheet
---

# Pathfinder 2E Sheets

`sheet`: Views your own sheet.
`sheet <name>`: Views someone else's sheet. Depending on your game configuration and on the other player's setting, this may or may not be permitted.
`sheet/<section>`: Views <section> of your sheet. See Valid Sections below.
`sheet/<section> <name>`: Views <section> of <name>'s sheet. Depending on your game configuration and on the other player's setting, this may or may not be permitted.
`csheet` and `csheet <name>`: Alias for `sheet/combat`.
`sheet/why <figure>`: Shows the arithmetic behind one number on your sheet - what it starts from, and every bonus and penalty that reached it. A modifier the stacking rules switched off is listed too, marked, so you can see that a new item changed nothing because you already had a better bonus of the same type. Bonuses that apply only while you are doing something in particular are listed separately, with what each one needs; see `help roll` for how to name it. Figures: `hp`, `ac`, `speed`, `perception`, a save (`fortitude`, `reflex`, `will`), `class dc`, or a skill or lore by name.
`sheet/why <figure>=<name>`: The same for someone else's sheet, subject to the same permissions as `sheet <name>`.
`sheet/option` (or `sheet/options`): Lists the circumstances your gear and feats offer, and which are on. Some items work only while a feature of theirs is active - a Clandestine Cloak hides you while its own magic is running, at the cost of being harder to talk to - and these are on by default, so an item you are wearing does what it says.
`sheet/option <name>`: Turns one off, or back on.
`sheet/option <name>=off` and `=on`: Says which, rather than flipping it.
`sheet/option <name>=default`: Hands it back to whatever offers it.
`sheet/option <name>=<value>`: Some circumstances are a choice rather than a switch - a gem twisted to frost rather than flame, a signet set to Fortitude rather than Reflex. `sheet/option` lists what each one can be set to.
`sheet/show`: Shows what permissions you have granted to your sheet.
`sheet/show <name>[=<section>]`: Shows optional <section> of your sheet to <name>. Depending on your game configuration, this command may have no effect.
`sheet/unshow <name>`: Ends showing of all sections of your sheet to <name>. Depending on your game configuration, this command may have no effect.

## Valid Sections

The following sections are valid switches for this command.

* **info** or **top**: Shows basic character information.
* **ability**: Shows ability scores and modifiers.
* **combat**: Shows derived stats, AC, to-hit, attacks and their bonuses, and lists feats that may apply in combat.
* **features**: Shows class-specific features gained from your class and dedication archetypes.
* **feats**: Shows general and skill feats.
* **languages**: Shows known languages.
* **magic**: Shows focus spells and spells per-day / remaining for spellcasting classes.
* **skills**: Shows skills and their modifiers.
