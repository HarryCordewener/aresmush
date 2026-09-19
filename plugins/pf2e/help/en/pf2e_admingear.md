---
toc: Pathfinder Second Edition - Admin
summary: Admin commands for other inventory and gear functions.
aliases:
- pf2estaff_inv
- pf2eadmin_gear
- pf2eadmin_inventory
---

# Pathfinder 2E -- Admin Commands for Inventory and Gear
Game admins and those they designate can make some modifications to characters' inventories. 

### Etching runes
**Commands**:
`etch/potency <character>=<category>/<item number>/<potency level>`
`etch/striking <character>=weapons/<item number>/<striking level>`
`etch/resilient <character>=armor/<item number>/<resilient level>`
`etch/property <character>=<category>/<item number>/<rune name>`

**Key**:
`<character>`: The character's name.
`<category>`: `weapons` or `armor`. Case-sensitive.
`<item number>`: The number of the item in the character's inventory.
`<potency level>`: The level of the Potency rune, as a number. Acceptable values: 0-3
`<striking level>`: The level of the Striking rune, as a number. Acceptable values: 0-3
`<resilient level>`: The level of the Resilient rune, as a number. Acceptable values: 0-3
`<rune name>`: The name of a property rune, as `browse runes` lists it - `Flaming`, `Ghost Touch`,
`Keen`. A name that is not one of those is refused, because a rune the catalogue does not have would
do nothing.

To take a property rune off an item, repeat the command that added it.

A property rune does what its catalogue entry says: a *flaming* rune adds 1d6 fire to that weapon's
damage and 1d10 persistent fire on a critical hit, and a *keen* rune turns a natural 19 into a
critical hit. An item holds as many property runes as its Potency rune is worth, so a rune that will
not fit wants a higher Potency rune first. Armour runes go on armour and weapon runes on weapons;
`browse runes` says which is which.