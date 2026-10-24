"""Dry starting placements and useful ammunition in the complete E1M1 route."""
from __future__ import annotations
import copy
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OFFSET = (0,160)
BOUNDS = ((132,238,114,206),(280,296,44,74),(282,310,-84,-68))
SPAWNS = ((176,152),(294,58),(296,-76))
GATE = dict(forward_x=248, reverse_x=244, reverse_z_min=8)
THIRD_GATE = dict(forward_z=-32, reverse_z=-24)
THIRD_LOS = (256,336,-104,-40)
AMMO = dict(x=282,z=90,floor=2,pickup_radius=3.5,amount=10,maximum=99,
    kind='collectible_ammo',at_full_ammo='remain',encounter_id=1,
    location='Dry entrance apron of the zigzag room, forward of the return-wall corner and before the second soldier',
    width=2,height=1.5,blocking=False)
AMMO_APPROACH = [[288,112],[290,96],[282,90]]
ROUTE = [[152,152],[172,152],[172,132],[220,132],[228,136],[244,136],[260,130],[276,124],
         [288,112],[290,96],[296,80],[304,56],[304,32],[296,16],[296,12]]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shared_geometry():
    import map_math
    return map_math


def select(active,x,z,offset=OFFSET):
    """Two hysteresis gates select one of three independently saved actors."""
    x-=offset[0]*256
    z-=offset[1]*256
    if active==0 and x>=GATE['forward_x']*256:return 1
    if active==1 and z<=THIRD_GATE['forward_z']*256:return 2
    if active==1 and z>=GATE['reverse_z_min']*256 and x<=GATE['reverse_x']*256:return 0
    if active==2 and z>=THIRD_GATE['reverse_z']*256:return 1
    return active


def local_scene(scene):
    """Normalize the fields consumed by the encounter safety proofs."""
    scene=copy.deepcopy(scene)
    ox,oz=scene.get('coordinate_offset',[0,0])
    def point(p):return [p[0]-ox,p[1]-oz]
    def bounds(b):return [b[0]-ox,b[1]-ox,b[2]-oz,b[3]-oz]
    scene['outer_polygon']=[point(p) for p in scene['outer_polygon']]
    scene['holes']=[[point(p) for p in h] for h in scene['holes']]
    for segment in scene['segments']:
        for key in ('x1','x2'):segment[key]-=ox
        for key in ('z1','z2'):segment[key]-=oz
        segment['plane']-=segment['nx']*ox+segment['nz']*oz
    for area in scene['areas']:
        if 'polygon' in area:
            area['polygon']=[point(p) for p in area['polygon']]
        if 'bounds' in area:
            area['bounds']['x']=[v-ox for v in area['bounds']['x']]
            area['bounds']['z']=[v-oz for v in area['bounds']['z']]
        if 'enemy_pursuit_bounds' in area:
            area['enemy_pursuit_bounds']=bounds(area['enemy_pursuit_bounds'])
    for portal in scene['portals']:
        portal['a']=point(portal['a']);portal['b']=point(portal['b'])
    for actor in scene['encounters']:
        actor['x']-=ox;actor['z']-=oz
        actor['movement_bounds']=bounds(actor['movement_bounds'])
    for key in ('enemy','medkit','ammo'):
        scene[key]['x']-=ox;scene[key]['z']-=oz
    scene['slime']['pools']={key:[point(p) for p in polygon]
        for key,polygon in scene['slime']['pools'].items()}
    scene['extension']['route_world']=[point(p) for p in scene['extension']['route_world']]
    scene['coordinate_offset']=[0,0]
    return scene


def second_los(x,z,px,pz,offset=OFFSET):
    ox,oz=offset; a,b,c,d=BOUNDS[1]
    return ((a+ox)*256<=x<=(b+ox)*256 and (c+oz)*256<=z<=(d+oz)*256 and
            (264+ox)*256<=px<=(352+ox)*256 and (8+oz)*256<=pz<=(100+oz)*256)


