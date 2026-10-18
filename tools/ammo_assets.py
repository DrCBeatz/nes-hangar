"""Native-pixel gray ammo clips with dark grooves and a small red cap."""
from pathlib import Path
import hashlib

import medkit_assets as medkit

# Gray magazine, dark vertical grooves and a red/copper-like cartridge cap.
# The visible silhouette is narrower than the shared projection canvas. Keeping
# those canvases unchanged preserves the medkit's accepted distance/feet math.
MASTER = (
    '.....222222.....', '....12222221....', '...1333333331...',
    '...1311331131...', '...1311331131...', '...1311331131...',
    '...1311331131...', '...1311331131...', '...1311331131...',
    '...1311331131...', '...1333333331...', '...1111111111...',
)
# Keep the grooves legible when nearest-neighbor scaling would lose a rail.
GROOVES = {3:'313', 4:'3113', 5:'31313', 6:'313313',
           7:'1313131', 8:'13133131', 9:'131131131', 10:'1311331131'}


def resize_clip(width):
    height = (3 * width + 2) // 4
    ink_width = (5 * width + 4) // 8
    def sample(position, source, target):
        return (2 * position * (source - 1) + target - 1) // (2 * (target - 1))
    rows = []
    for y in range(height):
        source_y = sample(y, 12, height)
        if 3 <= source_y <= 9:
            row = GROOVES[ink_width]
        else:
            row = ''.join(MASTER[source_y][3 + sample(x, 10, ink_width)]
                          for x in range(ink_width))
        rows.append(row)
    tiny = {
        4: ('.2.', '313', '111'),
        5: ('.2.', '333', '313', '111'),
        6: ('.22.', '3333', '3113', '3113', '1111'),
        7: ('.22.', '3333', '3113', '3113', '1111'),
        8: ('.222.', '33333', '31313', '31313', '31313', '11111'),
    }
    rows = tiny.get(width, rows)
    left = (width - ink_width) // 2
    return tuple('.' * left + row + '.' * (width - ink_width - left) for row in rows)


ART = tuple(resize_clip(width) for width in range(4, 17))
PALETTE = medkit.PALETTE


def write_assets(build, preview_dir=None):
    build = Path(build)
    build.mkdir(parents=True, exist_ok=True)
    widths = [len(rows[0]) for rows in ART]
    heights = [len(rows) for rows in ART]
    assert [(len(a[0]), len(a)) for a in ART] == [
        (len(a[0]), len(a)) for a in medkit.ART]
    columns = [(w + 7) // 8 for w in widths]
    tile_rows = [(h + 7) // 8 for h in heights]
    text = ['; Ammo pixels share all medkit size, threshold and projection tables.',
            '.pushseg', '.segment "RODATA"']
    for part, operator in [('lo', '<'), ('hi', '>')]:
        text += ['ammo_art_' + part + ': .byte ' + ','.join(
            operator + 'ammo_art_' + str(i) for i in range(len(ART)))]
    text += ['.segment "ACTOR_ART"']
    variants = []
    for i, rows in enumerate(ART):
        assert len(set(map(len, rows))) == 1
        assert set(''.join(rows)) <= set('.123')
        assert any(c != '.' for c in rows[-1]), 'Grounding requires floor-contact pixels'
        assert all(any(c != '.' for c in row) for row in rows), 'No vertical padding'
        patterns = columns[i] * tile_rows[i]
        assert patterns <= 4
        data = bytearray()
        for y in range(tile_rows[i] * 8):
            for plane in (0, 1):
                for col in range(columns[i]):
                    bits = 0
                    for bit in range(8):
                        x = col * 8 + bit
                        pixel = 0 if y >= len(rows) or x >= len(rows[0]) or rows[y][x] == '.' else int(rows[y][x])
                        bits |= ((pixel >> plane) & 1) << (7 - bit)
                    data.append(bits)
        name = f'ammo-art-{i}.bin'
        (build / name).write_bytes(data)
        text += ['ammo_art_' + str(i) + ': .incbin "' + name + '"']
        variants.append(dict(width=widths[i], height=heights[i], columns=columns[i],
            rows=tile_rows[i], patterns=patterns, file=name,
            sha256=hashlib.sha256(data).hexdigest(), pixels=list(rows)))
        if preview_dir:
            preview = Path(preview_dir)
            preview.mkdir(parents=True, exist_ok=True)
            medkit.png(preview / f'ammo-{widths[i]}x{heights[i]}-native.png', rows)
            medkit.png(preview / f'ammo-{widths[i]}x{heights[i]}.png', rows, scale=8)
    text += ['.popseg']
    assert len(ART) * 2 == 26
    assert sum(v['patterns'] * 16 for v in variants) == 496
    (build / 'ammo-assets.inc').write_text('\n'.join(text) + '\n')
    sums = [a + b for a, b in zip(widths, widths[1:])]
    thresholds = [((2 * 65536) ** 2 + value * value - 1) // (value * value) for value in sums]
    return dict(variants=variants, palette=['0F', '2D', '16', '10'], maxPatterns=4,
        maxSprites=4, maximumWidth=16, physicalWidth=2, distanceThresholds=thresholds,
        scaleMethod='13 prebuilt radial tiers, nearest integer width, 3:4 height/width',
        physicalHeight=1.5, variantCount=len(ART), sharedProjectionTables='medkit',
        commonBytes=26, artBytes=496, bottomOpaqueGrounding=True, transparentSideMargins=True,
        appearance='Upright gray clip, charcoal grooves and red cartridge cap',
        maximumOpaqueWidth=10, opaquePhysicalWidth=1.25)
