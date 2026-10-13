"""Manual terrain annotations for approved fictional map artwork.

This does NOT infer obstacle geometry from the photo. Annotated footprints and
road/hedge lines are explicit and can be refined in later patches.

Navigation raster (209x118):
FIELD=(200,200,200); ROAD=(255,0,0); WOODS=(0,255,0);
BUILDING=(0,0,0); WATER=(0,0,255); BRIDGE=(255,255,0).
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
ORIGINAL=ROOT/'assets/map/terrain_v0.3.1.png'
OUTPUT=ROOT/'assets/map/navigation_v0.3.1.png'
W,H=Image.open(ORIGINAL).size
NAV_W,NAV_H=209,118
SCALE=8
# Labels (each is assigned a distinctive RGB color below)
FIELD, ROAD, WOODS, BUILDING, WATER, BRIDGE = range(6)
canvas=np.full((H,W),FIELD,dtype=np.uint8)

def poly(points,label):
    cv2.fillPoly(canvas,[np.asarray(points,np.int32)],int(label))

def stroke(points,label,thickness):
    cv2.polylines(canvas,[np.asarray(points,np.int32)],False,int(label),int(thickness),cv2.LINE_8)

# Slow but traversable tree lines, following visual grove silhouettes.
forests=[
    ([(0,206),(105,225),(200,215),(310,220),(420,200),(535,210),(680,190),(835,204),(970,216),(1120,217),(1240,250),(1480,234),(1670,228)],52),
    ([(0,565),(180,585),(335,565),(500,560),(650,550),(820,550),(965,572),(1110,595),(1300,590),(1490,578),(1670,590)],65),
    ([(675,0),(650,95),(620,187),(590,310),(610,445),(665,560),(735,675),(790,815),(855,940)],55),
    ([(170,0),(195,160),(220,305),(212,470),(172,600)],48),
    ([(1470,0),(1480,180),(1470,360),(1520,530)],36),
]
for points,t in forests: stroke(points,WOODS,t)

# Named dirt roads, represented as connected corridors, walkable and preferred.
roads=[
 ([(278,-30),(310,125),(352,285),(380,437),(414,580),(443,720),(486,970)],32),
 ([(0,725),(185,669),(350,595),(510,500),(682,452),(845,439),(985,407),(1138,395),(1250,358),(1300,326)],32),
 ([(1175,-20),(1220,150),(1248,315),(1265,440),(1330,550),(1440,674),(1660,813)],39),
 ([(1243,328),(1365,354),(1500,323),(1680,284)],29),
 ([(400,743),(490,645),(620,610),(740,590)],18),
]
for points,t in roads: stroke(points,ROAD,t)

# Seasonal wet ditch is visible in the approved artwork near the eastern fields.
# It cannot be traversed except the road/culvert crossing (marked BRIDGE).
water=[(1045,284),(1065,302),(1073,323),(1084,345),(1097,365),(1104,381),(1108,413)]
stroke(water,WATER,17)
stroke([(1084,374),(1106,394),(1117,407)],BRIDGE,23)

# Individual blocked roof footprints, including clearance around the building.
# NW village upper-right of the image.
for p in [
 [(1008,81),(1038,65),(1073,113),(1043,142),(1007,126)],
 [(1102,47),(1139,67),(1152,112),(1114,132),(1085,99)],
 [(1076,129),(1118,122),(1128,158),(1097,177),(1064,156)],
 [(1150,132),(1181,137),(1193,173),(1159,186),(1137,166)],
 # lower left hamlet
 [(222,774),(255,767),(276,830),(238,850),(218,825)],
 [(304,748),(333,731),(356,773),(317,798)],
 [(350,702),(392,679),(422,748),(371,764)],
 [(326,805),(381,798),(407,834),(356,854)],
 [(429,754),(469,741),(485,796),(445,818)],
 # southeast cottages
 [(1430,660),(1484,635),(1521,689),(1481,734),(1436,710)],
 [(1359,761),(1396,738),(1441,792),(1400,823),(1365,795)],
 [(1463,816),(1508,792),(1539,838),(1492,868)],
]: poly(p,BUILDING)

# Expand solid obstacles by a couple of original image pixels, roughly the ball radius.
solid=(canvas==BUILDING).astype(np.uint8)
kernel=cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(17,17))
expanded=cv2.dilate(solid,kernel,iterations=1)
canvas[expanded>0]=BUILDING
# Downsample annotations conservatively: a cell intersecting any building/creek is solid.
# Allow bridges only for the explicitly marked culvert cells.
smooth=cv2.resize(canvas,(NAV_W,NAV_H),interpolation=cv2.INTER_NEAREST)
for y in range(NAV_H):
 for x in range(NAV_W):
  window=canvas[y*SCALE:min((y+1)*SCALE,H),x*SCALE:min((x+1)*SCALE,W)]
  if np.any(window==BUILDING): smooth[y,x]=BUILDING
  elif np.any(window==WATER) and not np.any(window==BRIDGE): smooth[y,x]=WATER
# Restore bridge center (overrides water where marked); ensure single crossing
for y in range(NAV_H):
 for x in range(NAV_W):
  win=canvas[y*SCALE:min((y+1)*SCALE,H),x*SCALE:min((x+1)*SCALE,W)]
  if np.count_nonzero(win==BRIDGE)>40 and smooth[y,x]!=BUILDING: smooth[y,x]=BRIDGE
# Use unambiguous RGB primaries readable through Godot Texture.get_image().
palette=np.asarray([[200,200,200],[255,0,0],[0,255,0],[0,0,0],[0,0,255],[255,255,0]],dtype=np.uint8)
Image.fromarray(palette[smooth],mode='RGB').save(OUTPUT,optimize=True)
print('map:',(W,H),'nav:',(NAV_W,NAV_H),'counts:',dict(zip(['field','road','forest','building','water','bridge'],np.bincount(smooth.ravel(),minlength=6).tolist())))
# Debug overlay, NOT included in gameplay; walls highlighted in red.
art=np.array(Image.open(ORIGINAL).convert('RGB'))
resized=cv2.resize(smooth,(W,H),interpolation=cv2.INTER_NEAREST)
color=np.zeros_like(art); color[resized==BUILDING]=(255,40,40);color[resized==WATER]=(0,65,255);color[resized==BRIDGE]=(255,220,0)
show=np.where(np.isin(resized,[BUILDING,WATER,BRIDGE])[...,None],(art*0.48+color*0.52).astype(np.uint8),art)
Image.fromarray(show).save(ROOT/'tools/nav_debug_preview.png')
