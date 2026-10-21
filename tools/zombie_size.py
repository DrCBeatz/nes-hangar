"""Exact radial size boundaries and a small near-distance hysteresis band.

Artwork remains pre-scaled; runtime only selects an existing size. Squared
Q8.8 thresholds avoid adding a square root to the 6502 renderer.
"""
from fractions import Fraction
import json
from pathlib import Path

NEAR_WIDTH = 24
MARGIN_Q8 = 32  # one eighth of a world unit on each side of the boundary


def ceiling(value):
    return -(-value.numerator // value.denominator)


def write_assets(output, sizes):
    output = Path(output)
    widths = [width for width, height in sizes]
    assert all(height == width * 2 for width, height in sizes)
    assert widths == sorted(set(widths)) and widths[-1] == 32
    near = widths.index(NEAR_WIDTH)
    distances = [Fraction(131072, a + b) for a, b in zip(widths, widths[1:])]
    thresholds = [ceiling(distance * distance) for distance in distances]
    grow = [ceiling((d - MARGIN_Q8) ** 2) for d in distances[near:]]
    shrink = [ceiling((d + MARGIN_Q8) ** 2) for d in distances[near:]]
    assert all(0 < g < t < s < 2**32 for g, t, s in zip(grow, thresholds[near:], shrink))
    assert all(distances[i] - distances[i + 1] > 2 * MARGIN_Q8
               for i in range(near, len(distances) - 1))
    lines = ['; Generated from actual zombie artwork widths. Do not hand-edit.',
             f'ZOMBIE_NEAR_SIZE = {near}',
             f'ZOMBIE_SIZE_MARGIN_Q8 = {MARGIN_Q8}']
    def table(label, values):
        for byte in range(4):
            lines.append(label + str(byte) + ': .byte ' + ','.join(
                '$%02X' % ((value >> (8 * byte)) & 255) for value in values))
    table('zombie_distance_threshold', thresholds)
    # The fixed bank has room for these read-only comparison tables. Avoid
    # spending the last common-window bytes copied into every switched bank.
    lines += ['.pushseg', '.segment "CODE"']
    table('zombie_grow_threshold', grow)
    table('zombie_shrink_threshold', shrink)
    lines += ['.popseg']
    (output / 'zombie-size.inc').write_text('\n'.join(lines) + '\n')
    report = dict(widths=widths, nearSize=near, marginQ8=MARGIN_Q8,
                  marginWorldUnits=MARGIN_Q8 / 256,
                  thresholdsSquaredQ8=thresholds,
                  growThresholdsSquaredQ8=grow, shrinkThresholdsSquaredQ8=shrink,
                  nearestDistances=[float(d / 256) for d in distances],
                  growDistances=[float(d / 256) - MARGIN_Q8 / 256 for d in distances[near:]],
                  shrinkDistances=[float(d / 256) + MARGIN_Q8 / 256 for d in distances[near:]],
                  policy='Living actor only; history keyed by immutable render epoch. '
                         'New actors and distant sizes choose nearest immediately; '
                         'near sizes retain their previous tier within a +/-1/8 unit band.')
    (output / 'zombie-size.json').write_text(json.dumps(report, indent=2) + '\n')
    return report
