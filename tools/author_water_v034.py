"""Rebuild navigability for the approved unique map. The original v0.3.3 data
must remain intact. Water is a non-walkable continuous barrier, with three authored
bridge openings. Edit the listed points to fix alignment on later passes."""
from pathlib import Path
from PIL import Image
import numpy as np, cv2
ROOT=Path(__file__).resolve().parents[1]
W,H=(1672,940)
# Keep previous working semantic zones outside water. Replace only water and bridges.
old=np.array(Image.open(ROOT/'assets/map/navigation_v0.3.3.png').convert('RGB'))
FIELD=(200,200,200); ROAD=(255,0,0); WOODS=(0,255,0); HOUSE=(0,0,0); WATER=(0,0,255); BRIDGE=(255,255,0)
nav=cv2.resize(old,(W,H),interpolation=cv2.INTER_NEAREST)
for col in [WATER,BRIDGE]:
    nav[np.all(nav==col,axis=2)]=FIELD
# Map a continuous barrier according to visually inspected river bends.
# Make waterways conservatively wider than the dark pixel interior: ball has radius.
wmask=np.zeros((H,W),np.uint8)
def line(pts,thick):
    cv2.polylines(wmask,[np.array(pts,np.int32)],False,255,thick,cv2.LINE_8)
    for pt in [pts[0],pts[-1]]: cv2.circle(wmask,pt,thick//2,255,-1)
def polygon(pts):cv2.fillPoly(wmask,[np.array(pts,np.int32)],255)
# Left branching meander from upper-left region to western wetland.
line([(230,109),(230,167),(209,222),(176,251),(168,269),(199,286),(247,303),(293,329),(324,349),(347,382),(363,406),(397,432),(443,449),(480,477),(522,496),(569,516),(621,522),(675,542),(725,563)],42)
line([(0,249),(36,263),(95,265),(155,276),(181,272)],35)
# Southwestern pools and broadening river near a wooded marsh.
polygon([(157,818),(196,820),(250,838),(277,867),(328,898),(335,934),(191,940),(151,906),(134,865)])
# Center-left marsh pool links into the meander, visually looks like backwater.
polygon([(480,479),(516,469),(561,480),(582,504),(573,525),(536,529),(493,511)])
# Right-hand bend, from the east edge west into a shallow wooded wetland.
line([(1672,266),(1639,295),(1600,328),(1576,358),(1554,397),(1536,418),(1511,456),(1484,480),(1455,491),(1409,508),(1357,509),(1313,505),(1273,496),(1231,490),(1189,498),(1143,512),(1096,522),(1048,540),(1005,555)],43)
# Upper right slough near the bend.
polygon([(1482,151),(1519,143),(1554,147),(1588,167),(1583,194),(1542,209),(1518,199),(1495,184)])
# Far southeast broad pond and an isolated southwest lake.
polygon([(1457,786),(1503,748),(1547,749),(1589,770),(1639,797),(1672,820),(1672,929),(1595,927),(1547,890),(1497,861)])
# Extra real-world-sized safety margin at water's edge in grid (4 original pixels per cell).
wmask=cv2.dilate(wmask,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
# Quantize blocked if ANY water in downsampled cell, not nearest sample.
Wnav,Hnav=418,236
water_low=cv2.resize(wmask,(Wnav,Hnav),interpolation=cv2.INTER_AREA)>24
# Seal small accidental gaps in marked channels; prevents diagonal shortcuts.
water_low=cv2.morphologyEx(water_low.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((3,3),np.uint8)).astype(bool)
nav_small=cv2.resize(nav,(Wnav,Hnav),interpolation=cv2.INTER_NEAREST)
nav_small[water_low]=WATER

# Only actual visible crossings receive access through the water barrier:
# Western road bridge, a narrow center footbridge, eastern road bridge.
# Bridging stroke runs from clear bank to clear bank and removes full barrier width.
bridge_canvas=np.zeros((H,W),np.uint8)
def bridge(pts,thick=16):
  cv2.polylines(bridge_canvas,[np.array(pts,np.int32)],False,255,thick,cv2.LINE_8)
bridge([(206,315),(276,286)],19)    # west, paved bridge
bridge([(428,479),(468,416)],15)    # narrow central footbridge
bridge([(1503,379),(1562,418)],19)  # east, paved bridge
bridge_low=cv2.resize(bridge_canvas,(Wnav,Hnav),interpolation=cv2.INTER_AREA)>12
# Only open intersections with marked water. Exterior areas are left as previously authored.
nav_small[bridge_low & water_low]=BRIDGE
# Each crossing must have at least 1+ nav cells bridging banks.
Image.fromarray(nav_small).save(ROOT/'assets/map/navigation_v0.3.4.png',optimize=True)


print("Updated water navigation mask",(Wnav,Hnav))
