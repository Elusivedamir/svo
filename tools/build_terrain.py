"""Rebuild deterministic fictional top-down farmland terrain for SVO prototype.

Dependencies: pillow, numpy, opencv-python. Run offline on a laptop, not in APK.
All coordinates match data/map_v0.3.json; visual art is one replaceable layer.
"""
from pathlib import Path
import math
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT=Path(__file__).resolve().parents[1]/'assets/map/terrain_v0.3.png'
W,H=3200,1800
rng=np.random.default_rng(133705)


def noise(w, h, nx,ny):
    small=rng.normal(0,1,(ny,nx)).astype('float32')
    return cv2.resize(small,(w,h),interpolation=cv2.INTER_CUBIC)

# No square-tile repetitions: several large-scale and grain noise fields.
large=noise(W,H,18,10)
medium=noise(W,H,125,75)
fine=noise(W,H,800,460)
pixel=rng.normal(0,1,(H,W)).astype('float32')
yy,xx=np.mgrid[0:H,0:W]
terrain=np.empty((H,W,3),dtype=np.float32)
terrain[:]=np.array((111,105,73),dtype=np.float32)
fields=[
    ([(0,0),(1200,0),(1025,620),(0,700)],(126,119,79),-0.40,17),
    ([(1200,0),(2290,0),(2120,733),(1025,620)],(144,124,80),0.15,20),
    ([(2290,0),(W,0),(W,798),(2120,733)],(107,116,78),0.75,19),
    ([(0,700),(1025,620),(1435,1220),(0,1300)],(130,112,76),0.35,25),
    ([(1025,620),(2120,733),(2280,1265),(1435,1220)],(97,110,76),-0.29,15),
    ([(2120,733),(W,798),(W,1370),(2280,1265)],(146,125,76),0.25,22),
    ([(0,1300),(1435,1220),(1560,H),(0,H)],(98,101,70),0.54,19),
    ([(1435,1220),(2280,1265),(2320,H),(1560,H)],(145,125,83),-0.67,21),
    ([(2280,1265),(W,1370),(W,H),(2320,H)],(113,107,76),0.46,18),
]
for polygon,color,theta,period in fields:
    mask=np.zeros((H,W),dtype=np.uint8)
    cv2.fillPoly(mask,[np.array(polygon,dtype=np.int32)],255)
    projected=xx*math.cos(theta)+yy*math.sin(theta)
    # Alternating crop/stubble row tones, with breaks and natural variation.
    rows=(np.sin(projected*(math.tau/period)+medium*0.28)*1.7
          +np.sin(projected*(math.tau/(period*5.7)))*0.7)
    variation=(large*6.4+medium*4.1+fine*2.6+pixel*1.9+rows)
    region=np.stack([color[0]+variation,color[1]+variation*.92,color[2]+variation*.68],axis=-1)
    terrain[mask>0]=region[mask>0]

# Narrow field margins: no artificial rectangular grid.
img=Image.fromarray(np.uint8(np.clip(terrain,0,255)),'RGB')
linework=Image.new('RGBA',(W,H),(0,0,0,0))
d=ImageDraw.Draw(linework,'RGBA')
for poly,_,_,_ in fields:
    pts=[tuple(x) for x in poly]
    d.line(pts+[pts[0]],fill=(46,51,37,38),width=5)
    d.line(pts+[pts[0]],fill=(203,186,122,25),width=2)
img=Image.alpha_composite(img.convert('RGBA'),linework)

def line_path(point_fn, count, start, end):
    return [(int(point_fn(t)[0]),int(point_fn(t)[1])) for t in np.linspace(start,end,count)]

# A few long tree belts between the fields. They will eventually become
# independent gameplay visibility and collision polygons.
belts=[
    (line_path(lambda t:(t,560+64*math.sin(t/360)+0.055*t),105,-80,3280),75,7),
    (line_path(lambda t:(t,1340+48*math.sin(t/285)-0.04*t),110,-80,3280),91,9),
    (line_path(lambda t:(1040+0.25*t+48*math.sin(t/200),t),65,-80,1880),70,5),
    (line_path(lambda t:(2460+60*math.sin(t/310),t),75,-30,1840),72,5),
    (line_path(lambda t:(310+0.09*t+25*math.sin(t/170),t),55,0,1420),53,4),
]
forest_mask=Image.new('L',(W,H),0)
fd=ImageDraw.Draw(forest_mask)
for points,width,_ in belts:
    fd.line(points,fill=210,width=width+42,joint='curve')
    fd.line(points,fill=255,width=width,joint='curve')
forest_mask=forest_mask.filter(ImageFilter.GaussianBlur(7))
forest_tint=Image.new('RGBA',(W,H),(41,65,42,225))
img=Image.composite(forest_tint,img,forest_mask).convert('RGBA')

