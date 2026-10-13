"""Preserve v0.3.5 water barriers and restore the northwest dry road gap.

Run from the complete repository: python tools/author_water_v036.py.
Requires Pillow and NumPy. The terrain artwork is not modified.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
FIELD = (200, 200, 200)
WATER = (0, 0, 255)
BRIDGE = (255, 255, 0)
ROAD = (255, 0, 0)
HOUSE = (0, 0, 0)


def same_color(array, color):
    return np.all(array == color, axis=2)


def rasterize(spec, name):
    size = tuple(spec['coordinate_size'])
    image = Image.new('L', size)
    draw = ImageDraw.Draw(image)
    for region in spec[name]:
        points = [tuple(p) for p in region['points']]
        if name == 'water_polygons':
            draw.polygon(points, fill=255)
        else:
            draw.line(points, fill=255, width=region['width'], joint='curve')
            r = region['width'] / 2
            for x, y in points:
                draw.ellipse((x-r, y-r, x+r, y+r), fill=255)
    return image


def pool_mask(image, size):
    """Keep the v0.3.5 conservative cell pooling identical for every mask."""
    nw, nh = size
    super_mask = np.array(image.resize((nw*4, nh*4), Image.Resampling.NEAREST))
    return super_mask.reshape(nh, 4, nw, 4).max(axis=(1, 3)) > 0


def build():
    spec = json.loads((ROOT/'data/water_regions_v0.3.6.json').read_text())
    original = np.array(Image.open(ROOT/'assets/map/navigation_v0.3.4.png').convert('RGB'))
    previous = np.array(Image.open(ROOT/'assets/map/navigation_v0.3.3.png').convert('RGB'))
    nav = original.copy()
    nw, nh = spec['navigation_size']
    assert nav.shape == previous.shape == (nh, nw, 3)
    cw, ch = spec['coordinate_size']
    # Rebuild v0.3.5 identically before applying the one local clearance.
    restored = previous.copy()
    restored[same_color(restored, WATER) | same_color(restored, BRIDGE)] = FIELD
    old_bridge = same_color(nav, BRIDGE)
    water_or_bridge = same_color(nav, WATER) | old_bridge
    yy, xx = np.mgrid[0:nh, 0:nw]
    px = (xx + .5) * cw / nw
    py = (yy + .5) * ch / nh
    reviewed = np.zeros((nh, nw), dtype=bool)
    for x0, y0, x1, y1 in spec['replace_water_regions']:
        reviewed |= (px >= x0) & (px < x1) & (py >= y0) & (py < y1)
    cleared = reviewed & water_or_bridge
    nav[cleared] = restored[cleared]

    polygons = np.array(rasterize(spec, 'water_polygons'))
    channels = np.array(rasterize(spec, 'water_channels'))
    core_water = Image.fromarray(np.maximum(polygons, channels))
    # Unexpanded water is protected as whole grid cells too: a clearance may
    # never carve a route through a cell touched by the authored water core.
    core_blocked = pool_mask(core_water, (nw, nh))
    water = core_water.filter(ImageFilter.MaxFilter(2 * spec['shore_margin_pixels'] + 1))
    blocked = pool_mask(water, (nw, nh))
    nav[blocked] = WATER
    nav[old_bridge] = BRIDGE
    baseline = nav.copy()

    dry_corridor = pool_mask(rasterize(spec, 'dry_clearance_corridors'), (nw, nh))
    original_buildings = same_color(original, HOUSE) | same_color(previous, HOUSE)
    clearance = (dry_corridor & blocked & ~core_blocked
                 & same_color(nav, WATER) & ~original_buildings & ~old_bridge)
    nav[clearance] = ROAD
    assert not np.any(clearance & core_blocked), 'Dry corridor touched core water'
    assert not np.any(clearance & original_buildings), 'Dry corridor touched a building'
    assert np.array_equal(nav[~clearance], baseline[~clearance]), 'Non-corridor cells changed'
    assert np.array_equal(same_color(nav, BRIDGE), old_bridge), 'Bridge corridors changed'

    allowed = {FIELD, WATER, BRIDGE, ROAD, (0,255,0), HOUSE}
    assert {tuple(c) for c in np.unique(nav.reshape(-1,3), axis=0)} <= allowed
    for region in spec['water_polygons'] + spec['water_channels']:
        x, y = region['probe']
        cell = (min(nh-1, int(y * nh/ch)), min(nw-1, int(x * nw/cw)))
        assert tuple(nav[cell]) == WATER, (region['name'], cell, nav[cell])
    for probe in spec['dry_probes']:
        x, y = probe['cell']
        assert tuple(nav[y,x]) not in (WATER, HOUSE), probe['name']
    for corridor in spec['dry_clearance_corridors']:
        x, y = corridor['navigation_probe']
        assert tuple(nav[y,x]) == ROAD, corridor['name']

    target = ROOT/'assets/map/navigation_v0.3.6.png'
    Image.fromarray(nav).save(target, optimize=True)
    print(f'Saved {target.name}: {int(same_color(nav,WATER).sum())} water cells; '
          f'{int(old_bridge.sum())} bridge cells preserved; '
          f'{int(clearance.sum())} margin-only cells restored to dry road')
    return nav


if __name__ == '__main__':
    build()
