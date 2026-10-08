"""Foundry's roll formulas, in a player's prose, as words.

A description says what an ability deals with the formula Foundry rolls for it - "takes
ternary(gte(@actor.level, 18), 7, ternary(gte(@actor.level, 15), 6, 5))d6 acid damage" - which only
Foundry can read. `in_words` finds each such formula in a text and writes it the way the book does:

    ternary(gte(@actor.level, 18), 7, ...)d6     5d6 (6d6 at 15th level, 7d6 at 18th level)
    (@item.rank)d6                               (1d6 per spell rank)
    (ceil(@actor.level/2))d8                     (1d8 per 2 levels, rounded up)
    (1d6 + @actor.level + @actor...int.mod)      (1d6 + your level + your Intelligence modifier)

A formula of one level or rank is worked out at every level or rank there is and described by how its
value changes: a few steps are listed, a steady climb is a rate. Anything else is read out term by
term. A text with no formula in it comes back as it was.
"""

import math
import re


# What a reference is, said to the player whose ability it is.
ABILITIES = {'str': 'Strength', 'dex': 'Dexterity', 'con': 'Constitution', 'int': 'Intelligence',
             'wis': 'Wisdom', 'cha': 'Charisma'}

# The references a formula can be worked out over, and the range of each: a character's level, an
# item's or effect's level, a spell's rank.
SCALES = {
    '@actor.level': {'domain': range(1, 21), 'unit': ('level', 'levels'), 'at': lambda v: f'{ordinal(v)} level'},
    '@item.level': {'domain': range(1, 21), 'unit': ('level', 'levels'), 'at': lambda v: f'level {v}'},
    '@item.rank': {'domain': range(1, 11), 'unit': ('spell rank', 'spell ranks'), 'at': lambda v: f'rank {v}'},
}

FUNCTIONS = {'ternary', 'gte', 'gt', 'lte', 'lt', 'eq', 'btwn', 'match', 'when', 'max', 'min', 'floor',
             'ceil', 'clamp', 'round', 'abs'}

# A rolled formula's own options after it, and a bracket naming its damage type from a flag.
TRAILING = re.compile(r'(?:\[[^\]\s]*@[^\]]*\])?(?:\|[\w:.-]+)*')


def ordinal(n):
    suffix = 'th' if 10 <= n % 100 <= 20 else {1: 'st', 2: 'nd', 3: 'rd'}.get(n % 10, 'th')
    return f'{n}{suffix}'


# ---------------------------------------------------------------------------------------------------
# Reading a formula

TOKEN = re.compile(r'\s*(?:(?P<num>\d+(?:\.\d+)?)|(?P<ref>@[\w.]+)|(?P<name>[A-Za-z_]\w*)|(?P<op>[-+*/(),]))')


class Unreadable(Exception):
    pass


class Parser:
    """A recursive descent over Foundry's formula grammar, from `start` in `text`, as far as a formula
    goes. `end` is where it stopped."""

    def __init__(self, text, start):
        self.text = text
        self.at = start
        self.end = start

    def peek(self):
        found = TOKEN.match(self.text, self.at)
        if not found:
            return None, None
        kind = found.lastgroup
        return kind, found.group(kind)

    def take(self):
        found = TOKEN.match(self.text, self.at)
        self.at = found.end()
        self.end = self.at
        return found.lastgroup, found.group(found.lastgroup)

    def expect(self, op):
        kind, value = self.peek()
        if kind != 'op' or value != op:
            raise Unreadable(op)
        self.take()

    def expr(self):
        node = self.term()
        while True:
            kind, value = self.peek()
            if kind == 'op' and value in '+-':
                saved = self.at, self.end
                self.take()
                try:
                    node = (value, node, self.term())
                except Unreadable:
                    self.at, self.end = saved
                    return node
            else:
                return node

    def term(self):
        node = self.dice()
        while True:
            kind, value = self.peek()
            if kind == 'op' and value in '*/':
                self.take()
                node = (value, node, self.dice())
            else:
                return node

    def dice(self):
        node = self.unary()
        # `(…)d6`, `2d6`, `ceil(x)d8`, `d((2+2*x))`: the die follows straight on.
        if self.text.startswith('d', self.at) and (self.at + 1 < len(self.text)) and \
                (self.text[self.at + 1].isdigit() or self.text[self.at + 1] == '('):
            self.at += 1
            node = ('d', node, self.unary())
            self.end = self.at
        return node

    def unary(self):
        kind, value = self.peek()
        if kind == 'op' and value == '-':
            self.take()
            return ('neg', self.unary())
        return self.primary()

    def primary(self):
        kind, value = self.peek()
        if kind == 'num':
            self.take()
            # `2d6` reads as the number and then its die.
            return ('num', float(value) if '.' in value else int(value))
        if kind == 'ref':
            self.take()
            return ('ref', value)
        if kind == 'name' and value in FUNCTIONS:
            self.take()
            self.expect('(')
            args = [self.expr()]
            while True:
                kind, value2 = self.peek()
                if kind == 'op' and value2 == ',':
                    self.take()
                    args.append(self.expr())
                    continue
                break
            self.expect(')')
            return ('call', value, args)
        if kind == 'op' and value == '(':
            self.take()
            node = self.expr()
            self.expect(')')
            return node
        raise Unreadable(value)