def third_los(x,z,px,pz,offset=OFFSET):
    """Player must be legal; the actor box lies in the whole room's kernel."""
    ox,oz=offset; a,b,c,d=BOUNDS[2]; pa,pb,pc,pd=THIRD_LOS
    return ((a+ox)*256<=x<=(b+ox)*256 and (c+oz)*256<=z<=(d+oz)*256 and
            (pa+ox)*256<=px<=(pb+ox)*256 and (pc+oz)*256<=pz<=(pd+oz)*256)


def incoming_visibility(scene,footprint_bounds=None):
    """Bound every pre-activation ray through both connecting portals.

    An exterior camera must first cross the encounter-room exit at X240,
    Z128..144. Those crossing points are the west edge of next_passage.
    Thus this exact passage-polygon bound also covers every earlier camera;
    using the entire first-room polygon would admit rays through its walls.
    """
    def clip(polygon,axis,bound,less):
        result=[]
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            inside_a=a[axis]<=bound if less else a[axis]>=bound
            inside_b=b[axis]<=bound if less else b[axis]>=bound
            if inside_a:result.append(a)
            if inside_a!=inside_b:
                t=(Fraction(bound)-a[axis])/(b[axis]-a[axis])
                result.append(tuple(a[i]+t*(b[i]-a[i]) for i in range(2)))
        return result
    passage=next(a['polygon'] for a in scene['areas'] if a['id']=='next_passage')
    first_portal=next(p for p in scene['portals'] if p['id']=='encounter_to_next_passage')
    assert first_portal['a']==[240,128] and first_portal['b']==[240,144]
    assert [240,128] in passage and [240,144] in passage
    assert min(x for x,z in passage)==240 and min(z for x,z in passage)==100
    assert 240<=GATE['reverse_x']<GATE['forward_x']<264
    polygon=[tuple(map(Fraction,p)) for p in passage]
    cameras=clip(polygon,0,GATE['forward_x'],True)
    if footprint_bounds is None:
        a,b,c,d=BOUNDS[1]
        footprint_bounds=[a-1,b+1,c-1,d+1]
    a,b,c,d=footprint_bounds
    values=[((cx*(100-az)+ax*(cz-100))/(cz-az),(cx,cz),(ax,az))
            for cx,cz in cameras for ax in (a,b) for az in (c,d)]
    maximum,camera,actor=max(values)
    portal=next(p for p in scene['portals'] if p['id']=='next_passage_to_zigzag')
    assert portal['a']==[280,100] and portal['b']==[302,100]
    assert maximum<280, 'Incoming footprint can be visible before activation'
    return dict(passed=True,actorFootprintBounds=footprint_bounds,
        maximumRayXAtRoomThreshold=str(maximum),minimumClearanceLeftOfPortal=str(280-maximum),
        worstBoundaryCamera=[str(v) for v in camera],worstActorFootprintCorner=list(actor),
        vertexAndActorCornerCases=len(values),
        passageCameraPolygon=[[str(v) for v in p] for p in cameras],
        upstreamPortal=[first_portal['a'],first_portal['b']],
        proof='Any visible ray from an earlier room first crosses the unique X240/Z128..144 opening, which is contained in the checked passage polygon. After multiplying by the positive ray denominator, the room-threshold inequality is affine in each camera and actor coordinate separately; clipped-polygon vertices and actor-box corners bound all such rays continuously. Radius-two camera clearance only reduces this domain. The reverse threshold lies farther upstream and is covered by the same bound.')


def distance2_to_segment(point,a,b):
    dx,dz=b[0]-a[0],b[1]-a[1]
    t=max(Fraction(0),min(Fraction(1),Fraction((point[0]-a[0])*dx+(point[1]-a[1])*dz,dx*dx+dz*dz)))
    return (point[0]-a[0]-t*dx)**2+(point[1]-a[1]-t*dz)**2


