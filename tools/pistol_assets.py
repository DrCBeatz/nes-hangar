"""Import the user-edited two-frame pistol PNG exactly into NES sprite patterns.

Only fixed patterns, static text, and OAM tile indices are made offline.  No
world views are generated here.  The four existing world solids are immutable;
both pattern-table banks receive this same 1 KiB fixed area at startup.
"""
from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT_CHARS = ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:/+-'
FONT_MAP = {ch: index + 4 for index, ch in enumerate(FONT_CHARS)}
# Slot 4 used to duplicate blank slot 0. Reuse that slot for weapon art while
# keeping every visible glyph and its index unchanged.
FONT_MAP[' '] = 0
SOURCE_SHEET = ROOT / 'assets/pistol-sheet.png'
WORLD_PALETTE = (0x0F, 0x17, 0x07, 0x2D)
HUD_PALETTE = (0x0F, 0x30, 0x10, 0x2D)
SPRITE_PALETTES = (0x0F, 0x0F, 0x17, 0x27, 0x0F, 0x0F, 0x27, 0x37)
PISTOL_X, PISTOL_TOP = 112, 136
HUD_NUMBERS = {'health': (4, 23, 100), 'ammo': (14, 23, 6)}


def _glyphs():
    return json.loads((ROOT / 'assets/font.json').read_text())


def _pattern(pixels):
    assert len(pixels) == 8 and all(len(row) == 8 for row in pixels)
    return bytes(sum(((pixels[y][x] >> bit) & 1) << (7 - x) for x in range(8))
                 for bit in range(2) for y in range(8))


