"""Rectangular medical cases with a lid seam and centered red cross; native pixels."""
from pathlib import Path
import struct
import zlib
import hashlib

# Preserve the accepted closest image. Derive all intermediate images offline;
# the NES only selects and uploads ordinary prebuilt bitplanes.
MASTER = (
    '.33333333333333.', '3333333333333333', '1111111331111111',
    '1333333333333331', '1333333223333331', '1333333223333331',
    '1333322222233331', '1333322222233331', '1333333223333331',
    '1333333223333331', '1333333333333331', '1111111111111111',
)


def resize_case(width):
    height = (3 * width + 2) // 4
    # Endpoint-aligned nearest samples preserve the lid, sides and occupied
    # bottom row. No filtering/new palette colors, and no runtime resampling.
    def sample(position, source, target):
        return (2 * position * (source - 1) + target - 1) // (2 * (target - 1))
    return tuple(''.join(MASTER[sample(y, 12, height)][sample(x, 16, width)]
                         for x in range(width)) for y in range(height))


ART = tuple(resize_case(width) for width in range(4, 17))
# Tiny images need a hand-tuned medical mark: simple resampling can miss the
# two-pixel stem entirely. Keep a flat base and a centered mark at every tier.
ART = (
    ('3333', '1221', '1111'),
    ('.333.', '13231', '12221', '11111'),
    ('.3333.', '132231', '122221', '132231', '111111'),
    ('.33333.', '1332331', '1322231', '1332331', '1111111'),
    ('.333333.', '11133111', '13322331', '13222231', '13322331', '11111111'),
) + ART[5:]
# index0 transparent; charcoal edges/seam, red cross, medium-gray case/lid.
# The flat lowest row keeps the existing floor anchor at every distance tier.
PALETTE = ((0,0,0,0),(82,82,82,255),(181,49,32,255),(152,150,152,255))


def png(path, rows, scale=1):
    w,h=len(rows[0])*scale,len(rows)*scale
    raw=b''.join(b'\0'+b''.join(bytes(PALETTE[0 if c=='.' else int(c)])*scale for c in row) for row in rows for _ in range(scale))
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))


def write_assets(build, preview_dir=None):
    build=Path(build); build.mkdir(parents=True,exist_ok=True)
    widths=[len(rows[0]) for rows in ART]; heights=[len(rows) for rows in ART]
    cols=[(w+7)//8 for w in widths]; tile_rows=[(h+7)//8 for h in heights]
    text=['; Native medkit tiers, rows as C plane0 bytes then C plane1 bytes.',
          'MEDKIT_VARIANT_COUNT = '+str(len(ART))]
    for name, values in [('widths',widths),('heights',heights),('cols',cols),('rows',tile_rows),('pattern_counts',[a*b for a,b in zip(cols,tile_rows)])]:
        text += ['medkit_'+name+': .byte '+','.join(map(str,values))]
    for part,operator in [('lo','<'),('hi','>')]:
        text += ['medkit_art_'+part+': .byte '+','.join(operator+'medkit_art_'+str(i) for i in range(len(ART)))]
    # Nearest width based on radial distance; exact squared Q8.8 boundaries.
    # Exact ceil((65536 / midpointWidth)^2), using integer arithmetic.
    sums=[a+b for a,b in zip(widths, widths[1:])]
    thresholds=[((2*65536)**2 + value*value - 1)//(value*value) for value in sums]
    for shift in range(4):
        text += ['medkit_distance_threshold'+str(shift)+': .byte '+','.join(str((v>>(8*shift))&255) for v in thresholds)]
    # Projection metadata remains mirrored; only the pixel source is banked.
    text += ['.pushseg', '.segment "ACTOR_ART"']
    variants=[]
    for i,rows in enumerate(ART):
        assert len(set(map(len,rows)))==1
        data=bytearray()
        for y in range(tile_rows[i]*8):
            for plane in (0,1):
                for col in range(cols[i]):
                    bits=0
                    for bit in range(8):
                        x=col*8+bit
                        pixel=0 if y>=len(rows) or x>=len(rows[0]) or rows[y][x]=='.' else int(rows[y][x])
                        bits|=((pixel>>plane)&1)<<(7-bit)
                    data.append(bits)
        name=f'medkit-art-{i}.bin'; (build/name).write_bytes(data)
        text+=['medkit_art_'+str(i)+': .incbin "'+name+'"']
        variants.append(dict(width=widths[i],height=heights[i],columns=cols[i],rows=tile_rows[i],patterns=cols[i]*tile_rows[i],file=name,sha256=hashlib.sha256(data).hexdigest(),pixels=list(rows)))
        if preview_dir:
            preview_dir=Path(preview_dir); preview_dir.mkdir(parents=True,exist_ok=True)
            png(preview_dir/f'medkit-{widths[i]}x{heights[i]}.png',rows,scale=8)
    text += ['.popseg']
    (build/'medkit-assets.inc').write_text('\n'.join(text)+'\n')
    return dict(variants=variants,palette=['0F','2D','16','10'],maxPatterns=4,maxSprites=4,maximumWidth=16,physicalWidth=2,distanceThresholds=thresholds,
                scaleMethod='13 prebuilt radial tiers, nearest integer width, 3:4 height/width',
                physicalHeight=1.5,variantCount=len(ART))