def dry_hull(scene,vertices):
    """Exact edge/containment proof for a convex swept player or sprite hull."""
    common=shared_geometry()
    hull=common.hull(vertices)
    for name,pool in scene['slime']['pools'].items():
        assert not any(common.inside(pool,p) for p in hull),('hull enters slime',name,hull)
        assert not any(common.inside(hull,p) for p in pool),('hull contains slime',name,hull)
        for a,b in zip(pool,pool[1:]+pool[:1]):
            assert not common.touches_hull(hull,a,b),('hull touches slime',name,a,b)
    return hull


def validate_ammo(scene):
    """Prove the pickup circle and a radius-two player approach stay wall-clear."""
    common=shared_geometry()
    assert scene['ammo']==AMMO, 'Authored ammo placement or behavior changed'
    ammo=scene['ammo'];point=(ammo['x'],ammo['z']);radius=ammo['pickup_radius']
    room=next(a for a in scene['areas'] if a['id']=='zigzag_room')
    assert room['floor']==ammo['floor']==2 and room['flat']
    assert common.inside(room['polygon'],point) and not common.blocked(scene,*point)
    walls=[s for s in scene['segments'] if s['collision']]
    distances=[]
    for wall in walls:
        ax,az,bx,bz=(wall[k] for k in ('x1','z1','x2','z2'))
        distance2=distance2_to_segment(point,(ax,az),(bx,bz))
        assert distance2>radius*radius, ('ammo pickup circle touches wall',wall['id'])
        distances.append((distance2,wall['id']))
    assert AMMO_APPROACH[0] in ROUTE and AMMO_APPROACH[-1]==list(point)
    swept_checks=0
    for a,b in zip(AMMO_APPROACH,AMMO_APPROACH[1:]):
        swept=dry_hull(scene,[(p[0]+dx,p[1]+dz) for p in (a,b) for dx in (-2,2) for dz in (-2,2)])
        for wall in walls:
            assert not common.touches_hull(swept,(wall['x1'],wall['z1']),(wall['x2'],wall['z2'])),('ammo approach',wall['id'])
            swept_checks+=1
    assert all(not common.blocked(scene,*p) for p in AMMO_APPROACH)
    a,b,c,d=BOUNDS[1]
    enemy_gap2=max(a-point[0],0,point[0]-b)**2+max(c-point[1],0,point[1]-d)**2
    assert enemy_gap2>(radius+8)**2, 'Ammo pickup circle overlaps expanded enemy contact bounds'
    nearest2,nearest_wall=min(distances)
    slime_distances=[]
    for name,pool in scene['slime']['pools'].items():
        assert not common.inside(pool,point),('ammo in slime',name)
        for a,b in zip(pool,pool[1:]+pool[:1]):
            d2=distance2_to_segment(point,a,b)
            assert d2>radius*radius,('pickup circle touches slime',name,a,b)
            slime_distances.append(d2)
    visibility=incoming_visibility(scene,[point[0]-1,point[0]+1,point[1]-1,point[1]+1])
    visibility['itemFootprintBounds']=visibility.pop('actorFootprintBounds')
    return dict(passed=True,position=list(point),floor=2,pickupRadius=radius,
        pickupCircleWallClear=True,nearestWall=nearest_wall,nearestWallDistanceSquared=str(nearest2),
        radiusTwoApproach=AMMO_APPROACH,continuousSweptRadius2Checks=swept_checks,
        pickupCircleEntirelyDry=True,nearestSlimeDistanceSquared=str(min(slime_distances)),
        completeRadiusTwoApproachDry=True,
        reachableFromPreservedRoute=True,nonblocking=True,
        squaredDistanceToEnemyMovementBounds=enemy_gap2,enemyContactHalfWidth=8,
        pickupCircleClearOfEnemyContactBounds=True,incomingItemHiddenBeforeActivation=visibility)


