"""Conservative, offline visibility lists for bounded runtime geometry work.

Each closed 16x16 camera cell is intersected with the walkable outer polygon.
The resulting points conservatively bound every legal camera position there.
A face is removed only if back-facing throughout that hull, or if finite
opaque boundaries provably cover EVERY connecting ray. Long faces may have
separately proven halves. False positives are permitted; sampled visibility
never discards geometry. Runtime depth selection handles remaining occlusion.
"""
from fractions import Fraction
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent


def scene_grid(scene):
    """Aligned authored-bounds grid; global coordinates never wrap at 256."""
    polygon=scene['outer_polygon']
    assert all(isinstance(v,int) and 0<=v<1024 for p in polygon for v in p)
    xmin=min(x for x,z in polygon)//16*16
    zmin=min(z for x,z in polygon)//16*16
    cols=(max(x for x,z in polygon)-xmin)//16+1
    rows=(max(z for x,z in polygon)-zmin)//16+1
    assert 1<=cols<=64 and 1<=rows<=64
    return dict(x_min=xmin,z_min=zmin,cols=cols,rows=rows,cell_size=16)


def grid_cells(grid):
    for z in range(grid['z_min'],grid['z_min']+16*grid['rows'],16):
        for x in range(grid['x_min'],grid['x_min']+16*grid['cols'],16):
            yield x,z


def grid_table(prefix,grid,cells):
    assert len(cells)==grid['cols']*grid['rows']
    upper=prefix.upper()
    lines=[f'{upper}_GRID_{field.upper()} = {grid[field]}' for field in ('x_min','z_min','cols','rows')]
    for suffix,operator in (('lo','<'),('hi','>')):
        lines += [f'{prefix}_zone_row_{suffix}:',
                  '.byte '+','.join(f'{operator}{prefix}_zone_row_{i}' for i in range(grid['rows']))]
    # Preserve the flat table label for inspection; runtime selects a row first.
    lines += [f'{prefix}_zone_lookup:' if prefix=='geometry' else 'collision_cell_zone:']
    for row in range(grid['rows']):
        lines += [f'{prefix}_zone_row_{row}:',
                  '.byte '+','.join(map(str,cells[row*grid['cols']:(row+1)*grid['cols']]))]
    return lines


def witness(cell, target, blocker):
    """Return a strict finite-segment separation certificate, or None.

    Source/target lie strictly on opposite sides of the blocker line. Their
    convex hull's section on that line is bounded by the corner/end-point
    intersections. If all these intersections lie inside the finite blocker,
    every connecting ray crosses it. Exact rational arithmetic avoids a
    tolerance or sample-density assumption at corners and cell boundaries.
    """
    nx, nz, plane = (blocker[k] for k in ('nx', 'nz', 'plane'))
    source = cell
    destination = [(target['x1'],target['z1']), (target['x2'],target['z2'])]
    side = lambda p: nx*p[0]+nz*p[1]-plane
    a, b = [side(p) for p in source], [side(p) for p in destination]
    if not ((min(a)>0 and max(b)<0) or (max(a)<0 and min(b)>0)):
        return None
    bx,bz = blocker['x1'],blocker['z1']
    dx,dz = blocker['x2']-bx,blocker['z2']-bz
    length2 = dx*dx+dz*dz
    crossings=[]
    for p, ds in zip(source,a):
        for q, dt in zip(destination,b):
            t=Fraction(ds,ds-dt)
            x=p[0]+t*(q[0]-p[0]); z=p[1]+t*(q[1]-p[1])
            along=(x-bx)*dx+(z-bz)*dz
            if not 0 < along < length2:
                return None
            crossings.append(along)
    return {'blocker': blocker['id'], 'minimumAlong': str(min(crossings)),
            'maximumAlong': str(max(crossings)), 'lengthSquared': length2}


