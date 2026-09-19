#!/usr/bin/env python3
"""What a spell does when it is cast at someone, from Foundry's spells.

Our spell catalogue (`pf2e_spells_*.yml`) describes a spell for a player to read and for a caster to
prepare. Casting one at a target needs what Foundry holds as data beside the prose: the defence it is
against - a save, basic or not, or AC for a spell attack - its damage and how that grows as it is
heightened, and its area. Those are written to `pf2e_spell_mechanics.yml`, keyed by the spell's name.

What a save's outcome does beyond damage is in the prose: Fear's failure leaves the target Frightened 2.
The prose links the condition it means (`@UUID[...conditionitems...]{Frightened 2}`), and the paragraph it
sits in says which outcome it is, so each outcome's conditions and effects are read from there. Every
outcome of a save happens to whoever rolled it, which is what makes the link enough.

Usage: scripts/import_foundry_spells.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_npcs as npcs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_spell_mechanics.yml'

OUTCOMES = {'Critical Success': 'criticalSuccess', 'Success': 'success', 'Failure': 'failure',
            'Critical Failure': 'criticalFailure'}
PARAGRAPH = re.compile(r'<strong>(Critical Success|Critical Failure|Success|Failure)</strong>(.*?)(?=<strong>(?:Critical Success|Critical Failure|Success|Failure)</strong>|<hr|</p>\s*<p><strong>Heightened|\Z)',
                       re.S)
LINK = re.compile(r'@UUID\[Compendium\.pf2e\.([\w-]+)\.Item\.[^\]]+\]\{([^}]+)\}')

# How long something an outcome leaves lasts, counted from the caster's turn: to the end or start of
# their next, or a number of rounds, which ends as their turn starts that many rounds on. A minute is
# ten rounds.
UNTIL = [(re.compile(r'until the end of (?:your|the caster\'s) next turn', re.I), lambda _: 'next-turn-end'),
         (re.compile(r'until the start of (?:your|the caster\'s) next turn', re.I), lambda _: 'next-turn-start'),
         (re.compile(r'for (\d+) rounds?', re.I), lambda found: f'rounds:{found.group(1)}'),
         (re.compile(r'for (\d+) minutes?', re.I), lambda found: f'rounds:{int(found.group(1)) * 10}')]


def effects_in(effects_text):
    """What one outcome's paragraph leaves on the one who rolled: each condition it links, at the value
    its label gives, and each effect. A duration belongs to the condition it directly follows."""
    found = []
    durations = sorted((match.start(), key(match)) for pattern, key in UNTIL for match in pattern.finditer(effects_text))
    links = list(LINK.finditer(effects_text))

    for index, link in enumerate(links):
        pack, label = link.groups()
        following = links[index + 1].start() if index + 1 < len(links) else len(effects_text)
        # Only a duration straight after the condition: "frightened 3 and fleeing for 1 round" puts the
        # round on the fleeing, which the text names without linking.
        until = next((key for at, key in durations
                      if link.end() <= at < following and not re.search(r'\band\b|,', effects_text[link.end():at])),
                     None)

        if pack == 'conditionitems':
            named = re.match(r'(.+?)(?:\s+(\d+))?\Z', label.strip())
            one = {'condition': named.group(1).strip().title().replace('Off-guard', 'Off-Guard')}
            if named.group(2):
                one['value'] = int(named.group(2))
            if until:
                one['until'] = until
            found.append(one)
        elif pack in ('spell-effects', 'other-effects', 'feat-effects', 'equipment-effects'):
            found.append({'effect': label.strip()})

    return found


def outcomes_of(description):
    out = {}

    for label, text in PARAGRAPH.findall(description or ''):
        held = effects_in(text)
        if held:
            out[OUTCOMES[label]] = held

    return out


def damage_of(system):
    return [{'formula': one.get('formula'), 'type': one.get('type'), 'category': one.get('category'),
             'kinds': one.get('kinds') or ['damage']}
            for one in (system.get('damage') or {}).values() if one.get('formula')]


def heightening_of(system, damage_keys):
    held = system.get('heightening') or {}

    if held.get('type') == 'interval':
        per = [held.get('damage', {}).get(key) for key in damage_keys]
        if any(per):
            return {'interval': held.get('interval', 1), 'damage': per}
    elif held.get('type') == 'fixed':
        levels = {}
        for rank, change in (held.get('levels') or {}).items():
            damage = (change or {}).get('damage') or {}
            formulas = [(damage.get(key) or {}).get('formula') for key in damage_keys]
            if any(formulas):
                levels[str(rank)] = formulas
        if levels:
            return {'fixed': levels}

    return None


def mechanics_of(doc):
    system = doc['system']
    traits = (system.get('traits') or {}).get('value') or []
    defense = system.get('defense') or {}
    save = defense.get('save') if isinstance(defense, dict) else None
    damage_keys = [key for key, one in (system.get('damage') or {}).items() if one.get('formula')]

    entry = {'rank': 0 if 'cantrip' in traits else (system.get('level') or {}).get('value', 1),
             'traits': traits}

    # How long it takes to cast: `2`, `1 to 3`, `reaction`, `10 minutes`.
    time = (system.get('time') or {}).get('value')
    if time:
        entry['time'] = str(time)
    if 'attack' in traits:
        entry['attack'] = True
    if save and save.get('statistic'):
        entry['save'] = save['statistic']
        entry['basic'] = bool(save.get('basic'))

    damage = damage_of(system)
    if damage:
        entry['damage'] = damage
        heightened = heightening_of(system, damage_keys)
        if heightened:
            entry['heightening'] = heightened

    area = system.get('area')
    if isinstance(area, dict) and area.get('value'):
        entry['area'] = f"{area.get('value')}-foot {area.get('type')}"
    for field in ('target', 'range'):
        value = (system.get(field) or {}).get('value')
        if value:
            entry[field] = value

    outcomes = outcomes_of((system.get('description') or {}).get('value'))
    if outcomes:
        entry['outcomes'] = outcomes

    return entry


def rendered(entries):
    lines = ['---', 'pf2e_spell_mechanics:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {json.dumps(name, ensure_ascii=False)}:')
        for field, held in entry.items():
            lines.append(f'    {field}: {json.dumps(held, ensure_ascii=False)}')

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    entries = {}

    for path, body in npcs.blobs(args.checkout):
        if not path.startswith('packs/pf2e/spells/'):
            continue

        doc = json.loads(body)

        if doc.get('type') == 'spell' and isinstance(doc.get('system'), dict):
            entries[doc['name']] = mechanics_of(doc)

    if args.write:
        open(os.path.join(CONFIG, OUT), 'w').write(rendered(entries))

    print('written' if args.write else 'dry run')
    print(f"  {len(entries)} spells: {sum('save' in one for one in entries.values())} with a save, "
          f"{sum('attack' in one for one in entries.values())} an attack, "
          f"{sum('damage' in one for one in entries.values())} damage, "
          f"{sum('outcomes' in one for one in entries.values())} leaving conditions or effects")


if __name__ == '__main__':
    main()