def _read_indexed_sheet():
    """Decode the frozen, 8-bit indexed Aseprite PNG without external packages.

    CRC, format, filters and palette checks reject accidental source changes
    rather than silently quantizing or changing transparency. This PNG remains
    the source of both frames; the firing frame is not regenerated from idle.
    """
    data = SOURCE_SHEET.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Pistol source is not a PNG')
    offset, chunks = 8, {}
    while offset < len(data):
        if len(data) - offset < 12:
            raise ValueError('Truncated pistol PNG chunk')
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + size]
        if offset + size + 12 > len(data):
            raise ValueError('Truncated pistol PNG payload')
        crc = struct.unpack_from('>I', data, offset + 8 + size)[0]
        if zlib.crc32(kind + payload) != crc:
            raise ValueError('Pistol PNG failed CRC validation')
        chunks.setdefault(kind, []).append(payload)
        offset += size + 12
        if kind == b'IEND':
            break
    if len(chunks.get(b'IHDR', [])) != 1:
        raise ValueError('Pistol PNG needs exactly one header')
    header = struct.unpack('>IIBBBBB', chunks[b'IHDR'][0])
    if header != (64, 32, 8, 3, 0, 0, 0):
        raise ValueError('Pistol sheet must be noninterlaced, 8-bit indexed, 64 x 32')
    palette = b''.join(chunks.get(b'PLTE', []))
    alpha = b''.join(chunks.get(b'tRNS', []))
    if len(palette) % 3 or not palette or not chunks.get(b'IEND'):
        raise ValueError('Pistol PNG has an invalid palette or no end marker')
    colors = [tuple(palette[i:i + 3]) + (alpha[i // 3] if i // 3 < len(alpha) else 255,)
              for i in range(0, len(palette), 3)]
    raw = zlib.decompress(b''.join(chunks.get(b'IDAT', [])))
    if len(raw) != 32 * 65:
        raise ValueError('Pistol PNG decoded data has the wrong length')
    rows = []
    for y in range(32):
        filter_type = raw[y * 65]
        row = list(raw[y * 65 + 1:(y + 1) * 65])
        previous = rows[y - 1] if y else [0] * 64
        for x in range(64):
            left = row[x - 1] if x else 0
            above = previous[x]
            upper_left = previous[x - 1] if x else 0
            if filter_type == 0:
                prediction = 0
            elif filter_type == 1:
                prediction = left
            elif filter_type == 2:
                prediction = above
            elif filter_type == 3:
                prediction = (left + above) // 2
            elif filter_type == 4:
                p = left + above - upper_left
                distances = [abs(p - left), abs(p - above), abs(p - upper_left)]
                prediction = (left, above, upper_left)[distances.index(min(distances))]
            else:
                raise ValueError('Unsupported pistol PNG filter')
            row[x] = (row[x] + prediction) & 255
        rows.append(row)
    if any(index >= len(colors) for row in rows for index in row):
        raise ValueError('Pistol PNG pixel references a missing palette entry')
    return [[colors[index] for index in row] for row in rows]


def _weapon_frames():
    """Map the supplied idle and firing frames to their existing sprite palettes."""
    rgba = _read_indexed_sheet()
    rgb = {0x0F: (0, 0, 0), 0x17: (102, 52, 0),
           0x27: (250, 158, 58), 0x37: (255, 217, 165)}
    frames = {}
    for frame_index, frame in enumerate(('idle', 'fire')):
        pixels = []
        for y in range(32):
            palette_id = int(frame == 'fire' and y < 8)
            palette = SPRITE_PALETTES[palette_id * 4:palette_id * 4 + 4]
            allowed = {rgb[palette[index]] + (255,): index for index in range(1, 4)}
            row = []
            for x in range(32):
                pixel = rgba[y][frame_index * 32 + x]
                if pixel[3] == 0:
                    row.append(0)
                elif pixel in allowed:
                    row.append(allowed[pixel])
                else:
                    raise ValueError(f'{frame} pixel ({x}, {y}) {pixel} is outside its NES palette')
            pixels.append(row)
        frames[frame] = pixels
    return frames


def _tile_variants(pixels):
    """All hardware-flippable orientations for exact 2bpp pattern reuse."""
    for attributes, rows in ((0, pixels), (0x40, [row[::-1] for row in pixels]),
                             (0x80, pixels[::-1]), (0xC0, [row[::-1] for row in pixels[::-1]])):
        yield attributes, _pattern(rows)


def _decode_frame(patterns, tile_indices, attributes):
    """Reconstruct precisely what the hardware will display, including flips."""
    pixels = [[0] * 32 for _ in range(32)]
    for index, (slot, attr) in enumerate(zip(tile_indices, attributes)):
        tile = patterns[slot]
        for y in range(8):
            source_y = 7 - y if attr & 0x80 else y
            for x in range(8):
                bit = x if attr & 0x40 else 7 - x
                value = ((tile[source_y] >> bit) & 1) | (((tile[source_y + 8] >> bit) & 1) << 1)
                pixels[(index // 4) * 8 + y][(index % 4) * 8 + x] = value
    return pixels


def _asm_bytes(label, values):
    return label + ':\n .byte ' + ','.join('$%02X' % v for v in values) + '\n'


def assets(build_dir, preview_dir=None):
    """Write the 1 KiB fixed CHR area, nametable and ca65 OAM/HUD interface."""
    build_dir = Path(build_dir)
    build_dir.mkdir(parents=True, exist_ok=True)
    glyphs = _glyphs()
    patterns = []
    for value in range(4):
        patterns.append(bytes([255 if value & 1 else 0]) * 8 + bytes([255 if value & 2 else 0]) * 8)
    for ch in FONT_CHARS:
        rows = glyphs[ch].split('/')
        patterns.append(bytes([int(row, 2) << 2 for row in rows] + [0]) + bytes(8))
    assert len(patterns) == 45  # Slots 0..44; original A..Z and decimal digits.
    # FONT_CHARS contains 41 glyphs: four solids plus forty-one fixed glyphs.
    first_contiguous_weapon_slot = len(patterns)
    reclaimed_weapon_slots = [4]
    allocated_weapon_slots = []
    frames = _weapon_frames()
    tile_indices, attributes = {}, {}
    for frame, pixels in frames.items():
        indices, attrs = [], []
        for row in range(4):
            for col in range(4):
                tile_pixels = [line[col * 8:col * 8 + 8] for line in pixels[row * 8:row * 8 + 8]]
                for flips, tile in _tile_variants(tile_pixels):
                    if tile in patterns:
                        slot = patterns.index(tile)
                        break
                else:
                    flips, tile = next(_tile_variants(tile_pixels))
                    slot = len(patterns)
                    if len(patterns) < 64:
                        patterns.append(tile)
                    else:
                        assert reclaimed_weapon_slots, 'Edited art exceeds the fixed CHR budget'
                        slot = reclaimed_weapon_slots.pop(0)
                        patterns[slot] = tile
                    allocated_weapon_slots.append(slot)
                indices.append(slot)
                palette = int(frame == 'fire' and row == 0)
                attrs.append(palette | flips)
        tile_indices[frame], attributes[frame] = indices, attrs
    for frame, pixels in frames.items():
        assert _decode_frame(patterns, tile_indices[frame], attributes[frame]) == pixels
    used_patterns = len(patterns)
    assert used_patterns <= 64, 'HUD must not consume any of the 192 dynamic world patterns'
    patterns += [bytes(16)] * (64 - len(patterns))
    fixed = b''.join(patterns)
    assert len(fixed) == 1024
    (build_dir / 'fixed-patterns.bin').write_bytes(fixed)

    name = bytearray(1024)
    text_lines = []

    def line(row, text, col=None):
        col = (32 - len(text)) // 2 if col is None else col
        assert 0 <= col and col + len(text) <= 32, text
        name[row * 32 + col:row * 32 + col + len(text)] = bytes(FONT_MAP[ch] for ch in text)
        text_lines.append({'row': row, 'col': col, 'text': text})

    line(1, 'E1M1 / HANGAR PROTOTYPE')
    line(22, 'HEALTH', 3)
    line(22, 'AMMO', 14)
    line(22, 'WEAPON', 24)
    line(23, 'PISTOL', 24)
    for col, row, value in HUD_NUMBERS.values():
        line(row, f'{value:03}', col)
    line(25, 'B FIRE  A+L/R STRAFE')
    line(26, 'UP/DOWN WALK  L/R TURN')
    line(27, 'SELECT EDGES  START PAUSE')
    # These are the existing world attribute bytes.  All 256x144 world pixels
    # (rows 3..20) keep palette 0; title and HUD use the readable white palette.
    name[0x3C0:0x3C8] = bytes([0x05]) * 8
    name[0x3E8:0x3F0] = bytes([0x50]) * 8
    name[0x3F0:0x400] = bytes([0x55]) * 16

    def palette_at(col, row):
        return (name[0x3C0 + (row // 4) * 8 + col // 4] >> (((row & 2) << 1) | (col & 2))) & 3

    assert all(palette_at(col, row) == 0 for row in range(3, 21) for col in range(32))
    assert all(palette_at(col, row) == 1 for row in (1, 22, 23, 25, 26, 27) for col in range(32))
    assert 4 not in name[:0x3C0], 'Reclaimed blank slot must not remain in the nametable'
    (build_dir / 'nametable.bin').write_bytes(name)
    (build_dir / 'world-palette.bin').write_bytes(bytes(WORLD_PALETTE))

    include = '; Generated by assets.py. Coordinates use NES OAM Y = top - 1.\n'
    include += f'PISTOL_X = {PISTOL_X}\nPISTOL_Y = {PISTOL_TOP - 1}\n'
    include += f'PISTOL_SPRITE_COUNT = 16\nPISTOL_PALETTE_BYTES = 8\nFONT_ZERO_TILE = {FONT_MAP["0"]}\n'
    for key, (col, row, _) in HUD_NUMBERS.items():
        include += f'HUD_{key.upper()}_ADDR = ${0x2000 + row * 32 + col:04X}\n'
    for frame in ('idle', 'fire'):
        include += _asm_bytes('pistol_' + frame + '_tiles', tile_indices[frame])
        include += _asm_bytes('pistol_' + frame + '_attributes', attributes[frame])
    include += _asm_bytes('pistol_palette', SPRITE_PALETTES)
    include += _asm_bytes('hud_digit_tiles', [FONT_MAP[str(i)] for i in range(10)])
    (build_dir / 'pistol-assets.inc').write_text(include)
    report = {
        'origin': 'Exact imported user-edited 64x32 pistol-sheet.png; idle left, firing right; local five-by-seven font',
        'sourceSheet': 'assets/pistol-sheet.png',
        'sourceSheetSha256': hashlib.sha256(SOURCE_SHEET.read_bytes()).hexdigest(),
        'sourceDimensions': [64, 32], 'sourcePixelsPreservedExactly': True,
        'paletteDesign': 'Exact source colors: transparent, opaque black, brown and tan body; amber/cream flash',
        'fixedPatternBytes': len(fixed), 'usedFixedPatterns': used_patterns,
        'firstWeaponSlot': min(allocated_weapon_slots),
        'firstContiguousWeaponSlot': first_contiguous_weapon_slot,
        'weaponPatternSlots': sorted(allocated_weapon_slots),
        'weaponPatternCount': len(allocated_weapon_slots),
        'reclaimedBlankGlyphSlot': 4, 'spaceGlyphSlot': 0,
        'dynamicPatternCapacity': 192,
        'fontMap': FONT_MAP, 'spriteCount': 16, 'maxSpritesPerScanline': 4,
        'pistolBounds': [PISTOL_X, PISTOL_TOP, 32, 32], 'fireRecoilPixels': 2,
        'spritePalettes': list(SPRITE_PALETTES), 'worldPalette': list(WORLD_PALETTE),
        'hudPalette': list(HUD_PALETTE), 'tileIndices': tile_indices, 'attributes': attributes,
        'hudNumbers': {key: {'col': col, 'row': row, 'value': value,
                            'ppuAddresses': [0x2000 + row * 32 + col, 0x2800 + row * 32 + col]}
                       for key, (col, row, value) in HUD_NUMBERS.items()},
        'textLines': text_lines,
        'sha256': {filename: hashlib.sha256((build_dir / filename).read_bytes()).hexdigest()
                   for filename in ('fixed-patterns.bin', 'nametable.bin', 'world-palette.bin', 'pistol-assets.inc')},
    }
    (build_dir / 'pistol-assets.json').write_text(json.dumps(report, indent=2) + '\n')
    if preview_dir is not None:
        _previews(Path(preview_dir), frames, patterns, name, report)
    return report


def _previews(directory, frames, patterns, name, report):
    """Enlarged nearest-neighbour review artifacts; never embedded in the ROM."""
    import struct
    import zlib

    def write_png(path, pixels, scale):
        height, width = len(pixels), len(pixels[0])
        payload = bytearray()
        for row in pixels:
            expanded = b'\0' + b''.join(bytes(pixel) * scale for pixel in row)
            payload.extend(expanded * scale)
        def chunk(kind, content):
            return struct.pack('>I', len(content)) + kind + content + struct.pack('>I', zlib.crc32(kind + content))
        path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width * scale, height * scale, 8, 2, 0, 0, 0))
                         + chunk(b'IDAT', zlib.compress(bytes(payload), 9)) + chunk(b'IEND', b''))

    directory.mkdir(parents=True, exist_ok=True)
    frames = {frame: _decode_frame(patterns, report['tileIndices'][frame],
                                   report['attributes'][frame]) for frame in frames}
    rgb = {0x0F: (0, 0, 0), 0x17: (102, 52, 0), 0x07: (80, 20, 0),
           0x2D: (78, 78, 78), 0x00: (117, 117, 117), 0x10: (173, 173, 173), 0x30: (255, 255, 255),
           0x27: (250, 158, 58), 0x37: (255, 217, 165)}
    atlas = [[(25, 25, 29)] * 64 for _ in range(48)]
    glyphs = _glyphs()
    for index, (frame, pixels) in enumerate(frames.items()):
        for char_index, ch in enumerate(frame.upper()):
            for y, row in enumerate(glyphs[ch].split('/')):
                for x, pixel in enumerate(row):
                    if pixel == '1':
                        atlas[y][index * 32 + char_index * 6 + x] = (230, 230, 230)
        for y in range(32):
            for x in range(32):
                pal_id = report['attributes'][frame][(y // 8) * 4 + x // 8] & 3
                pal = SPRITE_PALETTES[pal_id * 4:pal_id * 4 + 4]
                atlas[y + 8][index * 32 + x] = rgb[pal[pixels[y][x]]] if pixels[y][x] else (78, 78, 78)
    write_png(directory / 'pistol-art-native.png', atlas, 1)
    write_png(directory / 'pistol-art-preview.png', atlas, 8)
    screen = [[(0, 0, 0)] * 256 for _ in range(240)]
    for tile_y in range(30):
        for tile_x in range(32):
            tile = patterns[name[tile_y * 32 + tile_x]]
            attr = name[0x3C0 + (tile_y // 4) * 8 + tile_x // 4]
            pal_id = (attr >> (((tile_y & 2) << 1) | (tile_x & 2))) & 3
            pal = HUD_PALETTE if pal_id == 1 else WORLD_PALETTE
            for py in range(8):
                for px in range(8):
                    color = ((tile[py] >> (7 - px)) & 1) | (((tile[py + 8] >> (7 - px)) & 1) << 1)
                    screen[tile_y * 8 + py][tile_x * 8 + px] = rgb[pal[color]]
    # Neutral placeholder world simply locates the gun and HUD. Real ROM
    # screenshots are independently obtained by the runtime verifier.
    for y in range(24, 168):
        screen[y] = [(25, 25, 25) if y < 96 else rgb[0x2D]] * 256
    for y, row in enumerate(frames['idle']):
        for x, color in enumerate(row):
            if color:
                pal_id = report['attributes']['idle'][(y // 8) * 4 + x // 8] & 3
                screen[PISTOL_TOP + y][PISTOL_X + x] = rgb[SPRITE_PALETTES[pal_id * 4 + color]]
    write_png(directory / 'hud-layout-preview.png', screen, 3)
    (directory / 'art-preview-metadata.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build_dir', type=Path)
    parser.add_argument('--preview-dir', type=Path)
    args = parser.parse_args()
    print(json.dumps(assets(args.build_dir, args.preview_dir), indent=2))
