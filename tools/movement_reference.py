#!/usr/bin/env python3
"""Extended E1M1 opening, winding passage and encounter room with exact finite-wall collision.

The NES checks segment/AABB overlap and signed line distance. This model uses
polygon containment plus the separating-axis theorem directly in world Q8.8.
No occupancy grid or precomputed frames are used by either implementation.
"""
from __future__ import annotations
import hashlib
import json
import math
import os
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
MAP_PATH = Path(os.environ.get('E1M1_MAP_PATH', SOURCE.parent / 'assets/map.json'))
MAP = json.loads(MAP_PATH.read_text())
SEGMENTS = [s for s in MAP['segments'] if s.get('collision',True)]
RADIUS = MAP['player_radius']
RECESS = MAP['recess']
OUTER_FLOOR_HEIGHT = MAP['outer_floor_height']
RECESS_DEPTH = MAP['recess_depth']
BODY_HEIGHT = MAP['body_height']
EYE_HEIGHT = MAP['eye_height']
CEILING_HEIGHT = MAP['ceiling_height']
MAX_STEP_HEIGHT = MAP['max_step_height']
WORLD_Q8_LIMIT = 1024 * 256
SINE = tuple(round(63.5*math.sin(a*math.tau/256)) for a in range(256))
OFFSETS = (None,64,192,None,128,96,160,128,0,32,224,0,None,64,192,None)


def contains(polygon, x, z):
    """Even-odd containment; independent of winding and convex decomposition."""
    inside = False
    for (ax,az),(bx,bz) in zip(polygon, polygon[1:]+polygon[:1]):
        ax,az,bx,bz = ax*256,az*256,bx*256,bz*256
        if (az > z) != (bz > z):
            # Python fractions are unnecessary: this float is exact enough for
            # this bounded Q8.8 integer scene; contacts are caught by SAT below.
            if x < ax+(bx-ax)*(z-az)/(bz-az):
                inside = not inside
    return inside


def touches_segment(x, z, segment):
    """Exact SAT intersection of a finite segment and an axis-aligned square."""
    r = RADIUS*256
    ax,az,bx,bz = (segment[k]*256 for k in ('x1','z1','x2','z2'))
    if max(ax,bx) < x-r or min(ax,bx) > x+r:
        return False
    if max(az,bz) < z-r or min(az,bz) > z+r:
        return False
    dx,dz = bx-ax,bz-az
    cross = dx*(z-az)-dz*(x-ax)
    return abs(cross) <= r*(abs(dx)+abs(dz))


def collision_segments(pillars=True):
    return SEGMENTS if pillars else [s for s in SEGMENTS if s['kind'] != 'pillar']


def blocked(x, z, *, pillars=True):
    if not 0 <= x < WORLD_Q8_LIMIT or not 0 <= z < WORLD_Q8_LIMIT:
        return True
    if not contains(MAP['outer_polygon'],x,z) or (pillars and any(contains(h,x,z) for h in MAP['holes'])):
        return True
    return any(touches_segment(x,z,s) for s in collision_segments(pillars))


def floor_height(x, z, recess_depth=RECESS_DEPTH, *, pillars=True):
    """Highest support under the whole square; rim/corner contact is upper.

    Strict rectangle containment tests the footprint's four extents. This is
    deliberately expressed in world-Q8.8, independently from the assembly's
    high-byte gates and exact fractional lower-bound comparisons.
    """
    r = RADIUS*256
    lower = (x-r > RECESS['x_min']*256 and x+r < RECESS['x_max']*256 and
             z-r > RECESS['z_min']*256 and z+r < RECESS['z_max']*256)
    return OUTER_FLOOR_HEIGHT-recess_depth if lower else OUTER_FLOOR_HEIGHT


def eye_height(x, z, recess_depth=RECESS_DEPTH, *, pillars=True):
    return floor_height(x,z,recess_depth)+EYE_HEIGHT


def candidate_blocked(x,z,previous_floor,recess_depth=RECESS_DEPTH,
                      ceiling_height=CEILING_HEIGHT,max_step=MAX_STEP_HEIGHT,*,pillars=True):
    floor=floor_height(x,z,recess_depth)
    return (blocked(x,z,pillars=pillars) or floor+BODY_HEIGHT > ceiling_height or
            floor-previous_floor > max_step)


def tick(x,z,angle,buttons,parity,*,recess_depth=RECESS_DEPTH,pillars=True,
         ceiling_height=CEILING_HEIGHT,max_step=MAX_STEP_HEIGHT):
    if not buttons & 0x80 and not parity & 1:
        turn=buttons&3
        angle=(angle+(1 if turn==1 else -1 if turn==2 else 0))&255
    direction=OFFSETS[buttons&(15 if buttons&0x80 else 12)]
    bx=bz=0
    if direction is not None:
        heading=(angle+direction)&255
        candidate=x+SINE[heading]
        if candidate_blocked(candidate,z,floor_height(x,z,recess_depth),recess_depth,ceiling_height,max_step,pillars=pillars):bx=1
        else:x=candidate
        candidate=z+SINE[(heading+64)&255]
        if candidate_blocked(x,candidate,floor_height(x,z,recess_depth),recess_depth,ceiling_height,max_step,pillars=pillars):bz=1
        else:z=candidate
    return x,z,angle,bx,bz


