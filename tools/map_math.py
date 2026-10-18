"""Exact polygon, swept-footprint and wall tests for the authored map."""
from fractions import Fraction


def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def inside(poly,p):
    x,z=p;result=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>z)!=(b[1]>z) and x<Fraction(a[0])+Fraction((b[0]-a[0])*(z-a[1]),b[1]-a[1]):result=not result
    return result


def hull(points):
    points=sorted(set(points));lower=[];upper=[]
    for p in points:
        while len(lower)>=2 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper)>=2 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
        upper.append(p)
    return lower[:-1]+upper[:-1]


def touches_hull(poly,a,b):
    axes=[(-(q[1]-p[1]),q[0]-p[0]) for p,q in zip(poly,poly[1:]+poly[:1])]
    axes.append((-(b[1]-a[1]),b[0]-a[0]))
    for nx,nz in axes:
        v=[nx*x+nz*z for x,z in poly];w=[nx*p[0]+nz*p[1] for p in (a,b)]
        if max(v)<min(w) or max(w)<min(v):return False
    return True


def blocked(scene,x,z):
    p=(x,z)
    if not inside(scene['outer_polygon'],p) or any(inside(h,p) for h in scene['holes']):return True
    r=scene['player_radius']
    for s in scene['segments']:
        if not s['collision']:continue
        if max(s['x1'],s['x2'])<x-r or min(s['x1'],s['x2'])>x+r or max(s['z1'],s['z2'])<z-r or min(s['z1'],s['z2'])>z+r:continue
        if abs(s['nx']*x+s['nz']*z-s['plane'])<=r*(abs(s['nx'])+abs(s['nz'])):return True
    return False
