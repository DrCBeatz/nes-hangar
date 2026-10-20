"""Conservative near-source visibility gate for the sealed inner enclosure.

This is a necessary-condition filter, never a sampled visibility decision.
Any line from the slime room to the enclosure must cross the northern portal.
The northeast enclosure corner gives the rightmost possible crossing. A
one-unit X safety margin is added after rounding an entire one-unit Z slab.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def scanline_intervals(polygon,z):
    crossings=[]
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>z)!=(b[1]>z):
            crossings.append(Fraction(a[0])+Fraction(z-a[1],b[1]-a[1])*(b[0]-a[0]))
    crossings.sort()
    assert len(crossings)%2==0
    return list(zip(crossings[::2],crossings[1::2]))


def compile_filter(scene):
    inner=scene['inner_structure']
    room=next(a for a in scene['areas']if a['id']=='zigzag_room')
    portal=next(p for p in scene['portals']if p['id']=='next_passage_to_zigzag')
    a,b=sorted((portal['a'],portal['b']))
    assert a[1]==b[1]
    xmin,xmax=inner['bounds']['x'];zmin,zmax=inner['bounds']['z']
    assert xmin<xmax<a[0]<b[0] and a[1]<zmin<zmax
    assert inner['polygon']==[[xmin,zmin],[xmin,zmax],[xmax,zmax],[xmax,zmin]]
    assert inner['floor']==room['floor']==scene['outer_floor_height']==2
    assert inner['ceiling']==room['ceiling']==scene['ceiling_height']==10
    assert room['flat']
    indices=[i for i,s in enumerate(scene['segments'])
             if s['id']in ('inner_structure_east','inner_structure_south')]
    assert len(indices)==2 and indices[1]==indices[0]+1
    assert indices[0]//8==indices[1]//8
    for i in indices:
        face=scene['segments'][i]
        assert face['kind']=='inner' and face['collision'] and not face.get('dynamic')
        assert (face['bottom'],face['top'])==(2,10)
        assert max(face['x1'],face['x2'])<=xmax and max(face['z1'],face['z2'])<=zmax
    # The remaining outer boundaries are genuine opaque floor-to-ceiling
    # barriers. No transparent wall or dynamic door is used in this proof.
    outer=[s for s in scene['segments']if s.get('kind')=='outer']
    assert all(s['collision']and(s['bottom'],s['top'])==(2,10)
               and not s.get('dynamic')for s in outer)
    intervals=scanline_intervals(scene['outer_polygon'],Fraction(a[1]))
    relevant=[(lo,hi)for lo,hi in intervals if hi>=xmin]
    assert relevant==[(Fraction(a[0]),Fraction(b[0]))], ('new path across source cut',intervals)
    assert all(hi<xmin for lo,hi in intervals if (lo,hi)not in relevant)
    # A source-to-target line stays at X>=xmin, so cannot reach the other
    # opening-room component of this scanline. Crossing on a solid horizontal
    # boundary also remains opaque; it is not an additional portal.
    horizontal=[s for s in outer if s['z1']==s['z2']==a[1]]
    assert any(max(s['x1'],s['x2'])==a[0] and min(s['x1'],s['x2'])<a[0]for s in horizontal)
    nx,nz=zmax-a[1],a[0]-xmax
    divisor=math.gcd(nx,nz);nx//=divisor;nz//=divisor
    plane=nx*a[0]+nz*a[1]
    first_z=room['bounds']['z'][0];last_z=a[1]
    x_page=1;x_base=x_page*256;last_x=room['bounds']['x'][1]
    assert x_base>xmin and x_base<last_x<=512
    assert first_z<last_z and last_z-first_z<=256
    # For real Pz in [Z,Z+1), Pz<=Z+1. Reject only Xfloor<cut:
    # Px<cut, hence nx*Px+nz*Pz-plane is at most -nx, with one
    # additional world unit of conservative X margin beyond slab rounding.
    cuts=[(plane-nz*(z+1))//nx-1-x_base for z in range(first_z,last_z)]
    assert all(0<=value<=255 for value in cuts)
    margins=[plane-(nx*(value+x_base)+nz*(z+1))
             for z,value in zip(range(first_z,last_z),cuts)]
    assert min(margins)>=nx
    constants={'INNER_VISIBILITY_Z_MIN':first_z,'INNER_VISIBILITY_ROWS':len(cuts),
               'INNER_VISIBILITY_X_PAGE':x_page,'INNER_VISIBILITY_X_MAX':last_x,
               'INNER_VISIBILITY_FIRST':indices[0],'INNER_VISIBILITY_END':indices[-1]+1}
    return {'constants':constants,'x_cutoff':cuts,'tableBytes':len(cuts),
            'inequality':{'nx':nx,'nz':nz,'plane':plane,'visibleRequires':'nx*X+nz*Z-plane >= 0'},
            'domain':{'x':[x_base,last_x],'z':[first_z,last_z],'upperBoundsExclusive':True},
            'portal':[a,b],'enclosureExtreme':[xmax,zmax],
            'scanlineIntervals':[[str(lo),str(hi)]for lo,hi in intervals],
            'minimumStrictShadowMargin':min(margins),'extraXGuardUnits':1,
            'targetIds':[scene['segments'][i]['id']for i in indices]}


def hidden(x_q8,z_q8,scene):
    data=compile_filter(scene);domain=data['domain']
    if not(domain['x'][0]*256<=x_q8<domain['x'][1]*256
           and domain['z'][0]*256<=z_q8<domain['z'][1]*256):
        return False
    row=z_q8//256-domain['z'][0]
    return x_q8//256-domain['x'][0]<data['x_cutoff'][row]


def write_assets(directory,scene):
    result=compile_filter(scene);directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    (directory/'inner-visibility-config.inc').write_text(
        '; Conservative enclosure gate from the source-room portal.\n'+
        '\n'.join(f'{name} = {value}'for name,value in result['constants'].items())+'\n')
    lines=['; Per integer-Z slab. Table stores conservative X cutoff minus256.',
           '; Entire closed slab plus an extra one-world-unit X margin is proved hidden.',
           'inner_visibility_x_cut:']
    for i in range(0,len(result['x_cutoff']),16):
        lines.append('.byte '+','.join(map(str,result['x_cutoff'][i:i+16])))
    (directory/'inner-visibility-data.inc').write_text('\n'.join(lines)+'\n')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map',type=Path,default=ROOT/'assets/map.json')
    parser.add_argument('--output',type=Path,default=ROOT/'analysis/visibility-optimization')
    args=parser.parse_args()
    scene=json.loads(args.map.read_text());data=compile_filter(scene)
    # Independent finite-boundary certificates supplement the portal proof.
    # Failure to find one does not authorize a cull: the exact source-cut
    # topology and slab inequality above are the primary complete proof.
    import visibility
    walls=[s for s in scene['segments']if s.get('kind')=='outer']
    targets=[s for s in scene['segments']if s['id']in data['targetIds']]
    cells=0;plane_pairs=0;direct=0;blocker_counts={};analytic_max=None
    for row,cut in enumerate(data['x_cutoff']):
        z=data['domain']['z'][0]+row
        for x in range(data['domain']['x'][0],min(data['domain']['x'][1],data['domain']['x'][0]+cut)):
            source=visibility.cell_sources(x,z,scene['outer_polygon'],1)
            if not source:continue
            cells+=1
            fmax=max(data['inequality']['nx']*px+data['inequality']['nz']*pz-data['inequality']['plane']for px,pz in source)
            assert fmax<0
            analytic_max=fmax if analytic_max is None else max(analytic_max,fmax)
            for target in targets:
                plane_pairs+=1
                proof=next((p for wall in walls if(p:=visibility.witness(source,target,wall))),None)
                if proof:
                    direct+=1;key=proof['blocker'];blocker_counts[key]=blocker_counts.get(key,0)+1
    report={'mapSha256':hashlib.sha256(args.map.read_bytes()).hexdigest(),**data,
            'proof':{'completeSourceCutAndSlabProof':True,'sourceCellsMeetingWalkableOutline':cells,
                     'targetCellPairs':plane_pairs,'directSingleFiniteWallCertificates':direct,
                     'directCertificateWalls':blocker_counts,
                     'allSourceHullsSatisfyStrictShadowInequality':True,
                     'maximumShadowFunction':str(analytic_max),
                     'remainingPairs':'Covered by the complete portal/topology proof; a single finite blocker need not cover all source-to-target combinations.'},
            'scope':'Geometric proof includes all fractional positions of every rejected slab. Fixed-point renderer preservation is tested separately against the unfiltered renderer.'}
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'inner-visibility-proof.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'tableBytes':data['tableBytes'],'constants':data['constants'],'proof':report['proof']},indent=2))


if __name__=='__main__':main()
