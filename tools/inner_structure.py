#!/usr/bin/env python3
"""Audit the flat inner-structure experiment and draw its top-down layout.

This checks authored geometry and traversable routes, not renderer speed or
runtime AI. The optional WAD check verifies the source footprint independently
from the handwritten provenance metadata. No WAD is needed to build the ROM.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import html
import json
import math
import os
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]


def source_check(path, scene):
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == scene['source']['wad_sha256']
    kind, count, directory = struct.unpack_from('<4sII', data)
    assert kind in (b'IWAD', b'PWAD')
    entries = [struct.unpack_from('<II8s', data, directory + 16*i)
               for i in range(count)]
    marker = next(i for i, (_, _, name) in enumerate(entries)
                  if name.rstrip(b'\0') == b'E1M1')
    lumps = {name.rstrip(b'\0'): data[start:start+size]
             for start, size, name in entries[marker:marker+11]}
    vertices = list(struct.iter_unpack('<hh', lumps[b'VERTEXES']))
    lines = list(struct.iter_unpack('<7H', lumps[b'LINEDEFS']))
    def world(vertex):
        x, z = vertices[vertex]
        assert (x-640) % 8 == (z+3712) % 8 == 0
        return [(x-640)//8, (z+3712)//8+160]
    expected = {398: [[184,300],[212,300]],
                399: [[212,300],[212,340]],
                400: [[212,340],[184,340]],
                412: [[188,336],[188,304]]}
    for index, pair in expected.items():
        assert [world(v) for v in lines[index][:2]] == pair
    return {'sha256': hashlib.sha256(data).hexdigest(),
            'checkedLinedefs': list(expected), 'outerFootprintMatches': True,
            'sourceOpeningDeliberatelySealed': True}


def preview(scene, destination):
    """A diagram of authored world positions; this is not an emulator image."""
    def xy(p): return (75+(p[0]-112)*5, 95+(376-p[1])*5)
    def points(poly): return ' '.join(f'{x:g},{y:g}' for x,y in map(xy,poly))
    def line(a,b,**attrs):
        ax,ay=xy(a); bx,by=xy(b)
        return f'<line x1="{ax:g}" y1="{ay:g}" x2="{bx:g}" y2="{by:g}" '+ ' '.join(f'{k.replace("_","-")}="{v}"' for k,v in attrs.items())+'/>'
    def dot(p,color,label,dx=10,dy=-10):
        x,y=xy(p)
        return f'<circle cx="{x:g}" cy="{y:g}" r="6" fill="{color}"/><text x="{x+dx:g}" y="{y+dy:g}" fill="{color}">{html.escape(label)}</text>'
    block=scene['inner_structure']; enemy=scene['enemy']; kit=scene['medkit']
    parts=['<svg xmlns="http://www.w3.org/2000/svg" width="900" height="720" viewBox="0 0 900 720">',
           '<rect width="900" height="720" fill="#191b20"/>',
           '<style>text{font:15px sans-serif;fill:#ece5d9}.small{font-size:13px}</style>',
           '<text x="40" y="34" style="font-size:23px;font-weight:bold">First encounter room: simple inner structure</text>',
           '<text x="40" y="61">Flat floor 2 / ceiling 10. Full-height opaque block; both routes remain open.</text>',
           f'<polygon points="{points([[120,272],[240,272],[240,368],[120,368]])}" fill="#463b33"/>']
    for wall in scene['segments']:
        if wall.get('area') == 'encounter' and wall.get('kind') == 'outer':
            parts.append(line([wall['x1'],wall['z1']],[wall['x2'],wall['z2']],stroke='#bbb0a0',stroke_width=4))
    parts.append(f'<polygon points="{points(block["polygon"])}" fill="#997858" stroke="#e6c193" stroke-width="3"/>')
    parts.append(f'<polyline points="{points(block["inspection_route"])}" fill="none" stroke="#8dbce8" stroke-width="2" stroke-dasharray="7 5"/>')
    parts.append(dot([enemy['x'],enemy['z']],'#eb987b','Zombie',dx=-63,dy=23))
    parts.append(dot([kit['x'],kit['z']],'#9cdbaf','Medkit'))
    parts.append(dot([120,312],'#e5d779','Entrance',dx=-72,dy=-12))
    parts.append(dot([240,296],'#e5d779','To slime room',dx=12,dy=-8))
    x,y=xy([198,320]);parts.append(f'<text x="{x:g}" y="{y:g}" text-anchor="middle">SOLID</text>')
    parts.extend(['<text x="40" y="646">Blue dashed line: walkaround audit route. Brown block: x184..212, z300..340.</text>',
                  '<text x="40" y="672" class="small">Uses the original chamber outer footprint. Its west entrance is sealed for this four-face experiment.</text>',
                  '<text x="40" y="696" class="small">Source interior steps, lowered ceiling and walkable cavity are intentionally omitted.</text>', '</svg>'])
    destination.write_text('\n'.join(parts)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map',type=Path,default=ROOT/'assets/map.json')
    parser.add_argument('--output',type=Path,default=ROOT/'build/inner-structure')
    parser.add_argument('--wad',type=Path)
    args=parser.parse_args()
    scene=json.loads(args.map.read_text())
    os.environ['E1M1_MAP_PATH']=str(args.map.resolve())
    sys.path.insert(0,str(ROOT/'tools'))
    import movement_reference as movement
    block=scene['inner_structure']; xmin,xmax=block['bounds']['x']; zmin,zmax=block['bounds']['z']
    polygon=[[xmin,zmin],[xmin,zmax],[xmax,zmax],[xmax,zmin]]
    assert block['polygon']==polygon and polygon in scene['holes']
    assert scene['floor_regions'][0]['holes']==[scene['recess_polygon']]+scene['holes']+list(scene['slime']['pools'].values())
    assert block['floor']==scene['outer_floor_height']==2
    assert block['ceiling']==scene['ceiling_height']==10
    faces=[s for s in scene['segments'] if s.get('kind')=='inner']
    assert len(faces)==4
    for face,a,b in zip(faces,polygon,polygon[1:]+polygon[:1]):
        assert [face['x1'],face['z1']]==a and [face['x2'],face['z2']]==b
        assert face['collision'] and face['bottom']==2 and face['top']==10
        assert face['floor']==2 and face['floor_material']==3
    assert len(scene['encounters']) in (2,3) and len(scene['pillars'])==4
    assert not movement.blocked(scene['enemy']['x']*256,scene['enemy']['z']*256)
    assert not movement.blocked(scene['medkit']['x']*256,scene['medkit']['z']*256)

    # Every quarter-unit step along each intended route must retain the square
    # player footprint, including the onward route and both walkaround paths.
    samples=0
    for name,route in [('main',scene['route_world']),('return',scene['return_route_world']),
                       ('inspection',block['inspection_route'])]:
        for a,b in zip(route,route[1:]):
            steps=max(1,math.ceil(math.dist(a,b)*4))
            for i in range(steps+1):
                x,z=[round((a[j]+(b[j]-a[j])*i/steps)*256) for j in range(2)]
                assert not movement.blocked(x,z),('blocked route',name,x/256,z/256)
                samples+=1

    # Exhaustive integer-center connectivity for this room. This proves every
    # sampled reachable pocket connects to the entrance; fractional collision
    # contacts are checked separately immediately below.
    room=next(a for a in scene['areas'] if a['id']=='encounter')['bounds']
    free={(x,z) for x in range(room['x'][0]+3,room['x'][1]-2)
          for z in range(room['z'][0]+3,room['z'][1]-2)
          if not movement.blocked(x*256,z*256)}
    start=(124,312); assert start in free
    reached={start};queue=deque([start])
    while queue:
        x,z=queue.popleft()
        for p in ((x-1,z),(x+1,z),(x,z-1),(x,z+1)):
            if p in free and p not in reached:reached.add(p);queue.append(p)
    assert reached==free,('disconnected room centers',len(free-reached))
    assert {(scene['enemy']['x'],scene['enemy']['z']),
            (scene['medkit']['x'],scene['medkit']['z']),(236,296)}<=reached
    r=scene['player_radius']*256;cx=(xmin+xmax)*128;cz=(zmin+zmax)*128
    # Exact radius contacts blocked; one Q8.8 fraction outside remains free.
    contacts=[(xmin*256-r,cz,-1,0),(xmax*256+r,cz,1,0),
              (cx,zmin*256-r,0,-1),(cx,zmax*256+r,0,1)]
    for x,z,dx,dz in contacts:
        assert movement.blocked(x,z)
        assert not movement.blocked(x+dx,z+dz)
    for x in range(xmin,xmax+1):
        for z in range(zmin,zmax+1):assert movement.blocked(x*256,z*256)
    args.output.mkdir(parents=True,exist_ok=True)
    preview(scene,args.output/'layout.svg')
    report={'mapSha256':hashlib.sha256(args.map.read_bytes()).hexdigest(),
            'renderFaces':len(scene['segments']),'collisionFaces':len(movement.SEGMENTS),
            'innerBounds':block['bounds'],'additionalHeightTransitions':0,
            'routeSamples':samples,'connectedIntegerRoomCenters':len(reached),
            'radiusContactAndOneFractionOutside':'pass','solidInterior':'blocked',
            'enemyAndMedkitReachable':True,'bothWalkaroundRoutesClear':True,
            'source':source_check(args.wad,scene) if args.wad else 'not requested',
            'scope':'Authored geometry/reference collision audit; runtime rendering and AI verified separately.'}
    (args.output/'geometry-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