def collision_data():
    result=[]
    for s in SEGMENTS:
        nx,nz=s['nx'],s['nz']
        if nx<0 or (nx==0 and nz<0): nx,nz=-nx,-nz
        modes={(1,0):0,(0,1):1,(1,1):2,(1,-1):3,(2,-1):4}
        assert max(abs(nx),abs(nz))<=16, ('Unsupported collision normal',nx,nz)
        # Signed16 subtraction is unambiguous after the expanded AABB gate.
        plane=nx*s['x1']+nz*s['z1']
        corners=[nx*x+nz*z-plane for x in (min(s['x1'],s['x2'])-RADIUS,max(s['x1'],s['x2'])+RADIUS)
                 for z in (min(s['z1'],s['z2'])-RADIUS,max(s['z1'],s['z2'])+RADIUS)]
        assert max(abs(v) for v in corners)<128, ('Line-distance overflow',s['id'])
        result.append(dict(xmin=max(0,min(s['x1'],s['x2'])-RADIUS),
            xmax=max(s['x1'],s['x2'])+RADIUS,zmin=min(s['z1'],s['z2'])-RADIUS,
            zmax=max(s['z1'],s['z2'])+RADIUS,mode=modes.get((nx,nz),5),nx=nx,nz=nz&255,
            plane=(nx*s['x1']+nz*s['z1'])&255,support=RADIUS*(abs(nx)+abs(nz))))
        result[-1]['zmin']=max(0,result[-1]['zmin'])
    return result


def write_assets(destination,recess_depth=RECESS_DEPTH,*,ceiling_height=CEILING_HEIGHT,max_step=MAX_STEP_HEIGHT):
    destination=Path(destination); destination.mkdir(parents=True,exist_ok=True)
    assert 0 <= recess_depth <= OUTER_FLOOR_HEIGHT
    assert max_step >= 0 and ceiling_height < 255
    assert all(isinstance(v,int) and 0 <= v < 1024
               for polygon in [MAP['outer_polygon'],MAP['recess_polygon'],*MAP['holes']]
               for p in polygon for v in p), 'Authored coordinates must be integral 0..1023'
    spawn=MAP['spawn']; data=collision_data()
    assert not blocked(spawn['x_q8_8'],spawn['z_q8_8'])
    assert all(not blocked(round(p['x']*256),round(p['z']*256)) for p in MAP['audit_poses'] if not p.get('geometry_only',False))
    assert len(MAP['pillars']) == 4
    # All points inside each source pillar overlap its radius-two SAT bands.
    assert all(p['x_max']-p['x_min'] <= 2*RADIUS and
               p['z_max']-p['z_min'] <= 2*RADIUS for p in MAP['pillars'])
    lines=['; Generated from assets/map.json. Exact walls, pillars and recess support.',
        f'OUTER_FLOOR_HEIGHT = {OUTER_FLOOR_HEIGHT}',f'RECESS_DEPTH = {recess_depth}',
        f'RECESS_X_MIN = {RECESS["x_min"]}',f'RECESS_X_MAX = {RECESS["x_max"]}',
        f'RECESS_Z_MIN = {RECESS["z_min"]}',f'RECESS_Z_MAX = {RECESS["z_max"]}',
        f'PLAYER_EYE_HEIGHT = {EYE_HEIGHT}',f'PLAYER_BODY_HEIGHT = {BODY_HEIGHT}',
        f'SCENE_CEILING = {ceiling_height}',f'MAX_STEP_HEIGHT = {max_step}',
        f'SPAWN_FLOOR = {floor_height(spawn["x_q8_8"],spawn["z_q8_8"],recess_depth)}',
        f'SPAWN_X = {spawn["x_q8_8"]}',f'SPAWN_Z = {spawn["z_q8_8"]}',
        f'SPAWN_ANGLE = {spawn["angle"]}',f'COLLISION_COUNT = {len(data)}',
        f'PLAYER_RADIUS = {RADIUS}',
        f'SCENE_MIN_X = {min(x for x,z in MAP["outer_polygon"])}',
        f'SCENE_MAX_X = {max(x for x,z in MAP["outer_polygon"])}',
        f'SCENE_MIN_Z = {min(z for x,z in MAP["outer_polygon"])}',
        f'SCENE_MAX_Z = {max(z for x,z in MAP["outer_polygon"])}']
    for field in ('xmin','xmax','zmin','zmax'):
        lines.extend([f'collision_{field}_lo:','.byte '+','.join(str(d[field]&255) for d in data)])
        lines.extend([f'collision_{field}_hi:','.byte '+','.join(str(d[field]>>8) for d in data)])
    for field in ('mode','plane','support','nx','nz'):
        lines.extend([f'collision_{field}:','.byte '+','.join(str(d[field]) for d in data)])
    lines.append('movement_sine:')
    for i in range(0,256,16): lines.append('.byte '+','.join(str(v&255) for v in SINE[i:i+16]))
    path=destination/'movement-data.inc'; path.write_text('\n'.join(lines)+'\n')
    return dict(path=str(path),mapSha256=hashlib.sha256(MAP_PATH.read_bytes()).hexdigest(),
        segments=len(data),renderFaces=len(MAP['segments']),pillarCount=len(MAP['pillars']),recessDepth=recess_depth,
        outerFloor=OUTER_FLOOR_HEIGHT,recessFloor=OUTER_FLOOR_HEIGHT-recess_depth,
        eyeHeightAboveFloor=EYE_HEIGHT,bodyHeight=BODY_HEIGHT,ceilingHeight=ceiling_height,
        maxStepHeight=max_step,support='highest floor touched by square; recess only under strictly contained footprint',
        playerFootprint=f'axis-aligned square, radius {RADIUS} world units',
        collision='finite segments, global Q16.8 AABBs and proved local modular Q8.8 line distance; axis-separated sliding',
        coordinateBytes=3,coordinateFractionBits=8,supportedIntegerMaximum=1023,
        trigBytes=256,collisionTableBytes=13*len(data))