def validate_third(scene,original):
    """Prove continuous room sight, doorway clearance and walkaround routes."""
    common=shared_geometry(); ox,oz=OFFSET
    area=next(a for a in scene['areas'] if a['id']=='pre_exit')
    room=area['polygon']; a,b,c,d=BOUNDS[2]
    assert area['enemy_pursuit_allowed'] and area['ai_visibility_domain']=='pre_exit'
    assert tuple(area['enemy_pursuit_bounds'])==BOUNDS[2]
    assert tuple(area['bounds']['x']+area['bounds']['z'])==THIRD_LOS
    assert area['flat'] and area['floor']==2 and area['ceiling']==10
    assert a<=SPAWNS[2][0]<=b and c<=SPAWNS[2][1]<=d
    sprite=[(x,z) for x in (a-1,b+1) for z in (c-1,d+1)]
    margins=[common.cross(u,v,p) for u,v in zip(room,room[1:]+room[:1]) for p in sprite]
    assert min(margins)>0, 'Third actor sprite leaves room visibility kernel'
    # Any legal point accepted by the cheap LOS rectangle is in this room:
    # every other authored area's bounds has disjoint interior.
    pa,pb,pc,pd=THIRD_LOS
    for other in scene['areas']:
        if other['id']=='pre_exit':continue
        polygon=other.get('polygon')
        if polygon:
            xs,zs=zip(*polygon)
            assert max(xs)<=pa or min(xs)>=pb or max(zs)<=pc or min(zs)>=pd, ('LOS domain intersects another room',other['id'])
    walls=[s for s in scene['segments'] if s['collision']]
    contact=common.hull([(x,z) for x in (a-8,b+8) for z in (c-8,d+8)])
    assert all(common.inside(room,p) for p in contact)
    for wall in walls:
        assert not common.touches_hull(contact,(wall['x1'],wall['z1']),(wall['x2'],wall['z2'])),('third contact touches wall',wall['id'])
    # Radius-two routes pass either side even while the actor occupies any
    # permitted position. The door is assumed opened before crossing Z120.
    routes=[[[296,-44],[296,-56],[x,-56],[x,-96],[296,-96],[296,-108]] for x in (268,324)]
    second_bypass=[[274,92],[290,92],[316,80],[316,48],[320,24],[296,20],[296,-24]]
    checks=0
    for index,route in enumerate(routes+[second_bypass]):
        bounds=BOUNDS[2 if index<2 else 1]
        obstacle=common.hull([(x,z) for x in (bounds[0]-8,bounds[1]+8) for z in (bounds[2]-8,bounds[3]+8)])
        for u,v in zip(route,route[1:]):
            assert not common.blocked(scene,*u) and not common.blocked(scene,*v)
            swept=common.hull([(p[0]+dx,p[1]+dz) for p in (u,v) for dx in (-2,2) for dz in (-2,2)])
            for wall in walls:
                assert not common.touches_hull(swept,(wall['x1'],wall['z1']),(wall['x2'],wall['z2'])),('third route touches wall',index,u,v,wall['id'])
                checks+=1
            # Contact radius already applies to player center, so do not
            # inflate it again by the wall-collision footprint.
            assert not common.touches_hull(obstacle,u,v),('route enters actor contact bounds',index,u,v)
    authored=original['encounter_handoff']['third']
    assert authored['forward_z']==THIRD_GATE['forward_z']+oz
    assert authored['reverse_z']==THIRD_GATE['reverse_z']+oz
    assert authored['player_los_bounds']==[pa+ox,pb+ox,pc+oz,pd+oz]
    assert authored['hysteresis_width']==THIRD_GATE['reverse_z']-THIRD_GATE['forward_z']==8
    assert original['door']['z']==pd+oz==120
    assert original['exit_extension']['extra_actors']==1
    # Exact 16.8 threshold boundaries, including one fractional quantum.
    qx=(296+ox)*256; forward=authored['forward_z']*256; reverse=authored['reverse_z']*256
    cases=[(1,forward+1,1),(1,forward,2),(2,forward,2),(2,reverse-1,2),(2,reverse,1)]
    for state,z,want in cases:assert select(state,qx,z)==want
    return dict(passed=True,spawn=[SPAWNS[2][0]+ox,SPAWNS[2][1]+oz],
        movementBounds=[a+ox,b+ox,c+oz,d+oz],playerLosBounds=authored['player_los_bounds'],
        spriteFootprintInsideWholeRoomVisibilityKernel=True,minimumEdgeCrossProduct=min(margins),
        actorContactBoundsEntirelyInRoom=True,doorPlaneClearanceFromContactBounds=120-(d+oz+8),
        southOpeningClearanceFromContactBounds=c+oz-8-56,
        walkaroundRoutes=[[[x+ox,z+oz] for x,z in route] for route in routes],
        secondAliveBypass=[[x+ox,z+oz] for x,z in second_bypass],continuousSweptRadius2Checks=checks,
        forwardZ=authored['forward_z'],reverseZ=authored['reverse_z'],fractionalGateCases=len(cases),
        closedDoorSafety='The opaque door hides the sprite; LOS accepts only legal players on the room side at Z<=120, so rays never cross the closed door plane. The state handoff occurs earlier, at Z<=128.',
        visibilityProof='The expanded actor rectangle is strictly inside every inward room-edge halfplane, hence inside the polygon visibility kernel. Every legal player point accepted by the LOS bounding rectangle is in this room. This proves continuous sight segments, including fractional coordinates and the entry neck.',
        handoffLimitation='Only one actor simulates/renders. If an earlier soldier survives, its saved state is restored on return, but an outgoing actor may visibly disappear when crossing a handoff after the door has opened.')


