"""Connected E1M1 rooms: unfiltered fixed-point model and independent3D oracle.

Finite directed crossings emit vertical faces and near-sector horizontal floor
spans. Nearest opaque closure plus validated supporting-plane halfspaces and rectangular exit/entry topology fixes their painting order. No grid or stored views.
"""
from __future__ import annotations
import json
import math
import os
from functools import lru_cache
from pathlib import Path
import door_reference

HERE = Path(__file__).resolve().parent
SCENE = json.loads(Path(os.environ.get("E1M1_MAP_PATH", HERE.parent / "assets/map.json")).read_text())
WORLD_INTEGER_MAX = 1023
SEGMENTS = SCENE["segments"]
RECESS_DEPTH = SCENE["recess_depth"]
OUTER_FLOOR = SCENE["outer_floor_height"]
LOWER_FLOOR = OUTER_FLOOR - RECESS_DEPTH
OPAQUE_COUNT = next(i for i,s in enumerate(SEGMENTS) if s.get("kind") not in ("outer","pillar","door"))
RECESS_ENTRY_BEGIN = next(i for i,s in enumerate(SEGMENTS) if i>=OPAQUE_COUNT and s["bottom"]==s["top"])
SLIME_BEGIN = next(i for i,s in enumerate(SEGMENTS) if s.get("kind")=="floor_material")
SLIME_EDGE_COUNT = (len(SEGMENTS)-SLIME_BEGIN)//2

SINE = [round(256 * math.sin(a * math.tau / 256)) for a in range(256)]
VERTICES = list(dict.fromkeys((seg[k], seg[l]) for seg in SEGMENTS
                             for k, l in (("x1", "z1"), ("x2", "z2"))))


