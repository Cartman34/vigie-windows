from PIL import Image, ImageDraw
import math, sys, os
OUT=sys.argv[1]
def pt(cx,cy,r,deg):
    a=math.radians(deg); return (cx+r*math.cos(a), cy+r*math.sin(a))
def darken(rgb,f): return tuple(int(v*f) for v in rgb)
def make(color, frac, out):
    M=1024
    img=Image.new('RGBA',(M,M),(0,0,0,0)); d=ImageDraw.Draw(img)
    cx=cy=M/2; r=M*0.35; sw=M*0.11
    A0=135.0; SPAN=270.0; ang=A0+frac*SPAN
    R,G,B=color; val=(R,G,B,255)
    rr=M*0.45; d.ellipse([cx-rr,cy-rr,cx+rr,cy+rr], outline=(R,G,B,int(0.35*255)), width=max(1,int(round(M*0.024))))
    def arc_round(rad,s0,s1,col,width):
        d.arc([cx-rad,cy-rad,cx+rad,cy+rad],s0,s1,fill=col,width=int(round(width)))
        cr=width/2.0
        for a in (s0,s1):
            px,py=pt(cx,cy,rad,a); d.ellipse([px-cr,py-cr,px+cr,py+cr],fill=col)
    arc_round(r,A0,A0+SPAN,(0x30,0x36,0x3d,255),sw)
    tw=max(1,int(round(M*0.02)))
    for i in range(0,7):
        a=A0+(i/6.0)*SPAN
        x0,y0=pt(cx,cy,r*0.98,a); x1,y1=pt(cx,cy,r*0.80,a)
        d.line([x0,y0,x1,y1], fill=(0x8b,0x94,0x9e,int(0.35*255)), width=tw)
    arc_round(r,A0,ang,val,sw)
    tx,ty=pt(cx,cy,-M*0.06,ang); nx,ny=pt(cx,cy,r*0.92,ang)
    def line_round(x0,y0,x1,y1,col,width):
        d.line([x0,y0,x1,y1],fill=col,width=int(round(width))); cr=width/2.0
        for (px,py) in ((x0,y0),(x1,y1)): d.ellipse([px-cr,py-cr,px+cr,py+cr],fill=col)
    dcol=darken((R,G,B),0.72)+(int(0.95*255),)
    line_round(tx,ty,nx,ny, dcol, M*0.098)
    line_round(tx,ty,nx,ny, val,  M*0.082)
    hr=M*0.095; d.ellipse([cx-hr,cy-hr,cx+hr,cy+hr],fill=val)
    wr=M*0.042; d.ellipse([cx-wr,cy-wr,cx+wr,cy+wr],fill=(0xf0,0xf6,0xfc,255))
    base=img.resize((256,256),Image.LANCZOS)
    base.save(out, format='ICO', sizes=[(256,256),(48,48),(32,32),(24,24),(20,20),(16,16)])
# Fractions du niveau (voir docs/DECISIONS-VALIDEES.md) :
#   conforme = 1.00 -> jauge PLEINE (v2). Doit rester identique au repli GDI+ de tray.ps1.
make((63,185,80),  1.00, os.path.join(OUT,'ok.ico'))
make((210,153,34), 0.50, os.path.join(OUT,'warn.ico'))
make((248,81,73),  0.14, os.path.join(OUT,'error.ico'))
print('OK', sorted(x for x in os.listdir(OUT) if x.endswith('.ico')))