def validate_layout(scene):
    """Validate authored placements, activation, approach and contact safety."""
    common=shared_geometry()
    assert tuple(scene.get('coordinate_offset',[]))==OFFSET
    original=scene
    scene=local_scene(scene)
    assert scene['extension']['route_world']==ROUTE
    assert [tuple(e['movement_bounds']) for e in scene['encounters']]==list(BOUNDS)
    assert [(e['x'],e['z']) for e in scene['encounters']]==list(SPAWNS)
    assert scene['ammo']==AMMO
    for index,actor in enumerate(scene['encounters']):
        assert actor['id']==index and actor['health']==3
        assert actor['persistent'] and actor['active_at_once']==1
    assert (scene['enemy']['x'],scene['enemy']['z'])==SPAWNS[0]
    assert scene['medkit']['encounter_id']==0
    first_areas={'opening','passage','encounter','next_passage','zigzag_room'}
    for area in scene['areas']:
        if area['id'] not in first_areas and area['id']!='pre_exit':
            assert area.get('enemy_pursuit_allowed') is False
    room=next(a['polygon'] for a in scene['areas'] if a['id']=='zigzag_room')
    for radius in (1,):
        a,b,c,d=BOUNDS[1]
        for point in ((x,z) for x in (a-radius,b+radius) for z in (c-radius,d+radius)):
            assert all(common.cross(u,v,point)>=0 for u,v in zip(room,room[1:]+room[:1])),('actor outside room kernel',radius,point)
    walls=[s for s in scene['segments'] if s['collision']]
    a,b,c,d=BOUNDS[1]
    expanded=common.hull([(x,z) for x in (a-8,b+8) for z in (c-8,d+8)])
    assert all(common.inside(room,p) for p in expanded), 'Enemy contact footprint leaves room'
    for wall in walls:
        assert not common.touches_hull(expanded,(wall['x1'],wall['z1']),(wall['x2'],wall['z2'])),('enemy contact bounds touch wall',wall['id'])
    x,z=SPAWNS[1]
    spawn_feet=dry_hull(scene,[(x+dx,z+dz) for dx in (-1,1) for dz in (-1,1)])
    swept_checks=0
    for a,b in zip(ROUTE,ROUTE[1:]):
        assert not common.blocked(scene,*a) and not common.blocked(scene,*b),('route endpoint',a,b)
        swept=common.hull([(p[0]+dx,p[1]+dz) for p in (a,b) for dx in (-2,2) for dz in (-2,2)])
        for wall in walls:
            assert not common.touches_hull(swept,(wall['x1'],wall['z1']),(wall['x2'],wall['z2'])),('swept route',a,b,wall['id'])
            swept_checks+=1
    ox,oz=OFFSET
    expected_gate=dict(forward_x=GATE['forward_x']+ox,reverse_x=GATE['reverse_x']+ox,reverse_z_min=GATE['reverse_z_min']+oz)
    assert all(original['encounter_handoff'][k]==v for k,v in expected_gate.items())
    # New floor west of the old X gate is wholly south of the old map cap.
    # The reverse-Z condition prevents reactivating encounter 0 here.
    exit_areas=[a for a in original['areas'] if a['id'] not in first_areas]
    assert exit_areas and all(z<=8+oz for area in exit_areas for x,z in area['polygon'])
    return dict(passed=True,coordinateOffset=list(OFFSET),
        actorBounds=[e['movement_bounds'] for e in original['encounters']],
        actorPlacements=[[e['x'],e['z']] for e in original['encounters']],
        encounterStateRulesValidated=True,
        forwardThreshold=GATE['forward_x']+ox,reverseThreshold=GATE['reverse_x']+ox,reverseMinimumZ=8+oz,
        hysteresisWidth=4,extensionCannotReactivateFirstEncounter=True,
        thirdEncounter=validate_third(scene,original),
        secondActorSpriteFootprintInsideRoomVisibilityKernel=True,
        secondActorContactBoxInsideActualRoom=True,
        secondActorSpawnFeetDry=True,spawnFeetHull=spawn_feet,
        secondActorMayWalkAcrossSlime=True,
        incomingActorHiddenBeforeActivation=incoming_visibility(scene),
        ammoPlacement=validate_ammo(scene),
        roomThroatWidth=22,continuousSweptRadius2Checks=swept_checks,
        route=[[x+ox,z+oz] for x,z in ROUTE],invisibleHandoffGuaranteed=False,
        scope='The second soldier starts on the dry zigzag and may subsequently cross slime. The third soldier is confined to the pre-exit room visibility kernel and leaves both doorways and both side routes clear. Three persistent actors share one active slot. The ammo pickup and its entry approach remain dry and clear of enemy contact bounds. The southern extension cannot reactivate the first encounter. Finite planes and floor topology are separately checked by the geometry generator.')