def refs_of(node):
    if node[0] == 'ref':
        return {node[1]}
    if node[0] == 'num':
        return set()
    if node[0] == 'call':
        return set().union(*(refs_of(one) for one in node[2]))
    return set().union(*(refs_of(one) for one in node[1:]))


def calls_in(node):
    if node[0] == 'call':
        return True
    if node[0] in ('num', 'ref'):
        return False
    return any(calls_in(one) for one in node[1:] if isinstance(one, tuple))


# ---------------------------------------------------------------------------------------------------
# Working it out

def value(node, bound):
    kind = node[0]
    if kind == 'num':
        return node[1]
    if kind == 'ref':
        if node[1] not in bound:
            raise Unreadable(node[1])
        return bound[node[1]]
    if kind == 'neg':
        return -value(node[1], bound)
    if kind == 'd':
        raise Unreadable('dice')
    if kind in '+-*/':
        left, right = value(node[1], bound), value(node[2], bound)
        return {'+': left + right, '-': left - right, '*': left * right,
                '/': left / right if right else 0}[kind]
    name, args = node[1], node[2]
    if name == 'when':
        raise Unreadable('when')
    if name == 'match':
        for case in args:
            if case[0] == 'call' and case[1] == 'when':
                if len(case[2]) == 1:
                    return value(case[2][0], bound)
                if value(case[2][0], bound):
                    return value(case[2][1], bound)
            else:
                return value(case, bound)
        return 0
    if name == 'ternary':
        return value(args[1], bound) if value(args[0], bound) else value(args[2], bound)
    numbers = [value(one, bound) for one in args]
    return {'gte': lambda: numbers[0] >= numbers[1], 'gt': lambda: numbers[0] > numbers[1],
            'lte': lambda: numbers[0] <= numbers[1], 'lt': lambda: numbers[0] < numbers[1],
            'eq': lambda: numbers[0] == numbers[1], 'btwn': lambda: numbers[1] <= numbers[0] <= numbers[2],
            'max': lambda: max(numbers), 'min': lambda: min(numbers),
            'floor': lambda: math.floor(numbers[0]), 'ceil': lambda: math.ceil(numbers[0]),
            'round': lambda: round(numbers[0]), 'abs': lambda: abs(numbers[0]),
            'clamp': lambda: max(numbers[0], min(numbers[1], numbers[2]))}[name]()


def whole(number):
    return int(number) if float(number).is_integer() else number


# ---------------------------------------------------------------------------------------------------
# Saying it

