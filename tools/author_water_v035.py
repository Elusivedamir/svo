"""Apply audited, named water regions without erasing unaudited water globally.

Run from the complete repository: python tools/author_water_v035.py.
Requires Pillow and NumPy. No OpenCV or resizing of the approved terrain art.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
FIELD = (200, 200, 200)
WATER = (0, 0, 255)
BRIDGE = (255, 255, 0)


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


def build():
    spec = json.loads((ROOT/'data/water_regions_v0.3.5.json').read_text())
    nav = np.array(Image.open(ROOT/'assets/map/navigation_v0.3.4.png').convert('RGB'))
    previous = np.array(Image.open(ROOT/'assets/map/navigation_v0.3.3.png').convert('RGB'))
    nw, nh = spec['navigation_size']
    assert nav.shape == previous.shape == (nh, nw, 3)
    cw, ch = spec['coordinate_size']
    # Preserve all categories outside specifically reviewed replacement areas.
    # For removed water restore the previous non-water terrain classification.
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
    water = Image.fromarray(np.maximum(polygons, channels))
    water = water.filter(ImageFilter.MaxFilter(2 * spec['shore_margin_pixels'] + 1))
    # Pool every source pixel in a cell instead of sampling just its centre.
    # The supersampling lattice is an exact multiple of both grid dimensions.
    super_mask = np.array(water.resize((nw*4, nh*4), Image.Resampling.NEAREST))
    blocked = super_mask.reshape(nh, 4, nw, 4).max(axis=(1, 3)) > 0
    nav[blocked] = WATER
    # Retain the previously validated bank-to-bank corridors exactly.
    nav[old_bridge] = BRIDGE
    allowed = {FIELD, WATER, BRIDGE, (255,0,0), (0,255,0), (0,0,0)}
    assert {tuple(c) for c in np.unique(nav.reshape(-1,3), axis=0)} <= allowed
    for region in spec['water_polygons'] + spec['water_channels']:
        x, y = region['probe']
        cell = (min(nh-1, int(y * nh/ch)), min(nw-1, int(x * nw/cw)))
        assert tuple(nav[cell]) == WATER, (region['name'], cell, nav[cell])
    for probe in spec['dry_probes']:
        x, y = probe['cell']
        assert tuple(nav[y,x]) not in (WATER, (0,0,0)), probe['name']
    target = ROOT/'assets/map/navigation_v0.3.5.png'
    Image.fromarray(nav).save(target, optimize=True)
    print(f'Saved {target.name}: {int(same_color(nav,WATER).sum())} water cells; {int(old_bridge.sum())} bridge cells preserved')
    return nav


if __name__ == '__main__':
    build()