def write_assets(directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    scene_path=Path(os.environ.get('E1M1_MAP_PATH',HERE.parent/'assets/map.json'))
    scene=json.loads(scene_path.read_text())
    proof=validate_layout(scene)
    ox,oz=scene['coordinate_offset']
    lines=['; Generated encounter placement and area-activation thresholds.',
           f'ENCOUNTER_COUNT = {len(scene["encounters"])}']
    for index,los in ((1,(264+ox,352+ox,8+oz,100+oz)),(2,(256+ox,336+ox,-104+oz,-40+oz))):
        actor=scene['encounters'][index]
        lines += [f'ENCOUNTER{index}_X = {actor["x"]}',f'ENCOUNTER{index}_Z = {actor["z"]}']
        lines += [f'ENCOUNTER{index}_{key} = {value}' for key,value in zip(('X_MIN','X_MAX','Z_MIN','Z_MAX'),actor['movement_bounds'])]
        lines += [f'ENCOUNTER{index}_LOS_{key} = {value}' for key,value in zip(('X_MIN','X_MAX','Z_MIN','Z_MAX'),los)]
    lines += [f'ENCOUNTER_GATE_{key.upper()} = {scene["encounter_handoff"][key]}' for key in GATE]
    lines += [f'ENCOUNTER2_GATE_{key.upper()} = {scene["encounter_handoff"]["third"][key]}' for key in THIRD_GATE]
    (directory/'encounters-config.inc').write_text('\n'.join(lines)+'\n')
    proof['inputSha256']={str(scene_path.relative_to(ROOT)):sha(scene_path),
        str(Path(__file__).relative_to(ROOT)):sha(Path(__file__))}
    (directory/'encounter-layout-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
    return dict(encounters=scene['encounters'],handoff=scene['encounter_handoff'],proof=proof)


if __name__=='__main__':
    scene=json.loads((ROOT/'assets/map.json').read_text())
    print(json.dumps(validate_layout(scene),indent=2))