def rounded_div(n, d):
    return (1 if n >= 0 else -1) * ((abs(n) + d // 2) // d)


def projected_boundary(x, z, right=False):
    if z <= 0:
        return 256 if right else 0
    if abs(x) >= z:
        return 0 if x < 0 else 256
    return 128 + rounded_div(x * 128, z)


def floor_at(x_q8, z_q8, recess_depth=RECESS_DEPTH):
    r = SCENE["recess"]
    radius = SCENE["player_radius"] * 256
    inside = (x_q8-radius > r["x_min"]*256 and x_q8+radius < r["x_max"]*256 and
              z_q8-radius > r["z_min"]*256 and z_q8+radius < r["z_max"]*256)
    return SCENE["outer_floor_height"] - (recess_depth if inside else 0)


def eye_at(x_q8, z_q8, recess_depth=RECESS_DEPTH):
    return SCENE["eye_height"] + floor_at(x_q8,z_q8,recess_depth)


def scene_segments(recess_depth=RECESS_DEPTH):
    assert recess_depth in (0,RECESS_DEPTH)
    return [dict(seg, **{key: (OUTER_FLOOR-recess_depth if seg[key] == LOWER_FLOOR else seg[key])
                        for key in ("bottom", "top", "floor")}) for seg in SEGMENTS]


def height_boundary(height, inverse_depth, eye_height=SCENE["eye_height"]+OUTER_FLOOR):
    delta = eye_height - height
    displacement = (abs(delta) * inverse_depth + 2048) // 4096
    return max(0, min(144, 72 + (displacement if delta >= 0 else -displacement)))


def planes(x_q8, z_q8, angle, *, recess_depth=RECESS_DEPTH, door_open=True, door_cull=True):
    """Cached begin-frame plane data; values retain signed32 intermediates."""
    s, c = SINE[angle & 255], SINE[(angle + 64) & 255]
    transformed = {}
    for x, z in VERTICES:
        dx, dz = x * 256 - x_q8, z * 256 - z_q8
        transformed[x, z] = (dx * c - dz * s, dx * s + dz * c)
    result = []
    for index, seg in enumerate(SEGMENTS):
        if not door_reference.face_enabled(index,z_q8,door_open=door_open,door_cull=door_cull):
            continue
        nx, nz = seg["nx"], seg["nz"]
        distance = nx * x_q8 + nz * z_q8 - seg["plane"] * 256
        if distance <= 0:
            continue
        a = transformed[seg["x2"], seg["z2"]]
        b = transformed[seg["x1"], seg["z1"]]
        if a[1] <= 0 and b[1] <= 0:
            continue
        left, right = projected_boundary(*a), projected_boundary(*b, right=True)
        if left >= right:
            continue
        base = rounded_div(-(nx * (256 * s - 255 * c) +
                             nz * (256 * c + 255 * s)) * 2048, distance)
        step = rounded_div(-(nx * 2 * c - nz * 2 * s) * 2048, distance)
        result.append({"segment": index, "left": left, "right": right,
                       "base": base, "step": step, "distance": distance})
    return result


@lru_cache(maxsize=1)
def visibility_data():
    import visibility
    return visibility.compile_visibility(SCENE)


def candidates_for_pose(x_q8,z_q8,*,unfiltered=False):
    if unfiltered:return range(len(SEGMENTS))
    data=visibility_data();grid=data['grid']
    x=(x_q8//256-grid['x_min'])//16
    z=(z_q8//256-grid['z_min'])//16
    if not(0<=x<grid['cols'] and 0<=z<grid['rows']):return range(len(SEGMENTS))
    return data['lists'][data['cells'][z*grid['cols']+x]]


def slime_palette_candidate(x_q8,z_q8,angle,*,unfiltered=False,door_open=True,door_cull=True):
    """Conservative angular admission; hidden pools must not select green."""
    admitted=set(candidates_for_pose(x_q8,z_q8,unfiltered=unfiltered))
    return any(p['segment'] in admitted and (p['segment']>=SLIME_BEGIN or
               (p['segment']<OPAQUE_COUNT and SEGMENTS[p['segment']]['floor_material']==2))
               for p in planes(x_q8,z_q8,angle,door_open=door_open,door_cull=door_cull))


@lru_cache(maxsize=4096)
def slime_palette(x_q8,z_q8,angle,*,unfiltered=False,mode=0,
                  eye_height=None,recess_depth=RECESS_DEPTH,door_open=True,door_cull=True):
    """Select green only when a final world sample contains visible slime.

    Deliberately paint the final samples here rather than reproduce the 6502
    fast coverage rejection or suffix test. With the palette forced green,
    ordinary brown surfaces become material1 and material2 identifies slime.
    Precise raster samples even columns; coarse raster uses tile centers.
    """
    if not slime_palette_candidate(x_q8,z_q8,angle,unfiltered=unfiltered,door_open=door_open,door_cull=door_cull):
        return False
    probe=columns(x_q8,z_q8,angle,eye_height=eye_height,
                  recess_depth=recess_depth,_palette=True,door_open=door_open,door_cull=door_cull)
    for x in range(4 if mode else 0,256,8 if mode else 2):
        row=[0]*72+[3]*72
        for top,bottom,material in probe[x]:
            row[top:bottom]=[material]*(bottom-top)
        if any(row[y]==2 for y in range(4 if mode else 0,144,8 if mode else 1)):
            return True
    return False


def remap_material(index,material,surface,palette):
    if palette and material==2 and (surface=='wall' or OPAQUE_COUNT<=index<SLIME_BEGIN):
        return 1
    return material


def selected_crossings(x_q8, z_q8, angle, *, recess_depth=RECESS_DEPTH,door_open=True,door_cull=True):
    """Nearest opaque crossing and at most one rectangular exit/entry.

    Each opaque wall plane puts the entire recess in one halfspace. If the
    recess is outward, the nearest crossing hides both rims. Otherwise both
    rims precede that crossing in ray distance. Exit then entry painter order
    is topological, independent of rounded inverse-depth ties at corners.
    """
    active=[[] for _ in range(256)]
    for p in planes(x_q8,z_q8,angle,recess_depth=recess_depth,door_open=door_open,door_cull=door_cull):
        for column in range(p['left'],p['right']):
            value=p['base']+column*p['step']
            if value>0:
                active[column].append((p['segment'],value))
    result=[]
    for crossings in active:
        outer=[p for p in crossings if p[0]<OPAQUE_COUNT]
        low=[p for p in crossings if OPAQUE_COUNT<=p[0]<RECESS_ENTRY_BEGIN]
        high=[p for p in crossings if RECESS_ENTRY_BEGIN<=p[0]<SLIME_BEGIN]
        seams=[p for p in crossings if p[0]>=SLIME_BEGIN]
        assert len(low)<=1 and len(high)<=1, ('Overlapping rectangle crossings',crossings)
        assert outer, ('No enclosing wall',x_q8,z_q8,angle,len(result))
        closure=max(outer,key=lambda p:(p[1],p[0]))
        relation=recess_relation(SEGMENTS[closure[0]])
        rims=low+high # preserve rectangular exit then entry topology
        if relation==1:rims=[]
        elif relation==2:rims=[rim for rim in rims if rim[1]>=closure[1]]
        slime_relation=slime_halfspace(SEGMENTS[closure[0]])
        seams=sorted((p for p in seams if slime_relation==0 or (slime_relation==2 and p[1]>=closure[1])),key=lambda p:(p[1],p[0]))
        result.append([closure]+seams+rims)
    return result


def columns(x_q8, z_q8, angle, *, details=False, eye_height=None, recess_depth=RECESS_DEPTH,
            mode=0, _palette=None,door_open=True,door_cull=True):
    """256 wall/floor lists, culled and ordered before height projection."""
    if eye_height is None:
        eye_height=eye_at(x_q8,z_q8,recess_depth)
    segments=scene_segments(recess_depth)
    palette=(slime_palette(x_q8,z_q8,angle,mode=mode,eye_height=eye_height,
                           recess_depth=recess_depth,door_open=door_open,door_cull=door_cull) if _palette is None else _palette)
    result=[]
    for crossings in selected_crossings(x_q8,z_q8,angle,recess_depth=recess_depth,door_open=door_open,door_cull=door_cull):
        spans=[]
        floor_color=segments[crossings[0][0]]['floor_material']
        floor_clip=height_boundary(segments[crossings[0][0]]['floor'],crossings[0][1],eye_height)
        for index,value in crossings:
            seg=segments[index]
            top=height_boundary(seg['top'],value,eye_height)
            bottom=height_boundary(seg['bottom'],value,eye_height)
            floor_top=height_boundary(seg['floor'],value,eye_height)
            if index>=SLIME_BEGIN:floor_top=max(floor_clip,floor_top)
            if top<bottom:
                spans.append(dict(top=top,bottom=bottom,material=remap_material(index,seg['material'],'wall',palette),depth=value,segment=index,surface='wall'))
            if floor_top<144:
                if index>=SLIME_BEGIN:floor_color^=1
                span=dict(top=floor_top,bottom=144,material=floor_color if index>=SLIME_BEGIN else remap_material(index,seg['floor_material'],'floor',palette),depth=value,segment=index,surface='floor',cosmetic=index>=SLIME_BEGIN)
                if index>=SLIME_BEGIN:
                    assert spans and spans[-1]['surface']=='floor' and spans[-1]['bottom']==144
                    if spans[-1]['material']==span['material']:
                        continue
                    assert floor_top>=spans[-1]['top'], 'Nonmonotonic coplanar seam projection'
                    if floor_top==spans[-1]['top']:
                        spans.pop()
                        if spans and spans[-1]['material']==span['material']:
                            spans[-1]['bottom']=144
                            continue
                    else:
                        spans[-1]['bottom']=floor_top
                spans.append(span)
        result.append(spans)
    if details:
        return result
    return [[(s['top'],s['bottom'],s['material']) for s in spans] for spans in result]


def float_columns(x_q8, z_q8, angle, *, details=False, quantized_angles=False,
                  eye_height=None, recess_depth=RECESS_DEPTH,door_open=True):
    """Independent ray/finite-segment intersections, floating projection.

    A second independent oracle below intersects true horizontal floor planes
    for each pixel; it does not use this crossing/floor-span construction.
    """
    if eye_height is None:
        eye_height = eye_at(x_q8, z_q8, recess_depth)
    segments = scene_segments(recess_depth)
    palette=slime_palette(x_q8,z_q8,angle,door_open=door_open)
    px, pz = x_q8 / 256, z_q8 / 256
    theta = (angle & 255) * math.tau / 256
    s, c = math.sin(theta), math.cos(theta)
    if quantized_angles:
        s, c = SINE[angle & 255] / 256, SINE[(angle + 64) & 255] / 256
    result = []
    for column in range(256):
        u = (column - 127.5) / 128
        rx, rz = s + u * c, c - u * s
        spans = []
        for index, seg in enumerate(segments):
            if not door_reference.face_enabled(index,z_q8,door_open=door_open,door_cull=False):continue
            ax, az = seg["x1"] - px, seg["z1"] - pz
            ex, ez = seg["x2"] - seg["x1"], seg["z2"] - seg["z1"]
            determinant = rx * ez - rz * ex
            if determinant <= 1e-12:
                continue
            distance = (ax * ez - az * ex) / determinant
            along = (ax * rz - az * rx) / determinant
            if distance <= 0 or not -1e-10 <= along <= 1 + 1e-10:
                continue
            def boundary(h):
                offset = (eye_height - h) * 128 / distance
                rounded = math.floor(abs(offset) + .5)
                return max(0, min(144, 72 + (rounded if offset >= 0 else -rounded)))
            top, bottom, floor_top = boundary(seg["top"]), boundary(seg["bottom"]), boundary(seg["floor"])
            base = {"distance": distance, "depth": 524288 / distance, "segment": index}
            if floor_top < 144:
                spans.append(dict(base, top=floor_top, bottom=144,
                                  material=remap_material(index,seg["floor_material"],"floor",palette), surface="floor", cosmetic=index>=SLIME_BEGIN))
            if top < bottom:
                spans.append(dict(base, top=top, bottom=bottom,
                                  material=remap_material(index,seg["material"],"wall",palette), surface="wall"))
        spans.sort(key=lambda span: (span["depth"], span["segment"], span["surface"] == "floor"))
        result.append(spans)
    if details:
        return result
    return [[(s["top"], s["bottom"], s["material"]) for s in spans] for spans in result]


def point_inside(polygon, x, z):
    inside = False
    for (ax,az),(bx,bz) in zip(polygon,polygon[1:]+polygon[:1]):
        if (az > z) != (bz > z) and x < ax+(bx-ax)*(z-az)/(bz-az):
            inside = not inside
    return inside


def oracle_pixels(x_q8, z_q8, angle, *, eye_height=None, recess_depth=RECESS_DEPTH,
                  quantized_angles=False,door_open=True):
    """Independent nearest actual3D surface at every pixel.

    Vertical finite rectangles, the polygon-minus-hole outer floor, the inner
    rectangular floor and shared ceiling are intersected independently. No
    projected spans, sorting or floor halfplane construction is reused.
    """
    if eye_height is None:
        eye_height = eye_at(x_q8,z_q8,recess_depth)
    segments = scene_segments(recess_depth)
    palette=slime_palette(x_q8,z_q8,angle,door_open=door_open)
    px,pz = x_q8/256,z_q8/256
    theta = (angle&255)*math.tau/256
    s,c = math.sin(theta),math.cos(theta)
    if quantized_angles:
        s,c = SINE[angle&255]/256,SINE[(angle+64)&255]/256
    output = [[0]*256 for _ in range(144)]
    for x in range(256):
        u = (x-127.5)/128
        rx,rz = s+u*c,c-u*s
        wall_hits = []
        for index,seg in enumerate(segments):
            if not door_reference.face_enabled(index,z_q8,door_open=door_open,door_cull=False):continue
            ax,az = seg["x1"]-px,seg["z1"]-pz
            ex,ez = seg["x2"]-seg["x1"],seg["z2"]-seg["z1"]
            determinant = rx*ez-rz*ex
            if determinant <= 1e-12 or seg["bottom"] == seg["top"]:
                continue
            t = (ax*ez-az*ex)/determinant
            along = (ax*rz-az*rx)/determinant
            if t > 0 and -1e-10 <= along <= 1+1e-10:
                wall_hits.append((t,seg))
        for y in range(144):
            ry = (71.5-y)/128
            nearest,material = math.inf,0
            for t,seg in wall_hits:
                h = eye_height+ry*t
                if seg["bottom"] <= h <= seg["top"] and t < nearest:
                    nearest,material = t,(1 if palette and seg["material"]==2 else seg["material"])
            if ry < 0:
                for region in SCENE["floor_regions"]:
                    height = OUTER_FLOOR-recess_depth if region["height"] == LOWER_FLOOR else region["height"]
                    t = (height-eye_height)/ry
                    if t <= 0 or t >= nearest:
                        continue
                    wx,wz = px+t*rx,pz+t*rz
                    if point_inside(region["polygon"],wx,wz) and not any(point_inside(h,wx,wz) for h in region.get("holes",[])):
                        nearest,material = t,(1 if palette and region["id"]=="recess" else region["material"])
            elif ry > 0:
                t = (SCENE["ceiling_height"]-eye_height)/ry
                wx,wz = px+t*rx,pz+t*rz
                if t > 0 and t < nearest and point_inside(SCENE["outer_polygon"],wx,wz) and not any(point_inside(h,wx,wz) for h in SCENE["holes"]):
                    nearest,material = t,0
            assert nearest < math.inf,(x_q8,z_q8,angle,x,y,"uncovered ray")
            output[y][x] = material
    return output


def paint_columns(column_spans):
    result = [[0 if y < 72 else 3 for _ in range(256)] for y in range(144)]
    for x, spans in enumerate(column_spans):
        for top, bottom, material in spans:
            for y in range(top, bottom):
                result[y][x] = material
    return result


def pixels(x_q8, z_q8, angle, mode=0, *, eye_height=None, recess_depth=RECESS_DEPTH, pillars=True,door_open=True,door_cull=True):
    assert pillars, "This stress scene always includes four pillars"
    result = paint_columns(columns(x_q8, z_q8, angle, eye_height=eye_height,
                                   recess_depth=recess_depth,mode=mode,door_open=door_open,door_cull=door_cull))
    if mode:
        result = [[result[(y // 8) * 8 + 4][(x // 8) * 8 + 4]
                   for x in range(256)] for y in range(144)]
    return result


def float_pixels(x_q8, z_q8, angle, *, eye_height=None, recess_depth=RECESS_DEPTH, quantized_angles=False,door_open=True):
    return paint_columns(float_columns(x_q8, z_q8, angle, eye_height=eye_height,
                                       recess_depth=recess_depth, quantized_angles=quantized_angles,door_open=door_open))


def slime_halfspace(seg):
    """Supporting opaque planes give exact floor visibility at shared corners."""
    points=[p for poly in SCENE['slime']['pools'].values() for p in poly]
    distances=[seg['nx']*x+seg['nz']*z-seg['plane'] for x,z in points]
    return 0 if min(distances)>=0 else 1 if max(distances)<0 else 2


def recess_relation(seg):
    """0=inward, 1=outward, 2=straddling and requiring per-ray depth tests."""
    distances=[seg['nx']*x+seg['nz']*z-seg['plane']for x,z in SCENE['recess_polygon']]
    return 0 if min(distances)>=0 else 1 if max(distances)<0 else 2


def hides_recess(seg):
    return recess_relation(seg)==1


def validate_scene():
    """Prove the topology used by the exact recess ordering and floor oracle.

    The scene is unrestricted in room outline/count within byte coordinates;
    its recess remains one rectangular hole. Straddling opaque planes use
    per-ray depth tests; no visibility-zone lists are consulted.
    """
    outer,holes,patch=SCENE['outer_polygon'],SCENE['holes'],SCENE['recess_polygon']
    assert RECESS_DEPTH>0 and OUTER_FLOOR>=RECESS_DEPTH
    assert SCENE['ceiling_height']>OUTER_FLOOR+SCENE['eye_height']
    assert SCENE['max_step_height']>=RECESS_DEPTH
    assert all(isinstance(v,int)and 0<=v<=WORLD_INTEGER_MAX for polygon in [outer,patch]+holes for p in polygon for v in p)
    r=SCENE['recess']
    assert patch==[[r['x_min'],r['z_min']],[r['x_max'],r['z_min']],
                   [r['x_max'],r['z_max']],[r['x_min'],r['z_max']]]
    # A flat material panel may subdivide an authored boundary edge without
    # changing the collision/floor polygon. Prove that the render faces cover
    # each edge exactly, in order, with no gaps, overlaps or reversals.
    edges=[]
    cursor=0
    for polygon in [outer]+holes:
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            dx,dz=b[0]-a[0],b[1]-a[1]
            length2=dx*dx+dz*dz
            assert length2>0
            start=tuple(a)
            along=0
            while start!=tuple(b):
                assert cursor<OPAQUE_COUNT, ('Missing boundary face',a,b)
                seg=SEGMENTS[cursor]
                assert (seg['x1'],seg['z1'])==start
                end=(seg['x2'],seg['z2'])
                ex,ez=end[0]-a[0],end[1]-a[1]
                next_along=ex*dx+ez*dz
                assert ex*dz==ez*dx and along<next_along<=length2, ('Invalid boundary subdivision',seg['id'])
                edges.append((start,end))
                start,along=end,next_along
                cursor+=1
    assert cursor==door_reference.DOOR_FIRST
    door_reference.validate(SCENE)
    edges.extend(((s["x1"],s["z1"]),(s["x2"],s["z2"]))for s in SEGMENTS[door_reference.DOOR_FIRST:door_reference.DOOR_END])
    assert len(edges)==OPAQUE_COUNT
    edges.extend(zip(patch,patch[1:]+patch[:1]))
    edges.extend((b,a)for a,b in zip(patch,patch[1:]+patch[:1]))
    assert SLIME_BEGIN==len(edges)and RECESS_ENTRY_BEGIN==OPAQUE_COUNT+4
    assert SLIME_BEGIN==RECESS_ENTRY_BEGIN+4
    assert len(SEGMENTS)==SLIME_BEGIN+20
    from floor_reference import POOLS,GREEN_WALLS,validate
    validate(SCENE)
    assert len({s['id']for s in SEGMENTS})==len(SEGMENTS)
    for i,(seg,(a,b))in enumerate(zip(SEGMENTS,edges)):
        assert (seg['x1'],seg['z1'],seg['x2'],seg['z2'])==(*a,*b)
        dx,dz=b[0]-a[0],b[1]-a[1];g=math.gcd(abs(dx),abs(dz));assert g>0
        assert (seg['nx'],seg['nz'])==(-dz//g,dx//g)
        assert seg['plane']==seg['nx']*a[0]+seg['nz']*a[1]
        levels=(OUTER_FLOOR,SCENE['ceiling_height'],OUTER_FLOOR,2 if seg['id'] in GREEN_WALLS else 3) if i<OPAQUE_COUNT else (LOWER_FLOOR,OUTER_FLOOR,LOWER_FLOOR,2) if i<RECESS_ENTRY_BEGIN else (OUTER_FLOOR,OUTER_FLOOR,OUTER_FLOOR,3)
        assert tuple(seg[k]for k in ('bottom','top','floor','floor_material'))==levels
        assert seg['material']in(1,2)
        assert bool(seg.get('collision',True))==(i<OPAQUE_COUNT and seg.get('kind')!='door')
        if i<OPAQUE_COUNT:hides_recess(seg)
    for i,seg in enumerate(SEGMENTS[SLIME_BEGIN:]):
        assert seg['kind']=='floor_material' and not seg['collision']
        assert tuple(seg[k] for k in ('bottom','top','floor'))==(2,2,2)
        assert seg['floor_material']==(2 if i%2==0 else 3)
        if i%2:
            prev=SEGMENTS[SLIME_BEGIN+i-1]
            assert tuple(seg[k]for k in ('x1','z1','x2','z2'))==tuple(prev[k]for k in ('x2','z2','x1','z1'))
            assert all(seg[k]==-prev[k]for k in ('nx','nz','plane'))
    regions=SCENE['floor_regions'];assert len(regions)==4
    assert regions[0]['polygon']==outer and regions[0]['holes']==[patch]+holes+list(POOLS.values())
    assert regions[0]['height']==OUTER_FLOOR and regions[0]['material']==3
    assert regions[1]['polygon']==patch and regions[1]['holes']==[]
    assert regions[1]['height']==LOWER_FLOOR and regions[1]['material']==2


def write_assets(directory, recess_depth=RECESS_DEPTH):
    validate_scene()
    segments = scene_segments(recess_depth)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    assert len(VERTICES)<128 and len(segments)<128 # global IDs; renderer caches are bounded separately
    assert all(abs(s[k]) <= 7 for s in segments for k in ("nx", "nz"))
    # Plane distances remain signed24 Q8, and the existing numerator division
    # is independent of world translation. Reject unsupported authoring ranges.
    assert all(-32768 <= s["plane"] <= 32767 for s in segments)
    assert all(0 <= v <= WORLD_INTEGER_MAX for vertex in VERTICES for v in vertex)
    assert all(0 <= s["bottom"] <= s["top"] <= 32 and
               s["bottom"] % 2 == s["top"] % 2 == 0 for s in segments)
    lines = [f"WALL_COUNT = {len(SEGMENTS)}", f"VERTEX_COUNT = {len(VERTICES)}", f"OPAQUE_COUNT = {OPAQUE_COUNT}", f"RECESS_ENTRY_BEGIN = {RECESS_ENTRY_BEGIN}",f"SLIME_BEGIN = {SLIME_BEGIN}",f"SLIME_EDGE_COUNT = {SLIME_EDGE_COUNT}"]
    def table(label, values):
        lines.append(label + ":")
        values = list(values)
        for start in range(0, len(values), 16):
            lines.append("    .byte " + ",".join(f"${v & 255:02x}" for v in values[start:start + 16]))
    for label, shift in (("geom_sine_low", 0), ("geom_sine_high", 8)):
        table(label, (v >> shift for v in SINE))
    table("vertex_x", (v[0] for v in VERTICES))
    table("vertex_z", (v[1] for v in VERTICES))
    table("vertex_x_hi", (v[0] >> 8 for v in VERTICES))
    table("vertex_z_hi", (v[1] >> 8 for v in VERTICES))
    table("segment_vertex1", (VERTICES.index((s["x2"], s["z2"])) for s in segments))
    table("segment_vertex2", (VERTICES.index((s["x1"], s["z1"])) for s in segments))
    table("segment_hides_recess", (recess_relation(seg) for seg in segments[:OPAQUE_COUNT]))
    table("segment_hides_slime", (slime_halfspace(seg) for seg in segments[:OPAQUE_COUNT]))
    for key in ("nx", "nz", "material", "bottom", "top", "floor", "floor_material"):
        table("segment_" + key, (s[key] for s in segments))
    table("segment_plane_lo", (s["plane"] for s in segments))
    table("segment_plane_hi", (s["plane"] >> 8 for s in segments))
    (directory / "geometry-data.inc").write_text("\n".join(lines) + "\n")
    return {"segments": len(SEGMENTS), "vertices": len(VERTICES),
            "world_coordinate_bits": 24, "world_fraction_bits": 8,
            "supported_world_integer_max": WORLD_INTEGER_MAX,
            "trig_scale": 256, "depth_fraction_bits": 8,
            "depth_comparison_bits": 32, "projection_fraction_bits": 16, "interpolation_bits": 32,
            "wall_height_quantum": 2, "eye_heights": [SCENE["eye_height"]+OUTER_FLOOR-recess_depth,SCENE["eye_height"]+OUTER_FLOOR], "recess_depth": recess_depth,
            "span_capacity": 16, "maxEmittedCrossings": 13, "maxNonemptySpans": 15, "slimeBoundaryPairs":SLIME_EDGE_COUNT,
            "slimeCosmeticSpansOccludeSprites":False,"slimeDamage":False,
            "visibilityContract": "Complete authored polygon/holes/recess validated; straddling planes use per-ray depth comparison", "streaming": "Sequential columns, far-to-near vertical spans",
            "visibility": "Unfiltered nearest full-height outer/pillar closure; validated halfspace table; rectangular exit then entry topology",
            "geometry": "Connected E1M1 room/corridor polygon, four WAD pillars and enclosed rectangular recess; finite horizontal floors"}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path)
    args = parser.parse_args()
    if args.assets:
        print(json.dumps(write_assets(args.assets), indent=2))