def cell_sources(x,z,polygon,size=16):
    """Vertices of a conservative hull of cell intersected with free outline.

    A polygon/rectangle intersection has vertices only at retained vertices
    of either polygon or at their edge intersections. We retain every such
    point, even across disconnected pieces, and ignore pillar holes. Testing
    all these points bounds their convex hull without needing to construct it.
    """
    def inside(p):
        px,pz=p; result=False
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            ax,az=a;bx,bz=b
            if (bx-ax)*(pz-az)==(bz-az)*(px-ax) and min(ax,bx)<=px<=max(ax,bx) and min(az,bz)<=pz<=max(az,bz):
                return True
            if (az>pz)!=(bz>pz) and px<ax+Fraction((bx-ax)*(pz-az),bz-az):
                result=not result
        return result
    points={(x+dx,z+dz) for dx in (0,size) for dz in (0,size) if inside((x+dx,z+dz))}
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        ax,az=a;bx,bz=b
        if x<=ax<=x+size and z<=az<=z+size:points.add((ax,az))
        if ax!=bx:
            for edge in (x,x+size):
                t=Fraction(edge-ax,bx-ax)
                hit=az+t*(bz-az)
                if 0<=t<=1 and z<=hit<=z+size:points.add((edge,hit))
        if az!=bz:
            for edge in (z,z+size):
                t=Fraction(edge-az,bz-az)
                hit=ax+t*(bx-ax)
                if 0<=t<=1 and x<=hit<=x+size:points.add((hit,edge))
    return sorted(points)


def compile_visibility(scene):
    grid=scene_grid(scene)
    segments=scene['segments']
    # Static full-height room boundaries and the inner enclosure can occlude
    # whole sight lines. Pillars and low recess faces stay in runtime selection.
    blockers=[s for s in segments if s.get('kind') in ('outer','inner') and s.get('collision',True)]
    assert all(s['bottom'] == scene['outer_floor_height'] and
               s['top'] == scene['ceiling_height'] and not s.get('dynamic')
               for s in blockers), 'Offline blockers must be static full-height walls'
    assert all(s.get('kind')!='door' for s in blockers), 'An openable door must never occlude the offline PVS'
    def covered(cell,target,depth=0):
        proof=next((p for b in blockers if b['id'] != target['id']
                    if (p:=witness(cell,target,b)) is not None),None)
        if proof is not None:
            return proof
        if depth==7:
            return None
        # A long wall may be concealed by several different boundary walls.
        # Prove BOTH complete halves hidden, never merely sampled endpoints.
        mx=Fraction(target['x1']+target['x2'],2)
        mz=Fraction(target['z1']+target['z2'],2)
        a=covered(cell,dict(target,x2=mx,z2=mz),depth+1)
        if a is None:
            return None
        b=covered(cell,dict(target,x1=mx,z1=mz),depth+1)
        return {'halves':[a,b]} if b is not None else None
    def covered_source(x,z,size,target):
        source=cell_sources(x,z,scene['outer_polygon'],size)
        if not source:
            return {'outsideWalkableOutline':True}
        if max(target['nx']*px+target['nz']*pz-target['plane'] for px,pz in source)<=0:
            return {'backFacingThroughoutCell':True}
        proof=covered(source,target)
        if proof is not None or size==2:
            return proof
        half=size//2
        children=[]
        for sz in (z,z+half):
            for sx in (x,x+half):
                child=covered_source(sx,sz,half,target)
                if child is None:
                    return None
                children.append({'cell':[sx,sz],'size':half,'proof':child})
        return {'sourceSubcells':children}
    lists=[]; cells=[]; certificates=[]
    for x,z in grid_cells(grid):
        candidates=[]; removed=[]
        source=cell_sources(x,z,scene['outer_polygon'])
        # In the southern extension, a 16-unit camera cell can straddle the
        # visibility cones of both narrow doorways. Different portions of the
        # cell can be hidden by different walls, even when no single blocker
        # covers the whole source hull. Prove all four CLOSED subcells hidden
        # before omitting a face, subdividing ambiguous sources down to2 units.
        # This changes no runtime grid or RAM budget.
        parts=[]
        if source and (z < scene['encounter_handoff']['reverse_z_min'] or (x >= 256 and z < 272)):
            parts=[(sx,sz,cell_sources(sx,sz,scene['outer_polygon'],8))
                   for sz in (z,z+8) for sx in (x,x+8)]
        for index,target in enumerate(segments):
            if not source:
                proof={'outsideWalkableOutline':True}
            elif max(target['nx']*px+target['nz']*pz-target['plane'] for px,pz in source)<=0:
                # The runtime already rejects these directed faces. Do
                # the same test over the complete source hull offline.
                proof={'backFacingThroughoutCell':True}
            else:
                proof=covered(source,target)
            if proof is None and parts:
                subproofs=[]
                for sx,sz,subsource in parts:
                    subproof=covered_source(sx,sz,8,target)
                    if subproof is None:
                        break
                    subproofs.append({'cell':[sx,sz],'size':8,'proof':subproof})
                if len(subproofs)==4:
                    proof={'sourceSubcells':subproofs}
            if proof is None:
                candidates.append(index)
            else:
                removed.append({'segment':index,**proof})
        if candidates not in lists:
            lists.append(candidates)
        cells.append(lists.index(candidates))
        certificates.append({'cell':[x,z], 'zone':cells[-1], 'removed':removed})
    assert len(lists)<=256
    return {'lists':lists,'cells':cells,'certificates':certificates,'grid':grid}


