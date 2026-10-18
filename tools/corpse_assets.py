"""Original compact fallen soldier, using the established zombie palette.

The bent knees keep the prone silhouette compact. Its pale head is on the
left, olive jacket and trousers in the middle, and dark boots on the right;
the rifle lies across its lower edge. These are indexed source pixels, not
extracted Doom artwork. Runtime rendering reuses the zombie's masked tiles.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zlib


MASTER = (
    '.................1111...........',
    '................122221..........',
    '...............12222221.........',
    '....11111....1122222221.........',
    '...1333331.122222122221.........',
    '..13333333122222221222211.......',
    '..1331333312222222212222221.....',
    '...133333312222222221222222111..',
    '....11333122222222221222222111..',
    '...111111111133111111111111111..',
    '....111111111111111111111111111.',
    '.....11111..111111111111..111111',
)
SIZES = ((4, 2), (6, 3), (8, 3), (12, 5), (16, 6), (20, 8),
         (24, 9), (28, 11), (32, 12))
# Native tiny silhouettes preserve the pale head and olive uniform, details
# that nearest-neighbor reduction otherwise removes in the distant tiers.
NATIVE = {
    (4, 2): ('3221', '1111'),
    (6, 3): ('.122..', '332221', '111111'),
    (8, 3): ('...121..', '33222211', '11111111'),
    (12, 5): ('......121...', '.11..12221..', '13311222221.',
              '.33122222111', '.11111111111'),
}
PALETTE_NES = (0x0F, 0x0F, 0x18, 0x37)
PALETTE_RGB = ((37, 37, 42), (0, 0, 0), (112, 114, 0), (255, 217, 165))


def source_pixels(rows):
    assert rows and len({len(row) for row in rows}) == 1
    return [[0 if value == '.' else int(value) for value in row] for row in rows]


def resize(width, height):
    # Endpoint-aligned sampling preserves the lowest opaque source row and
    # keeps the floor anchor fixed. All scaling is performed at build time.
    def sample(position, old, new):
        return (2 * position * (old - 1) + new - 1) // (2 * (new - 1))
    return tuple(''.join(MASTER[sample(y, 12, height)][sample(x, 32, width)]
                         for x in range(width)) for y in range(height))


def build_assets():
    variants = []
    for index, (width, height) in enumerate(SIZES):
        rows = NATIVE.get((width, height)) or resize(width, height)
        pixels = source_pixels(rows)
        assert len(pixels) == height and all(len(row) == width for row in pixels)
        columns, tile_rows = (width + 7) // 8, (height + 7) // 8
        data = bytearray()
        for y in range(tile_rows * 8):
            for plane in (0, 1):
                for column in range(columns):
                    bits = 0
                    for bit in range(8):
                        x = column * 8 + bit
                        pixel = pixels[y][x] if y < height and x < width else 0
                        bits |= ((pixel >> plane) & 1) << (7 - bit)
                    data.append(bits)
        opaque = [(x, y) for y, row in enumerate(pixels)
                  for x, value in enumerate(row) if value]
        bounds = [min(x for x, _ in opaque), min(y for _, y in opaque),
                  max(x for x, _ in opaque), max(y for _, y in opaque)]
        assert bounds[3] == height - 1
        assert columns * tile_rows <= 8
        # Decode the stored rows, including all tile padding, independently.
        for y in range(tile_rows * 8):
            for x in range(columns * 8):
                offset, shift = y * columns * 2 + x // 8, 7 - x % 8
                decoded = ((data[offset] >> shift) & 1) | (((data[offset + columns] >> shift) & 1) << 1)
                assert decoded == (pixels[y][x] if y < height and x < width else 0)
        variants.append(dict(index=index, width=width, height=height,
                             columns=columns, rows=tile_rows,
                             patternCount=columns * tile_rows, storedRows=tile_rows * 8,
                             storedPlaneBytes=len(data), opaqueBoundsInclusive=bounds,
                             feetBaselineY=height - 1, pixels=pixels, rowPlanes=bytes(data)))
    return variants


def _png(path, pixels, scale=1):
    height, width = len(pixels), len(pixels[0])
    payload = b''.join((b'\0' + b''.join(bytes(pixel) * scale for pixel in row)) * scale
                       for row in pixels)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' +
                          chunk(b'IHDR', struct.pack('>IIBBBBB', width * scale, height * scale, 8, 2, 0, 0, 0)) +
                          chunk(b'IDAT', zlib.compress(payload, 9)) + chunk(b'IEND', b''))


def previews(directory, variants):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    gap, padding = 6, 6
    width = sum(v['width'] for v in variants) + gap * (len(variants) - 1) + padding * 2
    height = 12 + padding * 2
    image = [[PALETTE_RGB[0] for _ in range(width)] for _ in range(height)]
    left = padding
    for variant in variants:
        top = height - padding - variant['height']
        for y, row in enumerate(variant['pixels']):
            for x, value in enumerate(row):
                image[top + y][left + x] = PALETTE_RGB[value]
        left += variant['width'] + gap
        single = [[PALETTE_RGB[value] for value in row] for row in variant['pixels']]
        name = 'corpse-%dx%d' % (variant['width'], variant['height'])
        _png(directory / (name + '-native.png'), single)
        _png(directory / (name + '.png'), single, 12)
    _png(directory / 'corpse-sizes-native.png', image)
    _png(directory / 'corpse-sizes-preview.png', image, 5)


def write_assets(build, preview_dir=None):
    build = Path(build)
    build.mkdir(parents=True, exist_ok=True)
    variants = build_assets()
    text = ['; Original prone soldier, C plane-0 bytes then C plane-1 bytes per row.',
            'CORPSE_VARIANT_COUNT = 9', 'CORPSE_MAX_PATTERNS = 8']
    for field, label in (('width', 'widths'), ('height', 'heights'), ('columns', 'cols'),
                         ('rows', 'rows'), ('patternCount', 'pattern_counts')):
        text.append('corpse_' + label + ': .byte ' + ','.join(str(v[field]) for v in variants))
    for part, operator in (('lo', '<'), ('hi', '>')):
        text.append('corpse_art_' + part + ': .byte ' + ','.join(
            operator + 'corpse_art_' + str(v['index']) for v in variants))
    text += ['.pushseg', '.segment "ACTOR_ART"']
    for variant in variants:
        filename = 'corpse-art-%d.bin' % variant['index']
        (build / filename).write_bytes(variant['rowPlanes'])
        text.append('corpse_art_%d: .incbin "%s"' % (variant['index'], filename))
        variant['file'] = filename
        variant['sha256'] = hashlib.sha256(variant['rowPlanes']).hexdigest()
    text += ['.popseg']
    (build / 'corpse-assets.inc').write_text('\n'.join(text) + '\n')
    report = dict(origin='Original hand-authored compact prone soldier; no extracted Doom artwork',
                  normalPalette=list(PALETTE_NES), normalSpritePalette=2,
                  maxPatternsPerFrame=8, maxSprites=8, maxSpriteColumns=4,
                  sourceWidth=32, sourceHeight=12, variantCount=len(variants),
                  feetBaseline='Last opaque pixel row', sourceRowsPaddedToTileHeight=True,
                  sourcePlaneBytes=sum(v['storedPlaneBytes'] for v in variants),
                  tableBytes=7 * len(variants), storageBytes=7 * len(variants) + sum(v['storedPlaneBytes'] for v in variants),
                  storage='Each row: C low-plane bytes, then C high-plane bytes; rows zero-padded to eight.',
                  variants=[{key: value for key, value in v.items() if key != 'rowPlanes'} for v in variants],
                  sourceSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (build / 'corpse-assets.json').write_text(json.dumps(report, indent=2) + '\n')
    if preview_dir is not None:
        previews(preview_dir, variants)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('--preview-dir', type=Path)
    arguments = parser.parse_args()
    print(json.dumps(write_assets(arguments.build, arguments.preview_dir), indent=2))