def described(count, scale, die=None):
    """How a value of one level or rank changes over its range, as words: one number, a few steps, or
    a rate. `die` is the die the value counts, if it counts one."""
    shown = (lambda n: f'{whole(n)}{die}') if die else (lambda n: f'{whole(n)}')
    points = [(v, count({scale['ref']: v})) for v in scale['domain']]
    points = [(v, n) for v, n in points if n > 0] or points

    distinct = []
    for v, n in points:
        if not distinct or distinct[-1][1] != n:
            distinct.append((v, n))

    if len(distinct) == 1:
        return shown(distinct[0][1]), False

    one, many = scale['unit']

    # A steady rate - so many per level or rank, or per so many of them - from nothing, from a base, or
    # from so many levels or ranks in.
    for per in (1, 2, 3, 4, 5):
        for rounding, word in ((math.floor, ''), (math.ceil, ', rounded up')):
            rate = steady(points, lambda v: rounding(v / per))
            if not rate:
                continue
            each, base = rate
            unit = one if per == 1 else f'{per} {many}'
            if base == 0:
                return f'{shown(each)} per {unit}{word}', True
            if base > 0:
                return f'{shown(base)}, plus {shown(each)} per {unit}{word}', True
            if per == 1 and (-base) % each == 0:
                return f'{shown(each)} per {one} above {whole(-base // each)}', True

    if len(distinct) <= 6:
        base = shown(distinct[0][1])
        steps = ', '.join(f'{shown(n)} at {scale["at"](v)}' for v, n in distinct[1:])
        return f'{base} ({steps})', False

    # A climb by the same amount every so many levels.
    rises = [(v, n - m) for (v, n), (_, m) in zip(distinct[1:], distinct)]
    gaps = {b[0] - a[0] for a, b in zip(rises, rises[1:])}
    amounts = {amount for _, amount in rises}
    if len(gaps) == 1 and len(amounts) == 1:
        gap, amount = gaps.pop(), amounts.pop()
        unit = one if gap == 1 else f'{gap} {many}'
        return f'{shown(distinct[0][1])}, and {shown(amount)} more every {unit} from {scale["at"](rises[0][0])}', True

    return f'{shown(distinct[0][1])}, more at higher {many}', True


def steady(points, step):
    """`(each, base)` where every point is `base + each * step(v)`, each a positive whole number."""
    first = next(((v, n) for v, n in points if step(v) != step(points[0][0])), None)
    if not first:
        return None
    each = (first[1] - points[0][1]) / (step(first[0]) - step(points[0][0]))
    if each <= 0 or not float(each).is_integer():
        return None
    base = points[0][1] - each * step(points[0][0])
    if not all(n == base + each * step(v) for v, n in points):
        return None
    return int(each), whole(base)


def spoken(node):
    """A formula read out term by term, for one that does not hang on a single level or rank."""
    kind = node[0]
    if kind == 'num':
        return str(whole(node[1]))
    if kind == 'ref':
        return referred(node[1])
    if kind == 'neg':
        return f'-{spoken(node[1])}'
    if kind == 'd':
        # A flag's own dice: `(@actor.flags.….sneakAttackDamage.number)d(….faces)` is the sneak attack dice.
        if node[1][0] == 'ref' and node[2][0] == 'ref' and node[1][1].endswith('.number') and \
                node[2][1] == node[1][1][:-len('.number')] + '.faces':
            return referred(node[1][1]).replace(' damage', '') + ' dice'
        if node[1][0] != 'num' and node[2][0] == 'num':
            return f'd{whole(node[2][1])}s equal to {spoken(node[1])}'
        count = spoken(node[1])
        faces = spoken(node[2])
        count = count if node[1][0] == 'num' else f'({count})'
        faces = faces if node[2][0] == 'num' else f'({faces})'
        return f'{count}d{faces}'
    if kind in '+-':
        return f'{spoken(node[1])} {kind} {spoken(node[2])}'
    if kind == '*':
        return f'{spoken(node[1])} × {spoken(node[2])}'
    if kind == '/':
        numerator = spoken(node[1]) if node[1][0] in ('num', 'ref', 'call') else f'({spoken(node[1])})'
        if node[2] == ('num', 2):
            return f'half of {numerator}'
        return f'{numerator} ÷ {spoken(node[2])}'
    name, args = node[1], node[2]
    if name in ('floor', 'round'):
        return spoken(args[0])
    if name == 'ceil':
        return f'{spoken(args[0])}, rounded up'
    if name == 'max':
        return 'the greater of ' + ' and '.join(spoken(one) for one in args)
    if name == 'min':
        return 'the lesser of ' + ' and '.join(spoken(one) for one in args)
    raise Unreadable(name)


