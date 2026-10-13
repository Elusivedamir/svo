#!/usr/bin/env python3
"""Repeatable builder for v0.3.2 four-sector playable prototype.
Requires Pillow, NumPy, OpenCV on a development machine, not inside the APK.
Transforms art and nav identically to keep obstacles and bridges aligned.
"""
from PIL import Image,ImageOps
import numpy as np, cv2
from pathlib import Path
out=Path(__file__).resolve().parents[1]
base=out
art=Image.open(base/'assets/map/terrain_v0.3.1.png').convert('RGB')
nav=Image.open(base/'assets/map/navigation_v0.3.1.png').convert('RGB')
positions=[(0,0),(1,0),(0,1),(1,1)]

def tile_map(src,is_nav):
    w,h=src.size
    result=Image.new('RGB',(w*2,h*2))
    for c,r in positions:
        im=src
        if c: im=ImageOps.mirror(im)
        if r: im=ImageOps.flip(im)
        if c!=0 or r!=0:
            a=np.asarray(im)
            yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
            u=xx/max(w-1,1);v=yy/max(h-1,1)
            fade=np.sin(np.pi*u)*np.sin(np.pi*v)
            # Distinct terrain geometry but deformation vanishes at every sector boundary.
            phases={(1,0):(0.61,2.1),(0,1):(2.8,0.85),(1,1):(4.1,3.7)}[(c,r)]
            dx=fade*(78*np.sin(2*np.pi*v+phases[0])+41*np.cos(2*np.pi*u+phases[1]))
            dy=fade*(44*np.cos(2*np.pi*u+phases[0])+32*np.sin(2*np.pi*v+phases[1]))
            if is_nav:dx*=209/1672;dy*=118/941
            warped=cv2.remap(a,np.asarray(xx+dx,dtype=np.float32),np.asarray(yy+dy,dtype=np.float32),interpolation=cv2.INTER_NEAREST if is_nav else cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
            if not is_nav:
                # Local variations in foliage tint keep seams seamless while differentiating sectors
                tt={(1,0):1.02,(0,1):0.985,(1,1):1.006}[(c,r)]
                warped=np.uint8(np.clip(warped.astype(np.float32)*(1+(tt-1)*fade[:,:,None]),0,255))
            im=Image.fromarray(warped)
        result.paste(im,(w*c,h*r))
    return result
newart=tile_map(art,False)
newnav=tile_map(nav,True)
newart.save(out/'assets/map/terrain_v0.3.2.png',optimize=True)
newnav.save(out/'assets/map/navigation_v0.3.2.png',optimize=True)
print('size:',(newart.size,newnav.size))