# Trees are overlapping canopy shapes with northwest sunlight and shadows.
canopy=Image.new('RGBA',(W,H),(0,0,0,0))
td=ImageDraw.Draw(canopy,'RGBA')
def tree(cx,cy,r):
    k=float(rng.uniform(0.75,1.17))
    r=max(5,int(r*k))
    td.ellipse((cx+6-r,cy+6-r,cx+6+r,cy+6+r),fill=(9,17,15,132))
    color= rng.choice([0,1,2,3,4])
    palette=[(40,67,42),(50,75,43),(63,81,47),(45,66,37),(67,79,46)]
    rr,gg,bb=palette[color]
    td.ellipse((cx-r,cy-r,cx+r,cy+r),fill=(rr,gg,bb,255))
    for j in range(5):
        angle=j*math.tau/5+rng.uniform(-0.4,0.4)
        rad=r*rng.uniform(0.24,0.61)
        x=cx+math.cos(angle)*rad
        y=cy+math.sin(angle)*rad
        subr=r*rng.uniform(.34,.59)
        td.ellipse((x-subr,y-subr,x+subr,y+subr),fill=(rr+int(rng.integers(-8,9)),gg+int(rng.integers(-10,14)),bb+int(rng.integers(-4,9)),235))
    light=r*.45
    td.ellipse((cx-r*.61,cy-r*.68,cx-r*.61+light,cy-r*.68+light),fill=(112,117,76,75))

for points,width,seed in belts:
    pts=np.array(points,dtype=float)
    length=np.linalg.norm(np.diff(pts,axis=0),axis=1)
    cumulative=np.r_[0,np.cumsum(length)]
    count=int(cumulative[-1]/11.0)*max(2,seed//4)
    for _ in range(count):
        s=rng.uniform(0,cumulative[-1]);j=min(len(length)-1,max(0,np.searchsorted(cumulative,s)-1))
        t=(s-cumulative[j])/max(length[j],0.01)
        p=pts[j]*(1-t)+pts[j+1]*t
        offset=rng.normal(0,width*0.28)
        p+=np.array([-(pts[j+1,1]-pts[j,1]),pts[j+1,0]-pts[j,0]])/max(length[j],0.1)*offset
        if -30<p[0]<W+30 and -30<p[1]<H+30:
            tree(float(p[0]),float(p[1]),int(rng.integers(8,19)))
# Field-edge bushes / isolated young trees, not human-scale dots.
for _ in range(90):
    x=int(rng.uniform(0,W));y=int(rng.uniform(0,H))
    if float(rng.random())<.28:
        tree(x,y,int(rng.integers(6,11)))
img=Image.alpha_composite(img,canopy)

# Dirt farm roads cut across tree rows naturally; wheel ruts and shoulders.
roads=[
    [(0,1610),(320,1520),(670,1450),(1080,1230),(1510,1080),(1910,1010),(2360,790),(2780,750),(3200,660)],
    [(470,0),(585,250),(704,545),(815,880),(895,1120),(1000,1470),(1080,H)],
    [(3150,1750),(2820,1620),(2560,1410),(2380,1100),(2360,790),(2300,430),(2110,0)],
]
road_layer=Image.new('RGBA',(W,H),(0,0,0,0))
rd=ImageDraw.Draw(road_layer,'RGBA')
for idx,control in enumerate(roads):
    # Catmull-Rom spline interpolation: natural curves, no sharp paved corners.
    c=np.array(control,dtype=float)
    smooth=[]
    for i in range(len(c)-1):
        p0=c[max(i-1,0)];p1=c[i];p2=c[i+1];p3=c[min(i+2,len(c)-1)]
        for t in np.linspace(0,1,18,endpoint=False):
            q=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t**3)
            smooth.append((int(q[0]),int(q[1])))
    smooth.append(tuple(c[-1].astype(int)))
    rd.line(smooth,fill=(26,24,19,116),width=47,joint='curve')
    rd.line(smooth,fill=(115,94,61,250),width=39,joint='curve')
    rd.line(smooth,fill=(92,77,53,255),width=31,joint='curve')
    for offset,col in [(-10,(68,57,44,185)),(10,(68,57,44,185)),(-4,(157,131,88,90)),(4,(157,131,88,90))]:
        rut=[]
        for j,p in enumerate(smooth):
            prior=smooth[max(j-1,0)]; nxt=smooth[min(j+1,len(smooth)-1)]
            dx,dy=nxt[0]-prior[0],nxt[1]-prior[1]
            d=math.hypot(dx,dy)+1e-4
            rut.append((int(p[0]-dy/d*offset),int(p[1]+dx/d*offset)))
        rd.line(rut,fill=col,width=4,joint='curve')
    # occasional damp, not tiled repeating features.
    for j in range(12,len(smooth),19):
        if rng.uniform()>.73:
            x,y=smooth[j];r=int(rng.integers(5,17));rd.ellipse((x-r,y-r/3,x+r,y+r/3),fill=(53,57,49,145))
img=Image.alpha_composite(img,road_layer).convert('RGB')
# Natural subtle paper/terrain finishing (no HUD, no labels).
arr=np.asarray(img).astype(np.float32)
arr += (noise(W,H,400,250)*1.1)[:,:,None]
arr=np.uint8(np.clip(arr,0,255))
Image.fromarray(arr).save(OUT,optimize=True)
print('wrote',OUT,OUT.stat().st_size)
