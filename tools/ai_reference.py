"""Preserved encounter pursuit and conservative visibility for the extension.

The original outer sight domain remains X-monotone. Existing lower/upper
constraints reject the winding passage, and exact finite rectangle clipping
rejects the new full-height interior block. A radius-two expanded box also
blocks latched pursuit steps. The second encounter retains its prior kernel;
the third is confined to the kernel of the flat pre-exit room.
"""
import json, math, os
from fractions import Fraction
from pathlib import Path
HERE=Path(__file__).resolve().parent
MAP=json.loads(Path(os.environ.get('E1M1_MAP_PATH',HERE.parent/'assets/map.json')).read_text())
OX,OZ=MAP.get('coordinate_offset',[0,0])
LEGACY_LOCAL_POLYGON=((8,20),(24,20),(40,8),(64,8),(80,20),(88,20),
    (88,104),(88,128),(92,140),(104,144),(120,144),(120,112),
    (240,112),(240,208),(120,208),(120,160),(104,160),(76,148),
    (72,144),(72,104),(40,104),(24,96),(8,96))
LEGACY_POLYGON=[[x+OX,z+OZ] for x,z in LEGACY_LOCAL_POLYGON]
SIGHT_POLYGON=MAP.get('legacy_ai_polygon',LEGACY_POLYGON)
BOUNDS=((132+OX)*256,(238+OX)*256,(114+OZ)*256,(206+OZ)*256)
# The authored encounter metadata is also used to generate the assembly LOS
# bounds, so steering and sight cannot silently disagree after an area change.
ENCOUNTER_BOUNDS=tuple((a*256,b*256,c*256,d*256)
    for a,b,c,d in (e['movement_bounds'] for e in MAP['encounters']))
assert len(ENCOUNTER_BOUNDS)==3 and ENCOUNTER_BOUNDS[0]==BOUNDS
SPEED=8
CADENCE=8
INNER=MAP.get('inner_structure')
INNER_BOUNDS=(tuple(INNER['bounds']['x'])+tuple(INNER['bounds']['z'])) if INNER else None
INNER_RADIUS=2


def inner_blocks_sight(x,z,px,pz):
    """Independent exact segment/slab clipping, including tangent contacts."""
    if INNER_BOUNDS is None:return False
    enter,leave=Fraction(0),Fraction(1)
    for a,b,low,high in ((x,px,*INNER_BOUNDS[:2]),(z,pz,*INNER_BOUNDS[2:])):
        low*=256;high*=256
        if a==b:
            if a<low or a>high:return False
            continue
        first,last=sorted((Fraction(low-a,b-a),Fraction(high-a,b-a)))
        enter=max(enter,first);leave=min(leave,last)
        if enter>leave:return False
    return True


def inner_blocks_movement(x,z,active=0):
    if active or INNER_BOUNDS is None:return False
    a,b,c,d=INNER_BOUNDS;r=INNER_RADIUS
    return (a-r)*256<=x<=(b+r)*256 and (c-r)*256<=z<=(d+r)*256

def constraints():
    polygon=SIGHT_POLYGON;right=max(x for x,z in polygon)
    first=next(i for i,p in enumerate(polygon)if p[0]==right)
    last=max(i for i,p in enumerate(polygon)if p[0]==right)
    lower={};upper={}
    for x,z in polygon[:first+1]:lower[x]=max(z,lower.get(x,z))
    for x,z in polygon[last:]:upper[x]=min(z,upper.get(x,z))
    return [(x,z,kind)for x,z,kind in sorted([(x,z,0)for x,z in lower.items()]+[(x,z,1)for x,z in upper.items()],key=lambda p:(-p[0],p[2]))if x<122+OX]
CONSTRAINTS=constraints()

def has_los(x,z,px,pz,active=0):
    if active==1:
        a,b,c,d=ENCOUNTER_BOUNDS[1]
        return a<=x<=b and c<=z<=d and (264+OX)*256<=px<=(352+OX)*256 and (8+OZ)*256<=pz<=(100+OZ)*256
    if active==2:
        a,b,c,d=ENCOUNTER_BOUNDS[2]
        return a<=x<=b and c<=z<=d and (256+OX)*256<=px<=(336+OX)*256 and (-104+OZ)*256<=pz<=(-40+OZ)*256
    if not (BOUNDS[0]<=x<=BOUNDS[1] and BOUNDS[2]<=z<=BOUNDS[3]):return False
    if not ((8+OX)*256<=px<=(240+OX)*256 and (8+OZ)*256<=pz<=(208+OZ)*256):return False
    if inner_blocks_sight(x,z,px,pz):return False
    if px>=(120+OX)*256:return True
    dx=x-px
    for cx,cz,upper in CONSTRAINTS:
        if cx*256<px:continue
        value=(z-cz*256)*dx+(pz-z)*(x-cx*256)
        if value==0 or (value>0)==bool(upper):return False
    return True

