"""Add the reviewed junction bridge to the unchanged v0.3.6 navigation mask.

Run from the complete repository: python tools/author_bridge_v051.py.
Requires Pillow. The terrain artwork and source navigation are not modified.
Only the explicitly reviewed WATER cells under the road deck may be opened.
"""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parents[1]
WATER = (0, 0, 255)
BRIDGE = (255, 255, 0)
HOUSE = (0, 0, 0)


def distance_to_segment(point, start, end):
    dx, dy = end[0] - start[0], end[1] - start[1]
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return math.dist(point, start)
    t = max(0, min(1, ((point[0] - start[0]) * dx +
                       (point[1] - start[1]) * dy) / length_squared))
    return math.hypot(point[0] - start[0] - t * dx,
                      point[1] - start[1] - t * dy)


def build():
    spec = json.loads((PROJECT_ROOT / 'data/bridge_corridors_v0.5.1.json').read_text())
    source = PROJECT_ROOT / spec['source_navigation']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == spec['source_sha256'], \
        'The reviewed source mask differs; do not apply this bridge to another map'
    original = Image.open(source).convert('RGB')
    assert original.size == tuple(spec['navigation_size']), 'Navigation dimensions differ'
    nav = original.copy()
    width, height = nav.size
    coordinate_width, coordinate_height = spec['coordinate_size']
    reviewed_cells = set()
    for bridge in spec['bridges']:
        points = bridge['points']
        assert len(points) >= 2 and bridge['width'] > 0
        for pair in bridge['cells']:
            cell = tuple(pair)
            assert len(cell) == 2 and all(isinstance(v, int) for v in cell)
            x, y = cell
            assert 0 <= x < width and 0 <= y < height
            assert cell not in reviewed_cells, 'Repeated bridge cell'
            assert original.getpixel(cell) == WATER, \
                f'Only reviewed WATER may change, not land, buildings or old bridges: {cell}'
            center = ((x + .5) * coordinate_width / width,
                      (y + .5) * coordinate_height / height)
            distance = min(distance_to_segment(center, a, b)
                           for a, b in zip(points, points[1:]))
            assert distance <= bridge['width'] / 2 + 1e-6, \
                f'Cell center lies outside the reviewed paved corridor: {cell}'
            reviewed_cells.add(cell)
            nav.putpixel(cell, BRIDGE)
        for pair in bridge['river_probes']:
            cell = tuple(pair)
            assert original.getpixel(cell) == nav.getpixel(cell) == WATER, \
                f'Off-deck river was opened: {cell}'
        for pair in [bridge['from'], bridge['to']]:
            assert original.getpixel(tuple(pair)) not in (WATER, HOUSE), \
                'Bridge bank must already be dry and walkable'

    assert len(reviewed_cells) == spec['expected_changed_cells']
    changed = set()
    old_bridges = 0
    water_count = 0
    for y in range(height):
        for x in range(width):
            cell = (x, y)
            before, after = original.getpixel(cell), nav.getpixel(cell)
            old_bridges += before == BRIDGE
            water_count += after == WATER
            if before != after:
                changed.add(cell)
                assert before == WATER and after == BRIDGE
            elif before == BRIDGE:
                assert after == BRIDGE
    assert changed == reviewed_cells, 'Changes escaped the explicit deck cell list'
    target = PROJECT_ROOT / spec['target_navigation']
    target.parent.mkdir(parents=True, exist_ok=True)
    nav.save(target, optimize=True)
    print(f'Saved {target.name}: {len(changed)} deck WATER->BRIDGE cells; '
          f'{old_bridges} old bridge cells preserved; {water_count} water cells')
    return nav


if __name__ == '__main__':
    build()
