#!/usr/bin/env python3
"""Foundry's bestiaries, as creatures a GM can add to an encounter.

Every `npc` actor in their packs is a full stat block as data: its defences, its Strikes with their
bonuses and damage, its abilities, its spellcasting. An encounter needs those numbers to resolve an action
against a creature, and a GM acting for one needs its attacks, so each is read into
`game/bestiary/<pack>.yml`, with `game/bestiary/index.yml` saying which file holds each name.

They live outside `game/config` because there are six thousand of them: config is read whole at startup
and before every database spec, and a creature is only read when a GM names it.

What is kept is what play reads. The prose of an ability is kept, shortened, because a GM reads it to run
the ability; the lore of the creature is not.

Usage: scripts/import_foundry_npcs.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BESTIARY = os.path.join(ROOT, 'game', 'bestiary')
INDEX = 'index.yml'
ABILITY_TEXT = 500

SIZES = {'tiny': 'tiny', 'sm': 'small', 'med': 'medium', 'lg': 'large', 'huge': 'huge', 'grg': 'gargantuan'}
TYPES = {'action': 'action', 'reaction': 'reaction', 'free': 'free', 'passive': 'passive'}


def blobs(checkout):
    """Every JSON file in their packs, read in one pass through git rather than one process per file."""
    listed = subprocess.run(['git', '-C', checkout, 'ls-tree', '-r', 'HEAD', 'packs/pf2e'],
                            capture_output=True, text=True).stdout.splitlines()
    wanted = [(line.split()[2], line.split('\t', 1)[1]) for line in listed
              if line.endswith('.json') and not line.endswith('_folders.json')]

    batch = subprocess.Popen(['git', '-C', checkout, 'cat-file', '--batch'], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE)

    for sha, path in wanted:
        batch.stdin.write(f'{sha}\n'.encode())
        batch.stdin.flush()
        header = batch.stdout.readline().split()
        body = batch.stdout.read(int(header[2]))
        batch.stdout.read(1)

        yield path, body

    batch.stdin.close()
    batch.wait()


def titled(slug):
    return ' '.join(part.capitalize() for part in str(slug).split('-'))


def strike_of(item):
    system = item['system']
    rolls = system.get('damageRolls') or {}
    ranged = system.get('range') or {}
    traits = (system.get('traits') or {}).get('value') or []

    strike = {'name': item['name'], 'bonus': (system.get('bonus') or {}).get('value', 0),
              'damage': [[one.get('damage'), one.get('damageType'), one.get('category')]
                         for one in rolls.values() if one.get('damage')],
              'traits': traits}

    if isinstance(ranged, dict) and ranged.get('increment'):
        strike['range'] = ranged['increment']
    effects = (system.get('attackEffects') or {}).get('value') or []
    if effects:
        strike['effects'] = [titled(one) for one in effects]

    return strike


def ability_of(item):
    system = item['system']
    kind = ((system.get('actionType') or {}).get('value')) or 'passive'
    cost = (system.get('actions') or {}).get('value')

    ability = {'name': item['name'], 'type': TYPES.get(kind, 'passive'),
               'traits': (system.get('traits') or {}).get('value') or []}

    if cost:
        ability['cost'] = cost
    text = rules.plain((system.get('description') or {}).get('value'), ABILITY_TEXT)
    if text:
        ability['text'] = text

    return ability


def casting_of(item, spells):
    system = item['system']
    dc = system.get('spelldc') or {}
    own = [one for one in spells if (one['system'].get('location') or {}).get('value') == item['_id']]
    ranks = collections.defaultdict(list)

    for spell in own:
        location = spell['system'].get('location') or {}
        traits = (spell['system'].get('traits') or {}).get('value') or []
        rank = 0 if 'cantrip' in traits else (location.get('heightenedLevel') or
                                              (spell['system'].get('level') or {}).get('value') or 1)
        ranks[str(rank)].append(spell['name'])

    return {'name': item['name'], 'tradition': (system.get('tradition') or {}).get('value'),
            'type': (system.get('prepared') or {}).get('value'),
            'dc': dc.get('dc'), 'attack': dc.get('value'),
            'spells': {rank: sorted(set(names)) for rank, names in sorted(ranks.items(), key=lambda one: int(one[0]))}}


def npc_of(doc, pack):
    system = doc['system']
    attributes = system.get('attributes') or {}
    traits = system.get('traits') or {}
    items = doc.get('items') or []
    speed = attributes.get('speed') or {}

    npc = {'pack': pack,
           'level': ((system.get('details') or {}).get('level') or {}).get('value', 0),
           'size': SIZES.get((traits.get('size') or {}).get('value'), 'medium'),
           'rarity': traits.get('rarity', 'common'),
           'traits': traits.get('value') or [],
           'ac': (attributes.get('ac') or {}).get('value'),
           'hp': (attributes.get('hp') or {}).get('max'),
           'perception': (system.get('perception') or {}).get('mod'),
           'saves': {name: (held or {}).get('value') for name, held in (system.get('saves') or {}).items()},
           'abilities': {name: (held or {}).get('mod') for name, held in (system.get('abilities') or {}).items()},
           'speeds': {'land': speed.get('value', 0)}}

    for other in speed.get('otherSpeeds') or []:
        npc['speeds'][other.get('type')] = other.get('value')

    hp_details = (attributes.get('hp') or {}).get('details')
    if hp_details:
        npc['hp_details'] = hp_details
    senses = [one.get('type') for one in (system.get('perception') or {}).get('senses') or [] if one.get('type')]
    if senses:
        npc['senses'] = senses

    skills = {titled(name): (held or {}).get('base') for name, held in (system.get('skills') or {}).items()}
    skills.update({one['name']: ((one['system'].get('mod') or {}).get('value')) for one in items if one['type'] == 'lore'})
    if skills:
        npc['skills'] = skills

    immunities = [one.get('type') for one in attributes.get('immunities') or [] if one.get('type')]
    if immunities:
        npc['immunities'] = immunities
    for field in ('weaknesses', 'resistances'):
        held = {one.get('type'): one.get('value') for one in attributes.get(field) or [] if one.get('type')}
        if held:
            npc[field] = held

    strikes = [strike_of(one) for one in items if one['type'] == 'melee']
    if strikes:
        npc['strikes'] = strikes
    abilities = [ability_of(one) for one in items if one['type'] == 'action']
    if abilities:
        npc['actions'] = abilities

    spells = [one for one in items if one['type'] == 'spell']
    casting = [casting_of(one, spells) for one in items if one['type'] == 'spellcastingEntry']
    casting = [one for one in casting if one['dc'] or one['spells']]
    if casting:
        npc['spellcasting'] = casting

    return npc


def rendered(entries):
    lines = ['---']

    for name, entry in sorted(entries.items()):
        lines.append(f'{json.dumps(name, ensure_ascii=False)}:')
        for field, held in entry.items():
            lines.append(f'  {field}: {json.dumps(held, ensure_ascii=False)}')

    return '\n'.join(lines) + '\n'


def indexed(by_pack):
    """Which file holds each creature, with what a search filters on."""
    lines = ['---']

    for pack, entries in sorted(by_pack.items()):
        for name, entry in sorted(entries.items()):
            lines.append(f'{json.dumps(name, ensure_ascii=False)}: ' + json.dumps(
                {'pack': pack, 'level': entry['level'], 'traits': entry['traits']}, ensure_ascii=False))

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    by_pack = collections.defaultdict(dict)
    repeated = 0

    for path, body in blobs(args.checkout):
        if b'"type": "npc"' not in body and b'"type":"npc"' not in body:
            continue

        try:
            doc = json.loads(body)
        except json.JSONDecodeError:
            continue

        if doc.get('type') != 'npc' or not isinstance(doc.get('system'), dict):
            continue

        pack = path.split('/')[2]
        name = doc['name']

        # The same creature appears in more than one adventure; the first of its name is kept, and the
        # packs are read in order, so a bestiary's own copy wins over an adventure's.
        if any(name in held for held in by_pack.values()):
            repeated += 1
            continue

        by_pack[pack][name] = npc_of(doc, pack)

    if args.write:
        os.makedirs(BESTIARY, exist_ok=True)
        for old in os.listdir(BESTIARY):
            if old.endswith('.yml'):
                os.remove(os.path.join(BESTIARY, old))
        for pack, entries in by_pack.items():
            open(os.path.join(BESTIARY, f'{pack}.yml'), 'w').write(rendered(entries))
        open(os.path.join(BESTIARY, INDEX), 'w').write(indexed(by_pack))

    total = sum(len(one) for one in by_pack.values())
    print('written' if args.write else 'dry run')
    print(f'  {total} creatures in {len(by_pack)} packs; {repeated} repeats of a name already read')
    for pack, entries in sorted(by_pack.items(), key=lambda one: -len(one[1]))[:12]:
        print(f'  {len(entries):5d}  {pack}')


if __name__ == '__main__':
    main()
