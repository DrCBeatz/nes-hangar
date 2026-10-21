"""Two hand-authored walking poses for the E1M1 zombie soldier.

These are hand-authored indexed source pixels, not sampled world views or
extracted Doom assets.  Index zero is transparent; indices 1..3 are the black
outline/firearm, olive uniform, and pale face/hands.  Every proportional size
keeps the last opaque row on the feet baseline.  The renderer supplies position,
occlusion and hit state; this module supplies two fixed-size poses; animation never rescales the feet.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path


# A bareheaded, front-facing soldier with a slightly slumped stance. The rifle
# crosses the torso, with a pale hand supporting its barrel on the viewer's
# left and the trigger hand at the right. Paired dark eyes and an uneven mouth
# leave the face readable without adding a fourth opaque sprite color.
MASTER = (
    '......1111......',
    '.....133331.....',
    '.....133331.....',
    '....13133131....',
    '....13333331....',
    '.....131331.....',
    '......1331......',
    '....11133111....',
    '...1221222221...',
    '..122221122221..',
    '..122222222221..',
    '..122222222221..',
    '..121222221221..',
    '..123111112221..',
    '.11113311111111.',
    '.11111111113311.',
    '..122111111331..',
    '...1222222221...',
    '....12222221....',
    '....11111111....',
    '....12211221....',
    '....12211221....',
    '....12211221....',
    '....12211221....',
    '....12211221....',
    '....12111221....',
    '....11111111....',
    '....111..111....',
    '....111..111....',
    '...1111..1111...',
    '...1111..1111...',
    '..11111..11111..',
)

# Preserve eyes, rifle, hands and separated boots at the 8x16 size rather
# than allowing nearest-neighbor downsampling to remove the identifying marks.
DISTANT = (
    '..1111..',
    '..1331..',
    '..1331..',
    '..1311..',
    '.112211.',
    '.122221.',
    '.122221.',
    '11311111',
    '11111311',
    '..1111..',
    '..1221..',
    '..1221..',
    '..1221..',
    '..1111..',
    '.11..11.',
    '.11..11.',
)

# The two new long-range silhouettes are authored at their actual dimensions.
# A pale head, olive torso, dark firearm and separated boots take priority over
# tiny facial detail. The seven original size variants remain byte-identical.
VERY_DISTANT = (
    '.11.',
    '.33.',
    '1221',
    '1311',
    '1111',
    '.22.',
    '.11.',
    '1..1',
)
FAR = (
    '..11..',
    '.1331.',
    '.1311.',
    '.1221.',
    '122221',
    '131111',
    '111311',
    '.1221.',
    '.1221.',
    '.1111.',
    '.1..1.',
    '11..11',
)
NATIVE_DISTANCE_ART = {(4, 8): VERY_DISTANT, (6, 12): FAR, (8, 16): DISTANT}

# The head and rifle retain the established design. Opposite lead boots and
# a small supporting-hand change imply a step without lifting the whole actor.
# Both poses retain the same canvas, opaque bounds and bottom feet baseline.
WALK_A = MASTER[:24] + (
    '...122111221....',
    '...122111221....',
    '...1211.1111....',
    '...1111..111....',
    '...1111..111....',
    '..11111..1111...',
    '..11111..1111...',
    '..11111.........',
)
WALK_B = WALK_A[:14] + (
    '.11111331111111.',
    '.11111111133111.',
) + WALK_A[16:20] + tuple(row[::-1] for row in WALK_A[20:])
DISTANT_A = DISTANT[:10] + (
    '..1221..', '.12221..', '.12121..', '.11111..', '111..11.', '111.....',
)
FAR_A = FAR[:9] + ('11111.', '11..1.', '11....')
VERY_DISTANT_A = VERY_DISTANT[:6] + ('11.1', '11..')
POSE_MASTERS = (WALK_A, WALK_B)
POSE_NATIVE_ART = (
    {(4, 8): VERY_DISTANT_A, (6, 12): FAR_A, (8, 16): DISTANT_A},
    {(4, 8): VERY_DISTANT_A[:6] + tuple(row[::-1] for row in VERY_DISTANT_A[6:]),
     (6, 12): FAR_A[:9] + tuple(row[::-1] for row in FAR_A[9:]),
     (8, 16): DISTANT_A[:10] + tuple(row[::-1] for row in DISTANT_A[10:])},
)

SIZES = ((4, 8), (6, 12), (8, 16), (12, 24), (16, 32), (20, 40),
         (24, 48), (26, 52), (28, 56), (30, 60), (32, 64))
# The intermediate close-range tiers halve the 24-to-28 and 28-to-32 width steps. Existing
# sizes still sample the same master independently, preserving their pixels.
PALETTE_NES = (0x0F, 0x0F, 0x18, 0x37)
HIT_PALETTE_NES = (0x0F, 0x0F, 0x16, 0x30)
# Preview colors approximate the default emulator NES palette. Actual displayed
# color depends on the emulator's chosen palette; ROM bytes above are canonical.
PALETTE_RGB = ((37, 37, 42), (0, 0, 0), (112, 114, 0), (255, 217, 165))
HIT_PALETTE_RGB = ((37, 37, 42), (0, 0, 0), (180, 49, 32), (255, 255, 255))


def source_pixels(rows=MASTER):
    assert rows and len({len(row) for row in rows}) == 1
    return [[0 if value == '.' else int(value) for value in row] for row in rows]


def resize(pixels, width, height):
    """Palette-preserving nearest pixel-center sampling at a fixed aspect ratio."""
    old_height, old_width = len(pixels), len(pixels[0])
    assert width * old_height == height * old_width
    return [[pixels[min(old_height - 1, ((2 * y + 1) * old_height) // (2 * height))]
                   [min(old_width - 1, ((2 * x + 1) * old_width) // (2 * width))]
            for x in range(width)] for y in range(height)]


def encode_tile(pixels, left, top):
    """NES 2bpp tile; pixels outside the tight art width are transparent."""
    result = bytearray(16)
    height, width = len(pixels), len(pixels[0])
    for y in range(8):
        for x in range(8):
            value = pixels[top + y][left + x] if top + y < height and left + x < width else 0
            assert 0 <= value < 4
            result[y] |= (value & 1) << (7 - x)
            result[y + 8] |= ((value >> 1) & 1) << (7 - x)
    return bytes(result)


def decode_tile(pattern):
    assert len(pattern) == 16
    return [[((pattern[y] >> (7 - x)) & 1) | (((pattern[y + 8] >> (7 - x)) & 1) << 1)
             for x in range(8)] for y in range(8)]


def build_assets(pose=0):
    assert pose in (0, 1)
    master = source_pixels(POSE_MASTERS[pose])
    assert len(master) == 32 and all(len(row) == 16 for row in master)
    variants = []
    for index, (width, height) in enumerate(SIZES):
        native = POSE_NATIVE_ART[pose].get((width, height))
        pixels = source_pixels(native) if native is not None else resize(master, width, height)
        assert len(pixels) == height and all(len(row) == width for row in pixels)
        columns, rows = (width + 7) // 8, (height + 7) // 8
        patterns = [encode_tile(pixels, x, y) for y in range(0, height, 8)
                    for x in range(0, width, 8)]
        assert len(patterns) == columns * rows <= 32
        assert columns <= 4
        # Decode every emitted pattern independently, including padding, before
        # accepting it as the renderer's source for per-pixel occlusion masks.
        for tile_index, pattern in enumerate(patterns):
            left, top = (tile_index % columns) * 8, (tile_index // columns) * 8
            decoded = decode_tile(pattern)
            for y in range(8):
                for x in range(8):
                    expected = pixels[top + y][left + x] if top + y < height and left + x < width else 0
                    assert decoded[y][x] == expected
        opaque = [(x, y) for y, row in enumerate(pixels) for x, value in enumerate(row) if value]
        bounds = [min(x for x, _ in opaque), min(y for _, y in opaque),
                  max(x for x, _ in opaque), max(y for _, y in opaque)]
        assert bounds[3] == height - 1
        # Compact source format expected by the masked sprite compositor:
        # every row stores C bytes of low bits followed by C bytes of high bits.
        # The final column is zero-padded, but source rows stop at the actual
        # height. The compositor skips source reads for zero row masks and
        # supplies transparent output rows past the actual height.
        row_planes = bytearray()
        stored_rows = height
        for row in pixels:
            for plane in range(2):
                for column in range(columns):
                    row_planes.append(sum((((row[x] >> plane) & 1) << (7 - (x & 7)))
                                          for x in range(column * 8, min(width, (column + 1) * 8))))
        assert len(row_planes) == 2 * stored_rows * columns
        for y in range(stored_rows):
            offset = y * columns * 2
            for x in range(columns * 8):
                shift, column = 7 - (x & 7), x // 8
                decoded = ((row_planes[offset + column] >> shift) & 1) | \
                          (((row_planes[offset + columns + column] >> shift) & 1) << 1)
                assert decoded == (pixels[y][x] if x < width and y < height else 0)
        variants.append({'index': index, 'width': width, 'height': height,
                         'columns': columns, 'rows': rows, 'patternCount': len(patterns),
                         'storedRows': stored_rows, 'storedPlaneBytes': len(row_planes),
                         'opaqueBoundsInclusive': bounds, 'feetBaselineY': height - 1,
                         'pixels': pixels, 'patterns': patterns,
                         'raw': b''.join(patterns), 'rowPlanes': bytes(row_planes)})
    return variants


def _bytes(label, values):
    return label + ':\n .byte ' + ','.join('$%02X' % value for value in values) + '\n'


def _png(path, pixels, scale=1):
    height, width = len(pixels), len(pixels[0])
    payload = bytearray()
    for row in pixels:
        payload.extend((b'\0' + b''.join(bytes(pixel) * scale for pixel in row)) * scale)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' +
                     chunk(b'IHDR', struct.pack('>IIBBBBB', width * scale, height * scale, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(bytes(payload), 9)) + chunk(b'IEND', b''))


def previews(directory, variants, pose=0):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    gap, padding = 8, 8
    width = sum(v['width'] for v in variants) + gap * (len(variants) - 1) + padding * 2
    height = 64 + padding * 2
    image = [[PALETTE_RGB[0] for _ in range(width)] for _ in range(height)]
    left = padding
    for variant in variants:
        top = height - padding - variant['height']
        for y, row in enumerate(variant['pixels']):
            for x, value in enumerate(row):
                image[top + y][left + x] = PALETTE_RGB[value]
        left += variant['width'] + gap
    _png(directory / 'zombie-sizes-native.png', image)
    _png(directory / 'zombie-sizes-preview.png', image, 5)
    image = [[PALETTE_RGB[0] for _ in range(56)] for _ in range(40)]
    for left, palette in ((8, PALETTE_RGB), (32, HIT_PALETTE_RGB)):
        for y, row in enumerate(source_pixels(POSE_MASTERS[pose])):
            for x, value in enumerate(row):
                image[y + 4][x + left] = palette[value]
    _png(directory / 'zombie-normal-hit-native.png', image)
    _png(directory / 'zombie-normal-hit-preview.png', image, 8)


def write_assets(output, preview_dir=None):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    poses = [build_assets(pose) for pose in (0, 1)]
    variants = poses[0]
    assert all(len(pose) == len(SIZES) for pose in poses)
    for a, b in zip(*poses):
        for field in ('width', 'height', 'columns', 'rows', 'patternCount', 'storedRows', 'feetBaselineY', 'opaqueBoundsInclusive'):
            assert a[field] == b[field], (field, a[field], b[field])
        assert a['pixels'] != b['pixels']
    include = ('; Original zombie art; each row is C plane-0 bytes then C plane-1 bytes.\n'
               '; Source heights are tight; compositor blanks padded output rows without reading source.\n')
    include += 'ZOMBIE_VARIANT_COUNT = %d\nZOMBIE_MAX_PATTERNS = 32\n' % len(variants)
    for field, label in (('width', 'widths'), ('height', 'heights'), ('columns', 'cols'),
                         ('rows', 'rows'), ('patternCount', 'pattern_counts')):
        include += _bytes('zombie_' + label, [variant[field] for variant in variants])
    for part, operator in (('lo', '<'), ('hi', '>')):
        include += 'zombie_art_' + part + ':\n .byte ' + ','.join(
            operator + 'zombie_art_%d' % variant['index'] for variant in variants) + '\n'
    for part, operator in (('lo', '<'), ('hi', '>')):
        include += 'zombie_walk_art_' + part + ':\n .byte ' + ','.join(
            operator + 'zombie_walk_art_%d' % variant['index'] for variant in poses[1]) + '\n'
    include += _bytes('zombie_palette', PALETTE_NES)
    include += _bytes('zombie_hit_palette', HIT_PALETTE_NES)
    # Projection metadata stays mirrored while the raw pixel art is banked.
    include += '.pushseg\n.segment "ACTOR_ART"\n'
    for variant in variants:
        filename = 'zombie-art-%d.bin' % variant['index']
        (output / filename).write_bytes(variant['rowPlanes'])
        include += 'zombie_art_%d:\n .incbin "%s"\n' % (variant['index'], filename)
    for variant in poses[1]:
        filename = 'zombie-walk-art-%d.bin' % variant['index']
        (output / filename).write_bytes(variant['rowPlanes'])
        include += 'zombie_walk_art_%d:\n .incbin "%s"\n' % (variant['index'], filename)
    include += '.popseg\n'
    (output / 'zombie-assets.inc').write_text(include)
    report = {'origin': 'Original hand-authored zombie soldier; no extracted Doom artwork',
              'sourceWidth': 16, 'sourceHeight': 32, 'normalPalette': list(PALETTE_NES),
              'variantCount': len(variants),
              'hitPalette': list(HIT_PALETTE_NES), 'maxPatternsPerFrame': 32,
              'maxSpriteColumns': 4, 'feetBaseline': 'Last opaque pixel row',
              'normalSpritePalette': 2, 'hitSpritePalette': 2,
              'hitFlashUsesLivePaletteReplacement': True,
              'hitFlashPaletteExplanation': 'NMI replaces palette 2 colors for the published actor; actor attributes remain palette 2',
              'sourcePlaneBytes': sum(len(variant['rowPlanes']) for pose in poses for variant in pose),
              'tableBytes': 9 * len(variants) + 8,
              'storageBytes': 9 * len(variants) + 8 + sum(len(variant['rowPlanes']) for pose in poses for variant in pose),
              'exactAspectRatio': '1:2 at every size',
              'walkingPosesShareOpaqueBoundsAndFeetBaseline': True,
              'sourceRowsPaddedToTileHeight': False,
              'outputRowsPaddedToTileHeight': True,
              'paddingRequiresZeroMaskReadSkip': True,
              'storage': 'For each actual source row, C plane-0 bytes then C plane-1 bytes; C=ceil(width/8). No source row padding. The compositor emits zero rows past the source height without reading source memory.',
              'variants': [{key: value for key, value in variant.items()
                            if key not in ('pixels', 'patterns', 'raw', 'rowPlanes')} for variant in variants],
              'sourceSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    report['poses'] = [{'pose': pose, 'sourcePlaneBytes': sum(len(v['rowPlanes']) for v in variants),
                        'variants': [{k: v for k, v in variant.items() if k not in ('pixels', 'patterns', 'raw', 'rowPlanes')} for variant in variants]}
                       for pose, variants in enumerate(poses)]
    report['animation'] = 'Counter bit5 alternates after32 successful movement ticks; immutable pose per world picture'
    (output / 'zombie-assets.json').write_text(json.dumps(report, indent=2) + '\n')
    if preview_dir is not None:
        for pose, variants in enumerate(poses):
            previews(Path(preview_dir) / ('pose-%d' % pose), variants, pose)
        # Compact native pair and enlarged pair for a readable motion review.
        pair = [[PALETTE_RGB[0] for _ in range(40)] for _ in range(36)]
        for pose in (0, 1):
            for y, row in enumerate(source_pixels(POSE_MASTERS[pose])):
                for x, value in enumerate(row):
                    pair[y + 2][x + 2 + pose * 20] = PALETTE_RGB[value]
        _png(Path(preview_dir) / 'zombie-walk-pair-native.png', pair)
        _png(Path(preview_dir) / 'zombie-walk-pair-preview.png', pair, 8)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--preview-dir', type=Path)
    args = parser.parse_args()
    print(json.dumps(write_assets(args.output, args.preview_dir), indent=2))
