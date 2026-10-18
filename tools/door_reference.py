"""One full-height, permanently opening door across the final passage.

The open scene is byte-for-byte the accepted geometry after removing these two
render-only faces. Closed-door collision is a separate runtime state check.
"""
from __future__ import annotations
import copy
from fractions import Fraction
from pathlib import Path

DOOR_FIRST = 84
DOOR_END = 86
SOUTH_FIRST = 22
SOUTH_END = 43
DOOR_X_MIN = 288
DOOR_X_MAX = 304
DOOR_Z = 120


def prepare_scene(scene):
    scene = copy.deepcopy(scene)
    assert not any(s.get('kind') == 'door' for s in scene['segments'])
    assert next(i for i,s in enumerate(scene['segments']) if not s.get('collision',True)) == DOOR_FIRST
    faces=[]
    for name,a,b in [('exit_door_north',(288,120),(304,120)),
                     ('exit_door_south',(304,120),(288,120))]:
        nz=1 if b[0]>a[0] else -1
        faces.append(dict(id=name,x1=a[0],z1=a[1],x2=b[0],z2=b[1],nx=0,nz=nz,
                          plane=nz*DOOR_Z,material=2,bottom=scene['outer_floor_height'],
                          top=scene['ceiling_height'],floor=scene['outer_floor_height'],
                          floor_material=3,kind='door',collision=False,
                          dynamic='exit_corridor_door'))
    scene['segments'][DOOR_FIRST:DOOR_FIRST]=faces
    scene['description']=scene['description'].replace('two permanently open doorways', 'one openable passage door and an open final doorway')
    scene['exit_extension']['doors']='first passage door opens on use; final exit doorway remains open'
    scene['door']=dict(id='exit_corridor_door',x_min=DOOR_X_MIN,x_max=DOOR_X_MAX,z=DOOR_Z,
                       render_faces=[s['id'] for s in faces],render_face_ids=[DOOR_FIRST,DOOR_FIRST+1],
                       initial_state='closed',states=['closed','open'],animation=False,
                       floor=scene['outer_floor_height'],ceiling=scene['ceiling_height'],
                       dynamic_collision=True,visibility_blocker=False,
                       closed_south_face_range=[SOUTH_FIRST,SOUTH_END],
                       description='Opaque two-sided panel at the south end of the narrow passage; opening retains the complete accepted route.')
    validate(scene)
    return scene


def face_enabled(index,z_q8,*,door_open=True,door_cull=True):
    if door_open:
        return not DOOR_FIRST <= index < DOOR_END
    if DOOR_FIRST <= index < DOOR_END:
        return True
    # A real closed-door camera cannot touch the door's radius-two collision
    # band. Preserve enclosure for deliberately injected plane-center poses.
    if not door_cull or z_q8 == DOOR_Z*256:
        return True
    if z_q8 > DOOR_Z*256:
        return not SOUTH_FIRST <= index < SOUTH_END
    return SOUTH_FIRST <= index < SOUTH_END


def blocked(x_q8,z_q8,*,door_open=True,radius=2):
    if door_open:return False
    return (DOOR_X_MIN*256-radius*256 <= x_q8 <= DOOR_X_MAX*256+radius*256
            and abs(z_q8-DOOR_Z*256) <= radius*256)


def validate(scene):
    segments=scene['segments'];door=segments[DOOR_FIRST:DOOR_END]
    assert len(door)==2 and all(s.get('kind')=='door' and not s['collision'] for s in door)
    assert [(s['x1'],s['z1'],s['x2'],s['z2'])for s in door]==[(288,120,304,120),(304,120,288,120)]
    assert all((s['bottom'],s['top'],s['floor'],s['floor_material'])==(2,10,2,3)for s in door)
    # Every southern exterior face lies at/below the crosscut; every other
    # authored surface lies at/above it. No second connector crosses the line.
    for i,s in enumerate(segments):
        if DOOR_FIRST<=i<DOOR_END:continue
        zs=(s['z1'],s['z2'])
        assert max(zs)<=DOOR_Z if SOUTH_FIRST<=i<SOUTH_END else min(zs)>=DOOR_Z
    polygon=scene['outer_polygon'];crossings=[]
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>DOOR_Z)!=(b[1]>DOOR_Z):
            crossings.append(Fraction(a[0])+Fraction(DOOR_Z-a[1],b[1]-a[1])*(b[0]-a[0]))
    assert sorted(crossings)==[DOOR_X_MIN,DOOR_X_MAX]
    assert all(min(z for x,z in hole)>DOOR_Z for hole in scene['holes'])
    assert all(min(z for x,z in region['polygon'])>DOOR_Z for region in scene['floor_regions'][1:])
    assert all(s.get('kind')!='door' for s in segments if s.get('collision',True))
    return dict(crosscut=[[288,120],[304,120]],outlineIntersections=list(map(str,sorted(crossings))),
                southFaces=[SOUTH_FIRST,SOUTH_END],doorFaces=[DOOR_FIRST,DOOR_END],
                uniqueConnection=True,openDoorNeverOfflineBlocker=True,
                closedCollisionBand=[DOOR_Z-scene['player_radius'],DOOR_Z+scene['player_radius']])


def write_assets(directory,scene):
    proof=validate(scene)
    constants=dict(DOOR_FIRST=DOOR_FIRST,DOOR_END=DOOR_END,DOOR_SOUTH_FIRST=SOUTH_FIRST,
                   DOOR_SOUTH_END=SOUTH_END,DOOR_X_MIN=DOOR_X_MIN,DOOR_X_MAX=DOOR_X_MAX,
                   DOOR_Z=DOOR_Z)
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    (directory/'door-config.inc').write_text('; Full-height crosscut door; render state0closed/1open.\n'+'\n'.join(f'{k} = {v}'for k,v in constants.items())+'\n')
    return dict(scene['door'],topology=proof,constants=constants)


make_scene = prepare_scene


def bind_model(model,*,door_open=True,door_cull=True):
    """Bind immutable door state for existing renderer/oracle audit harnesses.

    The independent pixel painter consumes the chosen state without using
    optimized span merges.
    Rebinding restores original functions, so audit states never stack wrappers.
    """
    import functools
    import inspect
    names=('planes','slime_palette_candidate','slime_palette','selected_crossings',
           'columns','float_columns','oracle_pixels','pixels','float_pixels')
    originals=getattr(model,'_door_original_functions',None)
    if originals is None:
        originals={name:getattr(model,name)for name in names}
        model._door_original_functions=originals
    for name,fn in originals.items():
        if hasattr(fn,'cache_clear'):fn.cache_clear()
        parameters=inspect.signature(fn).parameters
        @functools.wraps(fn)
        def bound(*args,_fn=fn,_parameters=parameters,**kwargs):
            if 'door_open' in _parameters:kwargs['door_open']=door_open
            if 'door_cull' in _parameters:kwargs['door_cull']=door_cull
            return _fn(*args,**kwargs)
        setattr(model,name,bound)
    return model
