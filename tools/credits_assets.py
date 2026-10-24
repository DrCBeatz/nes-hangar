"""Generate the optional fixed-font credits page in its own startup PRG bank."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import newtitle_logo


def write_assets(build, font, preview_dir=None):
    """Use only the existing 64 fixed patterns; allocate no gameplay CHR/RAM."""
    build = Path(build)
    build.mkdir(parents=True, exist_ok=True)
    name = bytearray(1024)
    lines = []
    attribute_cells = {}

    def line(row, text, palette=1):
        col = (32-len(text))//2
        assert 3 <= row <= 27 and 0 <= col and col+len(text) <= 32
        missing = set(text)-set(font)
        assert not missing, ('Unsupported credits glyphs', sorted(missing))
        name[row*32+col:row*32+col+len(text)] = bytes(font[c] for c in text)
        lines.append(dict(row=row, col=col, text=text, palette=palette))
        for x in range(col, col+len(text)):
            cell = (row//2, x//2)
            assert attribute_cells.get(cell, palette) == palette, 'Conflicting text palettes'
            attribute_cells[cell] = palette
            addr = 0x3c0+(row//4)*8+x//4
            shift = ((row & 2) << 1) | (x & 2)
            name[addr] = (name[addr] & ~(3 << shift)) | (palette << shift)

    line(3, 'HANGAR', 2)
    line(5, 'NES PROTOTYPE BY', 3)
    line(6, 'DR C BEATZ')
    line(9, 'ORIGINAL DOOM', 3)
    line(10, 'ID SOFTWARE')
    line(12, 'AT DOOMS GATE')
    line(13, 'COMPOSED BY BOBBY PRINCE')
    line(14, 'NES ARRANGEMENT BY')
    line(15, 'DR C BEATZ')
    line(17, 'AUDIO ENGINE', 3)
    line(18, 'FAMISTUDIO BY')
    line(19, 'MATHIEU GAUTHIER')
    line(21, 'BASED ON FAMITONE2')
    line(22, 'BY SHIRU')
    line(26, 'B BACK / START CONTINUE', 3)

    assert 4 not in name[:960], 'Reclaimed blank tile belongs to the pistol'
    used_tiles = sorted(set(name[:960]))
    assert set(used_tiles) <= set(font.values())
    assert max(used_tiles) < 64, 'Credits must use the existing fixed font'
    # Black background, white body, bronze heading and gray labels. Both
    # halves are written for deterministic PPU palette state; sprites stay off.
    palette = bytes([0x0f,0x17,0x27,0x37, 0x0f,0x30,0x10,0x00,
                     0x0f,0x27,0x17,0x37, 0x0f,0x10,0x00,0x30]*2)
    (build/'credits-nametable.bin').write_bytes(name)
    (build/'credits-palette.bin').write_bytes(palette)
    report = dict(
        lines=lines, palette=list(palette), fontMap=font, usedFontTiles=used_tiles,
        nametable=0, patternTable=0, spriteRendering=False, additionalPatternBytes=0,
        bank=4, gatewayBank='COMMON', gameplayCpuOverhead=0,
        controls=dict(open='Select on the logo', back='B', continueToGuide='Start',
                      trigger='Fresh button edges; Start takes priority over B'),
        creditsScope='Project, original game, composition, new NES arrangement and audio engine',
        sha256={filename:hashlib.sha256((build/filename).read_bytes()).hexdigest()
                for filename in ('credits-nametable.bin','credits-palette.bin')})
    if preview_dir is not None:
        directory = Path(preview_dir)
        directory.mkdir(parents=True, exist_ok=True)
        patterns = (build/'fixed-patterns.bin').read_bytes()
        assert len(patterns) == 1024, 'Expected the existing 64 fixed patterns'
        pixels = newtitle_logo.decode_screen(patterns, name, palette)
        native, enlarged = directory/'credits-native.png', directory/'credits-preview.png'
        newtitle_logo.write_png(native, pixels)
        newtitle_logo.write_png(enlarged, pixels, scale=3)
        report['preview'] = dict(
            native=str(native), enlarged=str(enlarged), nativeSize=[256,240], previewScale=3,
            source='Offline decode of generated nametable, palette and existing fixed-pattern bytes',
            colorApproximation='Representative NES RGB palette')
    (build/'credits-layout.json').write_text(json.dumps(report, indent=2)+'\n')
    return report
