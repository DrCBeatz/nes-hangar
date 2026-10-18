"""Static completion screen using only the existing fixed font patterns."""
from pathlib import Path
import json


def write_assets(build, font):
    build = Path(build)
    name = bytearray(1024)
    lines = []

    def line(row, text, palette=1, col=None):
        col = (32-len(text))//2 if col is None else col
        assert 0 <= col and col+len(text) <= 32
        name[row*32+col:row*32+col+len(text)] = bytes(font[c] for c in text)
        lines.append(dict(row=row, col=col, text=text, palette=palette))
        for x in range(col, col+len(text)):
            addr = 0x3c0+(row//4)*8+x//4
            shift = ((row & 2) << 1) | (x & 2)
            name[addr] = (name[addr] & ~(3 << shift)) | (palette << shift)
        return row*32+col

    line(5, 'E1M1', 2)
    line(7, 'HANGAR', 2)
    line(10, 'LEVEL COMPLETE')
    kills = line(14, 'KILLS     0 / 2', col=8)+10
    items = line(16, 'ITEMS     0 / 2', col=8)+10
    time = line(18, 'TIME      00:00', col=8)+10
    line(24, 'PRESS START TO RESTART', 3)
    assert 4 not in name[:960], 'Reclaimed blank tile belongs to the pistol'
    palette = bytes([0x0f,0x17,0x07,0x2d, 0x0f,0x30,0x10,0x2d,
                     0x0f,0x16,0x27,0x2d, 0x0f,0x10,0x00,0x2d]*2)
    (build/'results-nametable.bin').write_bytes(name)
    (build/'results-palette.bin').write_bytes(palette)
    config = {'RESULTS_KILLS_ADDR':0x2000+kills,
              'RESULTS_ITEMS_ADDR':0x2000+items,
              'RESULTS_MINUTES_ADDR':0x2000+time,
              'RESULTS_SECONDS_ADDR':0x2000+time+3,
              'RESULTS_DIGIT_ZERO':font['0']}
    (build/'results-config.inc').write_text(''.join(f'{k} = ${v:04X}\n' for k,v in config.items()))
    report = dict(lines=lines, addresses=config, palette=list(palette),
                  fontMap=font, timerFormat='MM:SS, saturates at99:59',
                  enemyTotal=2, itemTotal=2, nametable=0, patternTable=0,
                  spriteRendering=False)
    (build/'results-layout.json').write_text(json.dumps(report, indent=2)+'\n')
    return report