def referred(ref):
    if ref in SCALES and ref != '@item.rank':
        return 'your level' if ref == '@actor.level' else 'its level'
    if ref == '@item.rank':
        return "the spell's rank"
    ability = re.match(r'@actor\.(?:system\.)?abilities\.(\w+)\.mod\Z', ref)
    if ability:
        return f'your {ABILITIES.get(ability.group(1), ability.group(1))} modifier'
    if ref == '@item.badge.value':
        return 'its value'
    if ref == '@actor.hitPoints.value':
        return 'your Hit Points'
    if ref == '@item.system.damage.dice':
        return 'its weapon damage dice'
    last = ref.split('.')[-1] if not ref.endswith(('.number', '.faces', '.type', '.value')) else ref.split('.')[-2]
    return 'your ' + re.sub(r'(?<!^)(?=[A-Z])', ' ', last).lower()


def rendered(node, ranked=False):
    """A formula as words. `ranked` reads an item's level as a spell's rank, which is what it is in a
    spell's own text."""
    refs = refs_of(node)
    if ranked and '@item.level' in refs:
        node = renamed(node, '@item.level', '@item.rank')
        refs = refs_of(node)

    scaled = [one for one in refs if one in SCALES]
    if len(refs) == 1 and scaled:
        scale = dict(SCALES[scaled[0]], ref=scaled[0])
        if node[0] == 'd' and node[2][0] == 'num':
            text, wrap = described(lambda bound: value(node[1], bound), scale, f'd{node[2][1]}')
        elif node[0] != 'd' and not has_dice(node):
            text, wrap = described(lambda bound: value(node, bound), scale)
        else:
            text, wrap = spoken(node), True
        return f'({text})' if wrap else text

    if not refs:
        if has_dice(node):
            return spoken(node)
        return str(whole(value(node, {})))

    # One reference and nothing done to it reads as the words for it.
    if node[0] == 'ref':
        return spoken(node)

    return f'({spoken(node)})'


def has_dice(node):
    if node[0] == 'd':
        return True
    if node[0] in ('num', 'ref'):
        return False
    if node[0] == 'call':
        return any(has_dice(one) for one in node[2])
    return any(has_dice(one) for one in node[1:])


def renamed(node, old, new):
    if node[0] == 'ref':
        return ('ref', new) if node[1] == old else node
    if node[0] == 'num':
        return node
    if node[0] == 'call':
        return ('call', node[1], [renamed(one, old, new) for one in node[2]])
    return (node[0],) + tuple(renamed(one, old, new) for one in node[1:])


# ---------------------------------------------------------------------------------------------------
# Finding them in a text

STARTS = re.compile(r'(?<![\w@.])(?:\(|@|\d|(?:' + '|'.join(sorted(FUNCTIONS)) + r')\()')


# A plain roll's damage type named from a flag - `13d6[@item.flags.system.rulesSelections.breathWeapon]` -
# and a roll's options - `|shortLabel`, `|immutable|name:...` - which are for Foundry's roll card.
FLAG_TYPE = re.compile(r'(\d+d\d+)\[[^\]\s]*@[^\]]*\]')
OPTIONS = re.compile(r'\|(?:shortLabel|immutable|traits:[\w,-]+|name:[\w.:-]+)')


def in_words(text, ranked=False):
    """`text` with each formula in it written as words."""
    text = OPTIONS.sub('', FLAG_TYPE.sub(r'\1', text))
    out = []
    index = 0

    while index < len(text):
        found = STARTS.search(text, index)
        if not found:
            out.append(text[index:])
            break

        start = found.start()
        parsed = parse_at(text, start)

        if not parsed:
            out.append(text[index:start + 1])
            index = start + 1
            continue

        node, end = parsed
        trailing = TRAILING.match(text, end)
        try:
            words = rendered(node, ranked)
        except (Unreadable, ZeroDivisionError, TypeError, IndexError):
            out.append(text[index:start + 1])
            index = start + 1
            continue

        out.append(text[index:start])
        out.append(words)
        index = trailing.end()

    return WRAPPED_CATEGORY.sub(r'\1 \2', ''.join(out))


# A damage roll's own grouping around a category, `((your sneak attack dice) precision)`, which reads
# as the dice and the category.
WRAPPED_CATEGORY = re.compile(r'\(\(([^()]+)\) (precision|persistent|splash)\)')


def parse_at(text, start):
    """The formula that begins at `start`, if one does that a reader could not read as it stands: it
    names a reference or calls a function."""
    parser = Parser(text, start)
    try:
        node = parser.expr()
    except (Unreadable, AttributeError):
        return None

    if not (refs_of(node) or calls_in(node)):
        return None

    return node, parser.end