def write_assets(directory, scene=None):
    scene=scene or json.loads(Path(os.environ.get('E1M1_MAP_PATH',HERE.parent/'assets/map.json')).read_text())
    result=compile_visibility(scene)
    bitmap_bytes=(len(scene['segments'])+7)//8
    def bitmap(ids):
        data=[0]*bitmap_bytes
        for index in ids:data[index//8]|=1<<(index&7)
        assert [i for i in range(len(scene['segments'])) if data[i//8]&(1<<(i&7))]==list(ids)
        return data
    lines=['; Exact offline conservative visibility; see visibility.py.',
           '; Bitmaps preserve exactly the proven global-face candidate sets.',
           f'GEOMETRY_CANDIDATE_BYTES = {bitmap_bytes}',
           f'ROOM_ZONE_COUNT = {len(result["lists"])}']
    lines += grid_table('geometry',result['grid'],result['cells'])
    for label,operator in [('geometry_candidate_lo','<'),('geometry_candidate_hi','>')]:
        lines += [label+':','.byte '+','.join(f'{operator}geometry_candidates_{i}' for i in range(len(result['lists'])))]
    lines += ['geometry_candidate_count:', '.byte '+','.join(str(len(a)) for a in result['lists'])]
    lines += ['geometry_candidate_bits:', '.byte 1,2,4,8,16,32,64,128']
    for i,candidates in enumerate(result['lists']):
        lines += [f'geometry_candidates_{i}:', '.byte '+','.join(map(str,bitmap(candidates)))]
    lines += ['geometry_all_candidates:', '.byte '+','.join(map(str,bitmap(range(len(scene['segments'])))))]
    directory=Path(directory); directory.mkdir(parents=True,exist_ok=True)
    (directory/'visibility-data.inc').write_text('\n'.join(lines)+'\n')
    (directory/'visibility-certificates.json').write_text(json.dumps(result,indent=2)+'\n')
    return {'zones':len(result['lists']), 'cellSize':16, 'grid':result['grid'], 'globalFaces':len(scene['segments']),
            'minimumCandidates':min(map(len,result['lists'])),
            'maximumCandidates':max(map(len,result['lists'])),
            'method':'Whole-cell rejection or complete finite-boundary coverage; ambiguous southern sources subdivide exactly from16 down to2 units offline',
            'encoding':'Fixed-width bitmaps; candidate membership and ascending global-ID order unchanged',
            'bitmapBytes':bitmap_bytes,
            'tableBytes':len(result['cells'])+2*result['grid']['rows']+3*len(result['lists'])+bitmap_bytes*(len(result['lists'])+1)+8}


def write_collision_assets(directory, scene):
    """Exclude walls whose expanded AABB cannot touch any pose in a cell."""
    radius=scene['player_radius']
    segments=[s for s in scene['segments'] if s.get('collision',True)]
    lists=[]; cells=[]; grid=scene_grid(scene)
    for x,z in grid_cells(grid):
        ids=[i for i,s in enumerate(segments)
             if max(s['x1'],s['x2'])+radius>=x and min(s['x1'],s['x2'])-radius<=x+16
             and max(s['z1'],s['z2'])+radius>=z and min(s['z1'],s['z2'])-radius<=z+16]
        # Descending IDs retain the previous collision traversal order.
        ids.reverse()
        if ids not in lists: lists.append(ids)
        cells.append(lists.index(ids))
    assert len(lists)<=256
    lines=['; Conservative finite-wall collision candidates by closed camera cell.']
    lines += grid_table('collision',grid,cells)
    for label,op in [('collision_candidate_lo','<'),('collision_candidate_hi','>')]:
        lines += [label+':','.byte '+','.join(f'{op}collision_candidates_{i}' for i in range(len(lists)))]
    lines += ['collision_candidate_count:', '.byte '+','.join(str(len(a)) for a in lists)]
    for i,ids in enumerate(lists):
        lines += [f'collision_candidates_{i}:','.byte '+','.join(map(str,ids or [0]))]
    (Path(directory)/'collision-visibility.inc').write_text('\n'.join(lines)+'\n')
    return {'zones':len(lists),'globalWalls':len(segments),'maxCandidates':max(map(len,lists)),
            'grid':grid,'tableBytes':len(cells)+2*grid['rows']+3*len(lists)+sum(max(1,len(a)) for a in lists)}
