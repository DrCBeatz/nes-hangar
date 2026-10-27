"""Native indexed DOOM-logo import and NES tile conversion for the title screen.

The indexed source art is derived from id Software's M_DOOM patch in a supplied
WAD. It is third-party artwork, not original MIT-licensed project artwork.
Normal builds use the frozen indexed JSON and do not require or package a WAD.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

SOURCE = Path(__file__).resolve().parent.parent / 'assets/newlogo-doom.json'
LOGO_WIDTH, LOGO_HEIGHT = 192, 94
LOGO_X, LOGO_Y = 32, 40
FIRST_TILE = 64
# Only palette data changes between these builds. Index 1 contains both the
# original blue faces and some dark bronze shading, so mixed hues are an
# approximation of the source, not a restoration of its original colours.
PALETTES = {
    'grayscale': dict(label='Grayscale', colors=(0x0f, 0x00, 0x10, 0x30)),
    'bronze': dict(label='Bronze', colors=(0x0f, 0x17, 0x27, 0x37)),
    'blue-gold': dict(label='Blue and gold', colors=(0x0f, 0x11, 0x27, 0x37)),
    'steel': dict(label='Blue steel', colors=(0x0f, 0x11, 0x10, 0x30)),
}
DEFAULT_PALETTE = 'bronze'
# Representative RGB values for offline previews, not a universal NES colour
# standard. Actual colours depend on the emulator palette or console/display.
PREVIEW_RGB = {
    0x0f: (0, 0, 0), 0x00: (98, 98, 98), 0x10: (152, 150, 152),
    0x30: (255, 255, 255), 0x11: (8, 76, 196),
    0x17: (102, 52, 0), 0x27: (250, 158, 58), 0x37: (255, 217, 165),
}


def import_wad(wad, output=SOURCE):
    """Read patch columns and map the blue/bronze logo into three NES grays."""
    data = Path(wad).read_bytes()
    magic, count, directory = struct.unpack_from('<4sII', data)
    assert magic in (b'IWAD', b'PWAD') and directory + count * 16 <= len(data)
    patches = []
    palettes = []
    for index in range(count):
        start, size, name = struct.unpack_from('<II8s', data, directory + index * 16)
        assert start + size <= len(data)
        if name.rstrip(b'\0') == b'PLAYPAL':
            palettes.append(data[start:start + size])
        if name.rstrip(b'\0') == b'M_DOOM':
            patches.append(data[start:start + size])
    assert len(patches) == 1, 'Expected exactly one M_DOOM patch'
    assert len(palettes) == 1 and len(palettes[0]) >= 768
    palette = palettes[0]
    patch = patches[0]
    width, height, left, top = struct.unpack_from('<hhhh', patch)
    assert (width, height) == (123, 60), 'This experiment targets the original menu logo'
    pixels = [[0] * width for _ in range(height)]
    for x in range(width):
        cursor = struct.unpack_from('<I', patch, 8 + x * 4)[0]
        while patch[cursor] != 255:
            y, length = patch[cursor], patch[cursor + 1]
            assert y + length <= height and cursor + length + 4 <= len(patch)
            for row in range(y, y + length):
                index = patch[cursor + 3 + row - y]
                r, g, b = palette[index * 3:index * 3 + 3]
                luminance = (299 * r + 587 * g + 114 * b) // 1000
                # Keep the saturated blue letter faces visible in grayscale;
                # simple luminance would erase them while retaining bronze.
                pixels[row][x] = (1 if b * 2 > r * 3 and b * 2 > g * 3 else
                                  0 if luminance < 40 else 1 if luminance < 85 else
                                  2 if luminance < 150 else 3)
            cursor += length + 4
    report = dict(format='indexed-logo-v1', width=width, height=height,
                  backgroundIndex=0, grayIndices=[1, 2, 3],
                  rows=[''.join(map(str, row)) for row in pixels],
                  origin='id Software DOOM M_DOOM menu-logo patch, converted to three opaque grayscale shades',
                  licenseScope='Third-party DOOM artwork; excluded from the original-code MIT grant',
                  source=dict(wadSha256=hashlib.sha256(data).hexdigest(), lump='M_DOOM',
                              lumpSha256=hashlib.sha256(patch).hexdigest(), lumpBytes=len(patch),
                              playpalSha256=hashlib.sha256(palette).hexdigest(),
                              nativeWidth=width, nativeHeight=height, leftOffset=left, topOffset=top),
                  conversion='Transparent gaps and luminance below40 become black; luminance40..84 -> gray1,85..149 -> gray2,150+ -> gray3. Saturated blue (2B>3R and2B>3G) becomes gray1 to preserve letter faces. Integer luminance=(299R+587G+114B)//1000.')
    Path(output).write_text(json.dumps(report, indent=2) + '\n')
    return report


def tile_bytes(pixels, x, y):
    return bytes(sum(((pixels[y + py][x + px] >> plane) & 1) << (7 - px) for px in range(8))
                 for plane in (0, 1) for py in range(8))


def decode_screen(patterns, nametable, palette):
    """Independently decode exactly the NES bytes used in the experiment."""
    assert len(patterns) % 16 == 0 and len(nametable) == 1024
    pixels = []
    for y in range(240):
        row = []
        for x in range(256):
            tx, ty = x // 8, y // 8
            tile = nametable[ty * 32 + tx]
            at, bit = tile * 16 + y % 8, 7 - x % 8
            value = ((patterns[at] >> bit) & 1) | (((patterns[at + 8] >> bit) & 1) << 1)
            attr = nametable[960 + ty // 4 * 8 + tx // 4]
            pal = (attr >> (((ty & 2) << 1) | (tx & 2))) & 3
            color = palette[0 if not value else pal * 4 + value]
            row.append(PREVIEW_RGB[color])
        pixels.append(row)
    return pixels


def write_png(path, pixels, scale=1):
    width, height = len(pixels[0]), len(pixels)
    payload = b''.join((b'\0' + b''.join(bytes(p) * scale for p in row)) * scale for row in pixels)
    def chunk(kind, blob):
        return struct.pack('>I', len(blob)) + kind + blob + struct.pack('>I', zlib.crc32(kind + blob))
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' +
                          chunk(b'IHDR', struct.pack('>IIBBBBB', width * scale, height * scale, 8, 2, 0, 0, 0)) +
                          chunk(b'IDAT', zlib.compress(payload, 9)) + chunk(b'IEND', b''))


def write_assets(build, font, preview_dir=None, palette_name=DEFAULT_PALETTE):
    build = Path(build)
    selected = PALETTES[palette_name]
    logo_colors = selected['colors']
    assert len(logo_colors) == 4 and logo_colors[0] == 0x0f
    source = json.loads(SOURCE.read_text())
    assert source['format'] == 'indexed-logo-v1'
    width, height = source['width'], source['height']
    assert (width, height) == (123, 60)
    half_width, half_height = LOGO_WIDTH // 2, LOGO_HEIGHT // 2
    assert len(source['rows']) == height and all(len(row) == width and set(row) <= {'0', '1', '2', '3'} for row in source['rows'])
    screen = [[0] * 256 for _ in range(240)]
    for y in range(LOGO_HEIGHT):
        for x in range(LOGO_WIDTH):
            source_y = ((2 * (y // 2) + 1) * height) // (2 * half_height)
            source_x = ((2 * (x // 2) + 1) * width) // (2 * half_width)
            screen[LOGO_Y + y][LOGO_X + x] = int(source['rows'][source_y][source_x])
    fixed = (build / 'fixed-patterns.bin').read_bytes()
    assert len(fixed) == FIRST_TILE * 16 and fixed[:16] == bytes(16)
    lookup, extra, name = {bytes(16): 0}, [], bytearray(1024)
    for ty in range(30):
        for tx in range(32):
            pattern = tile_bytes(screen, tx * 8, ty * 8)
            if pattern not in lookup:
                lookup[pattern] = FIRST_TILE + len(extra)
                extra.append(pattern)
            name[ty * 32 + tx] = lookup[pattern]
    # The shared gameplay font has no period: its remaining fixed tiles hold
    # weapon art. Append a boot-only glyph to the logo's temporary CHR tiles.
    # Paired rows retain the existing two-for-one title packing format.
    period = bytes([0, 0, 0, 0, 0, 0, 0x18, 0x18] + [0] * 8)
    if period not in lookup:
        lookup[period] = FIRST_TILE + len(extra)
        extra.append(period)
    title_font = dict(font, **{'.': lookup[period]})
    lines = []
    for row, text in ((19, 'HANGAR'), (21, 'UNOFFICIAL NES PROTOTYPE'),
                      (23, 'PROTOTYPE 0.2.0'), (26, 'START PLAY / SELECT CREDITS')):
        col = (32 - len(text)) // 2
        assert set(text) <= set(title_font)
        assert all(title_font[c] < FIRST_TILE or c == '.' for c in text)
        name[row * 32 + col:row * 32 + col + len(text)] = bytes(title_font[c] for c in text)
        lines.append(dict(row=row, col=col, text=text))
        for x in range(col, col + len(text)):
            at = 960 + row // 4 * 8 + x // 4
            shift = ((row & 2) << 1) | (x & 2)
            name[at] = (name[at] & ~(3 << shift)) | (1 << shift)
    raw = b''.join(extra)
    assert FIRST_TILE + len(extra) <= 256
    assert FIRST_TILE * 16 + len(raw) <= 4096
    # Exact2x vertical expansion repeats every row pair. Store four bytes per
    # plane, then the boot uploader writes each byte twice. No runtime scratch.
    packed = bytearray()
    for pattern in extra:
        assert all(pattern[i] == pattern[i + 1] for i in range(0, 16, 2))
        packed.extend(pattern[::2])
    assert bytes(v for byte in packed for v in (byte, byte)) == raw
    palette = bytes(logo_colors) + bytes([0x0f, 0x30, 0x10, 0x00] * 7)
    assert len(palette) == 32 and all(palette[i] == 0x0f for i in range(0, 32, 4))
    (build / 'newtitle-logo-patterns.bin').write_bytes(raw)  # decoded verification data
    output = {'newtitle-logo-packed.bin': bytes(packed), 'newtitle-logo-nametable.bin': bytes(name),
              'newtitle-logo-palette.bin': palette}
    for filename, blob in output.items():
        (build / filename).write_bytes(blob)
    config = dict(NEW_TITLE_CHR_ADDR=FIRST_TILE * 16, NEW_TITLE_CHR_PATTERNS=len(extra))
    (build / 'newtitle-logo-config.inc').write_text(''.join(f'{k} = ${v:04X}\n' for k, v in config.items()))
    decoded = decode_screen(fixed + raw, name, palette)
    for y in range(LOGO_Y, LOGO_Y + LOGO_HEIGHT):
        for x in range(LOGO_X, LOGO_X + LOGO_WIDTH):
            assert decoded[y][x] == PREVIEW_RGB[logo_colors[screen[y][x]]]
    # All fixed font tiles are retained, so the following guide needs no CHR reload.
    assert (fixed + raw)[:1024] == fixed
    report = dict(source='assets/newlogo-doom.json', origin=source['origin'], sourceSha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                  sourceLump=source['source'], nativeScreen=[256, 240], logoBounds=[LOGO_X, LOGO_Y, LOGO_WIDTH, LOGO_HEIGHT],
                  style=selected['label'] + '; unchanged indexed logo on black',
                  paletteName=palette_name, paletteNes=list(logo_colors),
                  previewColorApproximation='Representative NES RGB; actual emulator and display colours vary',
                  newPatternCount=len(extra),
                  firstPattern=FIRST_TILE, highestPattern=FIRST_TILE + len(extra) - 1,
                  patternBytes=len(raw), storedPatternBytes=len(packed), uploadedPatternBytes=len(raw), nametableBytes=len(name), paletteBytes=len(palette),
                  additionalAssetBytes=sum(len(v) for v in output.values()), patternTable=0, fontPreserved=True,
                  patternPacking='Each stored byte is emitted twice, restoring adjacent identical pattern rows in each plane',
                  lines=lines, titleGlyphMap=title_font,
                  bootOnlyGlyphs={'.': lookup[period]},
                  spriteRendering=False, gameplayResourceCost=0,
                  sha256={k: hashlib.sha256(v).hexdigest() for k, v in output.items()})
    if preview_dir is not None:
        preview = Path(preview_dir)
        preview.mkdir(parents=True, exist_ok=True)
        write_png(preview / 'newtitle-logo-native.png', decoded)
        write_png(preview / 'newtitle-logo-preview.png', decoded, 3)
        report['preview'] = dict(native=str(preview / 'newtitle-logo-native.png'), enlarged=str(preview / 'newtitle-logo-preview.png'),
                                 source='Offline decode of exact generated NES pattern, nametable and palette bytes')
    (build / 'newtitle-logo-layout.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--import-wad', type=Path, required=True, help='Read M_DOOM from a supplied WAD; not required for normal builds')
    parser.add_argument('--output', type=Path, default=SOURCE)
    args = parser.parse_args()
    result = import_wad(args.import_wad, args.output)
    print(json.dumps({k: v for k, v in result.items() if k != 'rows'}, indent=2))
