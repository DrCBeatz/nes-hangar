"""Validate authored flat slime boundaries, materials and finite planes."""
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCENE = json.loads(Path(os.environ.get('E1M1_MAP_PATH', HERE.parent/'assets/map.json')).read_text())
POOLS = SCENE['slime']['pools']
GREEN_WALLS = {
    'zigzag_west_slime', 'zigzag_east_lower_bevel', 'zigzag_sealed_shelf_lower',
    'zigzag_sealed_shelf_diagonal', 'zigzag_sealed_shelf_upper',
    'zigzag_east_long', 'zigzag_east_upper_bevel',
}


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def contains(polygon, x, z):
    inside = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        if (a[1] > z) != (b[1] > z) and x < a[0]+(b[0]-a[0])*(z-a[1])/(b[1]-a[1]):
            inside = not inside
    return inside


def validate(scene):
    """Check the current authored floor surfaces without a historical map input."""
    pools = scene['slime']['pools']
    seams = [s for s in scene['segments'] if s.get('kind') == 'floor_material']
    assert len(seams) == 2 * scene['slime']['interior_edges'] == 20
    pool_edges = {frozenset((tuple(a), tuple(b)))
                  for poly in pools.values() for a, b in zip(poly, poly[1:]+poly[:1])}
    for segment in seams:
        a = (segment['x1'], segment['z1'])
        b = (segment['x2'], segment['z2'])
        assert frozenset((a,b)) in pool_edges
        assert segment['nx'] * a[0] + segment['nz'] * a[1] == segment['plane']
        assert segment['nx'] * b[0] + segment['nz'] * b[1] == segment['plane']
        assert segment['bottom'] == segment['top'] == segment['floor'] == 2
        assert not segment['collision']
        reverse = [s for s in seams if (s['x1'],s['z1'],s['x2'],s['z2']) == (*b,*a)]
        assert len(reverse) == 1
        assert {segment['floor_material'],reverse[0]['floor_material']} == {2,3}
    assert scene['slime']['flat'] and scene['slime']['height'] == 2
    assert scene['slime']['damage'] is True
    assert [r['polygon'] for r in scene['floor_regions'][2:]] == list(pools.values())
    assert all(r['height'] == 2 and r['material'] == 2 for r in scene['floor_regions'][2:])
    return dict(authoredSlimeGeometryValidated=True, floorHeight=2,
                directedMaterialPlanes=len(seams), damageEnabled=True,
                sourceSectors=scene['slime']['source_sectors'])