def steering(x,z,px,pz):
    ax,az=(abs(px-x)+128)//256,(abs(pz-z)+128)//256
    if not max(ax,az):return 0,0
    # Shared shift retains bounded proportional steering for remote inputs.
    # All current successful LOS positions have both magnitudes below256.
    while max(ax,az)>255:ax>>=1;az>>=1
    vx,vz=(8,8*az//ax)if ax>=az else(8*ax//az,8)
    return vx*(1 if px>=x else-1),vz*(1 if pz>=z else-1)

def contact(x,z,px,pz,radius=9):
    dx,dz=abs(x-px),abs(z-pz)
    if dx>=radius*256 or dz>=radius*256:return False
    return (dx//16)**2+(dz//16)**2<(radius*16)**2

def move(x,z,px,pz,vx,vz,active=0):
    a,b,c,d=ENCOUNTER_BOUNDS[active]
    q=x+vx
    if a<=q<=b and not contact(q,z,px,pz) and not inner_blocks_movement(q,z,active):x=q
    q=z+vz
    if c<=q<=d and not contact(x,q,px,pz) and not inner_blocks_movement(x,q,active):z=q
    return x,z

def validate_sight_domain():
    """Prove the first sight domain has only its explicitly handled obstacle.

    A segment joining positions with x<=240 never enters x>240. The old outer
    boundary and pillars remain, and the only admitted additional hole is the
    full-height inner rectangle checked separately by exact segment clipping.
    """
    assert SIGHT_POLYGON==LEGACY_POLYGON, 'The original AI sight polygon changed'
    polygon=MAP['outer_polygon']
    expected=[]
    for point in LEGACY_POLYGON:
        expected.append(point)
        if point==[240+OX,112+OZ]:
            expected.extend([[240+OX,128+OZ],[240+OX,144+OZ]])
    assert [p for p in polygon if p[0]<=240+OX]==expected, 'Extension overlaps the legacy AI domain'
    assert all(x>=240+OX for x,z in polygon if [x,z] not in expected)
    legacy_holes=[[[x+OX,z+OZ],[x+OX,z+4+OZ],[x+4+OX,z+4+OZ],[x+4+OX,z+OZ]]
                  for x,z in ((32,40),(68,40),(32,76),(68,76))]
    inner_holes=[]
    if INNER_BOUNDS:
        a,b,c,d=INNER_BOUNDS
        assert 132+OX<a<b<238+OX and 114+OZ<c<d<206+OZ
        assert INNER['floor']==MAP['outer_floor_height'] and INNER['ceiling']==MAP['ceiling_height']
        inner_holes=[[[a,c],[a,d],[b,d],[b,c]]]
        assert not inner_blocks_movement(MAP['enemy']['x']*256,MAP['enemy']['z']*256)
    assert MAP['holes']==legacy_holes+inner_holes, 'Unproved AI obstacle'
    edges=[(a,b) for loop in [LEGACY_POLYGON]+legacy_holes+inner_holes for a,b in zip(loop,loop[1:]+loop[:1])]
    def on_edge(point,a,b):
        x,z=point;ax,az=a;bx,bz=b
        return ((bx-ax)*(z-az)==(bz-az)*(x-ax) and
                min(ax,bx)<=x<=max(ax,bx) and min(az,bz)<=z<=max(az,bz))
    for segment in MAP['segments']:
        if not segment.get('collision',True):continue
        a=(segment['x1'],segment['z1']);b=(segment['x2'],segment['z2'])
        if min(a[0],b[0])<240+OX:
            assert any(on_edge(a,c,d) and on_edge(b,c,d) for c,d in edges), ('New wall enters AI sight domain',segment['id'])
    extensions=[a for a in MAP['areas'] if a.get('ai_visibility_domain')=='extension']
    assert {'next_passage','zigzag_room'} <= {a['id'] for a in extensions}
    assert all(a.get('enemy_pursuit_allowed') is (a['id']=='zigzag_room') for a in extensions)
    room=next(a for a in MAP['areas'] if a['id']=='pre_exit')
    assert room['ai_visibility_domain']=='pre_exit' and room['enemy_pursuit_allowed']
    assert tuple(v*256 for v in room['enemy_pursuit_bounds'])==ENCOUNTER_BOUNDS[2]
    a,b,c,d=room['enemy_pursuit_bounds'];polygon=room['polygon']
    margins=[(v[0]-u[0])*(z-u[1])-(v[1]-u[1])*(x-u[0])
        for u,v in zip(polygon,polygon[1:]+polygon[:1])
        for x in (a-1,b+1) for z in (c-1,d+1)]
    assert min(margins)>0, 'Third sprite leaves the pre-exit room visibility kernel'
    assert MAP['door']['z']==room['bounds']['z'][1]==120
    return dict(legacySightPolygon=LEGACY_POLYGON,extensionHalfPlaneX=240+OX,
                doorway=[[240+OX,128+OZ],[240+OX,144+OZ]],
                innerOccluderBounds=INNER_BOUNDS,innerMovementRadius=INNER_RADIUS,
                thirdRoomKernelMinimumCrossProduct=min(margins),
                proof='Legacy rays stay in x<=240+origin. Exact finite segment/rectangle clipping excludes the new full-height inner block; original pillar holes and outer boundary remain unchanged')

def write_assets(directory):
    assert MAP['player_radius']==2 and MAP['enemy']['contact_radius']==8
    domain=validate_sight_domain()
    polygon=SIGHT_POLYGON; first=next(i for i,p in enumerate(polygon)if p[0]==240+OX);last=max(i for i,p in enumerate(polygon)if p[0]==240+OX)
    assert all(a[0]<=b[0]for a,b in zip(polygon[:first+1],polygon[1:first+1]))
    assert all(a[0]>=b[0]for a,b in zip(polygon[last:],polygon[last+1:]))
    assert all([x+OX,z+OZ] in polygon for x,z in ([120,112],[240,112],[240,208],[120,208],[120,144],[120,160]))
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    lines=['; Preserved X-monotone legacy sight constraints; extension players are conservatively rejected.',f'ZOMBIE_AI_CONSTRAINTS = {len(CONSTRAINTS)}',f'AI_ORIGIN_X = {OX}',f'AI_ORIGIN_Z = {OZ}']
    lines += [f'AI_INNER_ENABLED = {int(INNER_BOUNDS is not None)}']
    if INNER_BOUNDS:
        for field,value in zip(('X_MIN','X_MAX','Z_MIN','Z_MAX'),INNER_BOUNDS):
            origin=OX if field.startswith('X') else OZ
            lines += [f'AI_INNER_{field} = {value-origin}']
            expanded=value+(-INNER_RADIUS if field.endswith('MIN') else INNER_RADIUS)
            lines += [f'AI_INNER_MOVE_{field} = {expanded}']
        assert (INNER_BOUNDS[0]-INNER_RADIUS)//256==(INNER_BOUNDS[1]+INNER_RADIUS)//256
        assert (INNER_BOUNDS[2]-INNER_RADIUS)//256==(INNER_BOUNDS[3]+INNER_RADIUS)//256
    for field,values in [('x',[p[0]-OX for p in CONSTRAINTS]),('z',[p[1]-OZ for p in CONSTRAINTS]),('upper',[p[2]for p in CONSTRAINTS])]:lines +=['zombie_ai_corner_'+field+':','.byte '+','.join(map(str,values))]
    for index,field in enumerate(('x_min','x_max','z_min','z_max')):
        for part,shift in (('lo',8),('hi',16)):
            lines += ['zombie_ai_'+field+'_'+part+':','.byte '+','.join(str((b[index]>>shift)&255) for b in ENCOUNTER_BOUNDS)]
    (directory/'zombie-ai-data.inc').write_text('\n'.join(lines)+'\n')
    return dict(speedQ8=SPEED,decisionSimulationTicks=CADENCE,confinementQ8=BOUNDS,stopRadius=9,contactRadius=8,
        los='Actor0 retains legacy constraints plus exact inner-block occlusion; actor1 accepts legal player centers in its zigzag room; actor2 accepts legal player centers in the pre-exit room including its entry neck. Both later movement boxes are inside their room visibility kernels; actors cannot attack through the closed Z120 door.',
        constraints=CONSTRAINTS,visibilityDomainProof=domain,extensionPursuit=True,encounterBoundsQ8=ENCOUNTER_BOUNDS)
