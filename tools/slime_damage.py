"""Build cheap, conservative live-player hazard intervals for flat slime.

Each admitted unit cell is wholly contained in the closed source polygon.
This gives the player a small forgiving border instead of dealing damage on
gray pixels. Runtime checks the player's center and never reads the changing
map PRG bank. All geometry decisions below use exact rational arithmetic.
"""
from __future__ import annotations

from fractions import Fraction
import json
import math
from pathlib import Path

DAMAGE = 5
PERIOD = 60
X_BASE = 256
FLOOR = 2


def point_in_closed_polygon(polygon, x, z):
    inside = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        cross = (b[0]-a[0])*(z-a[1]) - (b[1]-a[1])*(x-a[0])
        if cross == 0 and min(a[0], b[0]) <= x <= max(a[0], b[0]) and min(a[1], b[1]) <= z <= max(a[1], b[1]):
            return True
        if (a[1] > z) != (b[1] > z):
            crossing = Fraction(a[0]) + Fraction((b[0]-a[0])*(z-a[1]), b[1]-a[1])
            if x < crossing:
                inside = not inside
    return inside


def segment_enters_open_cell(a, b, x, z):
    """Exact clipping; a boundary lying on the square edge is harmless."""
    lower, upper = Fraction(0), Fraction(1)
    for p, d, lo, hi in ((a[0], b[0]-a[0], x, x+1),
                          (a[1], b[1]-a[1], z, z+1)):
        if d == 0:
            if not lo < p < hi:
                return False
            continue
        first, last = sorted((Fraction(lo-p, d), Fraction(hi-p, d)))
        lower, upper = max(lower, first), min(upper, last)
    return lower < upper


def closed_cell_inside(polygon, x, z):
    """Independent containment proof, including concave boundary intrusions."""
    if not all(point_in_closed_polygon(polygon, u, v)
               for u, v in ((x, z), (x+1, z), (x+1, z+1), (x, z+1))):
        return False
    return not any(segment_enters_open_cell(a, b, x, z)
                   for a, b in zip(polygon, polygon[1:] + polygon[:1]))


def row_interval(polygon, z):
    """Use each integer-height slab's exact left/right envelope, no sampling."""
    middle = Fraction(2*z+1, 2)
    edges = []
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if min(a[1], b[1]) < middle < max(a[1], b[1]):
            def at(v, a=a, b=b):
                return Fraction(a[0]) + Fraction(b[0]-a[0], b[1]-a[1])*(v-a[1])
            edges.append((at(middle), at(z), at(z+1)))
    if not edges:
        return (0, 0)
    assert len(edges) == 2, (z, edges, 'Pool must have one horizontal interval')
    left, right = sorted(edges)
    first, end = math.ceil(max(left[1:])), math.floor(min(right[1:]))
    return (first, end) if first < end else (0, 0)


def tables(scene):
    pools = scene['slime']['pools']
    assert list(pools) == ['slime_west', 'slime_east']
    assert scene['slime']['height'] == FLOOR
    vertices = [v for p in pools.values() for v in p]
    assert all(isinstance(c, int) for v in vertices for c in v)
    z_min, z_end = min(v[1] for v in vertices), max(v[1] for v in vertices)
    assert 0 <= z_min < z_end <= 256
    assert all(X_BASE <= x < X_BASE+256 for x, _ in vertices)
    result = {}
    checked = admitted = 0
    for name, polygon in pools.items():
        rows = []
        x_min, x_end = min(v[0] for v in polygon), max(v[0] for v in polygon)
        for z in range(z_min, z_end):
            first, end = row_interval(polygon, z)
            safe = [x for x in range(x_min, x_end) if closed_cell_inside(polygon, x, z)]
            expected = list(range(first, end))
            assert safe == expected, (name, z, safe, expected)
            checked += x_end-x_min
            admitted += len(safe)
            rows.append((first-X_BASE, end-X_BASE) if safe else (0, 0))
        result[name] = rows
    return z_min, z_end, result, dict(exactRationalContainment=True,
        allAuthoredCellsChecked=checked, admittedHazardCells=admitted,
        singleIntervalPerPoolPerRow=True, damageOutsideGreen=False,
        cellRule='Entire closed unit cell inside source pool; player center selects cell',
        footprintRule='Player collision radius is not expanded into the hazard')


def write_assets(output, scene):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    z_min, z_end, rows, validation = tables(scene)
    text = ['; Generated conservative hazard cells; NMI reads fixed PRG only.',
            f'SLIME_DAMAGE = {DAMAGE}', f'SLIME_PERIOD = {PERIOD}',
            f'SLIME_FLOOR = {FLOOR}', f'SLIME_X_HIGH = {X_BASE//256}',
            f'SLIME_Z_MIN = {z_min}', f'SLIME_Z_END = {z_end}',
            '.export slime_west_first, slime_west_end, slime_east_first, slime_east_end',
            '.segment "CODE"']
    for pool, values in rows.items():
        for component, index in (('first', 0), ('end', 1)):
            text.append(f'{pool}_{component}:')
            data = [v[index] for v in values]
            text.extend(' .byte ' + ','.join(str(v) for v in data[i:i+16]) for i in range(0, len(data), 16))
    (output/'slime-damage-data.inc').write_text('\n'.join(text)+'\n')
    info = dict(damage=DAMAGE, periodNmi=PERIOD, firstDamageAfterConsecutiveNmi=PERIOD,
        timerResetOn=['safe ground', 'Start', 'death', 'exit completion'],
        floorHeight=FLOOR, xBase=X_BASE, zMinimum=z_min, zEndExclusive=z_end,
        tableBytes=4*(z_end-z_min), rows=rows, validation=validation)
    (output/'slime-damage-data.json').write_text(json.dumps(info, indent=2)+'\n')
    return info
