# @author Florent HAZARD <f.hazard@sowapps.com>
# -*- coding: utf-8 -*-
"""Vigie's OWN icon font (vigie-icons.ttf).

WHY THIS FILE IS STILL IN PYTHON (D41, subject S08)
---------------------------------------------------
PHP is the default tool, PowerShell the one for Windows tools, and a .py file is an argued
decision -- never a habit. Here is the argument, so it is read here and nowhere else: this
script WRITES A TrueType FONT. Neither .NET nor PHP can write one. Converting it would mean
hand-writing a font generator -- the glyf, loca, cmap, head, hhea, hmtx, maxp, name, post
and OS/2 tables with their checksums -- for a script that runs the day an icon changes. The
cost bears no relation to the gain.

The other generator, the client app's icons, WAS converted on 07/10: GDI+ ships with
Windows, where Pillow had to be installed. One Python file is left in the repository, and
the check-naming ratchet came down to 1.

Same philosophy as generate-icons.ps1 for the client app (D01): the source of truth is THIS
script; the generated font is versioned beside it and replayable. The icons are REAL
characters (private use area, U+E001...), used in the front end through the .vi CSS class
plus a data attribute or the glyph's entity.

Drawing: a 1000 UPM grid, baseline at 0, icons drawn roughly inside [0..1000]x[0..800].
TrueType contours (non-zero fill): the outer contour runs clockwise, the inner one -- the
hole -- runs anti-clockwise.

Usage:  python generate-icon-font.py     (writes vigie-icons.ttf here)
"""
import math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1000
ADV = 1000  # one advance for all: the icons are square, the CSS alignment does the rest


# --------------------------------------------------------------------------- helpers
def circle(pen, cx, cy, r, clockwise=True):
    """A circle approximated with quadratics (8 segments). clockwise=False means a hole."""
    pts = []
    n = 16
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    if clockwise:
        pts = pts[::-1]
    pen.moveTo(pts[0])
    # even points sit on the curve, odd ones are controls (an even approximation)
    for i in range(1, n, 2):
        ctrl = pts[i]
        fin = pts[(i + 1) % n]
        # push the control point out slightly to stay close to a true circle
        k = 1.08
        cxx = cx + (ctrl[0] - cx) * k
        cyy = cy + (ctrl[1] - cy) * k
        pen.qCurveTo((cxx, cyy), fin)
    pen.closePath()


def poly(pen, points, clockwise=True):
    pts = points[::-1] if clockwise else points
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def ring(pen, cx, cy, r_outer, thickness):
    circle(pen, cx, cy, r_outer, clockwise=True)
    circle(pen, cx, cy, r_outer - thickness, clockwise=False)


def rect(pen, x0, y0, x1, y1, clockwise=True):
    poly(pen, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], clockwise)


def rounded_rect(pen, x0, y0, x1, y1, r, clockwise=True):
    pts = []
    n = 4
    coins = [
        (x1 - r, y1 - r, 0.0),      # haut droit
        (x0 + r, y1 - r, 90.0),     # haut gauche
        (x0 + r, y0 + r, 180.0),    # bas gauche
        (x1 - r, y0 + r, 270.0),    # bas droit
    ]
    for cx, cy, a0 in coins:
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    poly(pen, pts, clockwise)


# --------------------------------------------------------------------------- glyphes
def g_gear(pen):
    """Engrenage : 8 teeth + ring."""
    cx, cy, r = 500, 400, 260
    teeth = []
    n = 8
    for i in range(n):
        a = 2 * math.pi * i / n
        w = 0.22  # half-largeur angulaire d'une dent
        for da, rr in ((-w, r), (-w * 0.6, r + 110), (w * 0.6, r + 110), (w, r)):
            teeth.append((cx + rr * math.cos(a + da), cy + rr * math.sin(a + da)))
    poly(pen, teeth, clockwise=True)
    circle(pen, cx, cy, 120, clockwise=False)


def g_puzzle(pen):
    """Piece de puzzle : tenon en HAUT, encoche a DROITE, les deux bien marques.

    Un seul contour ferme : superposer un carre et des cercles laissait voir les
    jonctions. Le rayon (170 pour un corps de 660) est celui des icones du genre --
    en dessous, le relief ne se lit plus a 16 px (essai a 115 : on ne voyait rien).
    """
    import math
    r = 170.0
    x0, y0, x1, y1 = 170.0, 170.0, 830.0, 830.0
    cx_tenon, cy_encoche = 470.0, 470.0
    N = 22
    pts = [(x0, y0), (x1, y0)]                       # bord bas

    # Bord droit : on monte, et l'ENCOCHE rentre vers l'interieur.
    pts.append((x1, cy_encoche - r))
    for i in range(1, N):
        a = -math.pi / 2 + math.pi * i / N
        pts.append((x1 - r * math.cos(a), cy_encoche + r * math.sin(a)))
    pts.append((x1, cy_encoche + r))
    pts.append((x1, y1))

    # The top edge: heading left, with the TAB sticking up.
    pts.append((cx_tenon + r, y1))
    for i in range(1, N):
        a = math.pi * i / N
        pts.append((cx_tenon + r * math.cos(a), y1 + r * math.sin(a)))
    pts.append((cx_tenon - r, y1))
    pts.append((x0, y1))

    poly(pen, pts, clockwise=True)


def g_flag(pen):
    """Fanion (notifications de l'onglet) : hampe + drapeau."""
    rect(pen, 200, 40, 260, 760, clockwise=True)
    poly(pen, [(260, 740), (760, 620), (260, 470)], clockwise=True)


def g_bell(pen):
    """Cloche, d'apres l'icone « bell » de Font Awesome (solid, viewBox 448 x 512).

    Proportions relevees sur l'originale et respectees ici :
      corps 416 x 365 (donc PLUS LARGE QUE HAUT), bouton du haut 64 x 50,
      battant 128 de large en half-disque sous la base, total 448 x 512.
    Deux essais precedents ont rate faute de tenir ce rapport : dome ecrase d'abord,
    corps etroit et long ensuite.
    """
    import math
    # 0.90: the bell looked bigger than its neighbours. The other glyphs carry between 640
    # and 740 of ink; at 776 tall, this one stood out.
    K = 682 / 448.0 * 0.90
    half   = 208 * K
    body_height = 365 * K
    y_bottom   = 250.0

    # The body: almost straight sides at the bottom, a rounded shoulder at the top.
    N = 40
    pts = []
    for i in range(N + 1):
        t = i / float(N)
        pts.append((500 - half * ((1 - t ** 3.0) ** 0.42), y_bottom + body_height * t))
    for i in range(N, -1, -1):
        t = i / float(N)
        pts.append((500 + half * ((1 - t ** 3.0) ** 0.42), y_bottom + body_height * t))
    poly(pen, pts, clockwise=True)

    # The base: the horizontal edge, a little wider than the body.
    rounded_rect(pen, 500 - half - 22, y_bottom - 46, 500 + half + 22, y_bottom + 8, 24, clockwise=True)

    # The button on top.
    rounded_rect(pen, 500 - 32 * K, y_bottom + body_height - 10, 500 + 32 * K, y_bottom + body_height + 50 * K, 22, clockwise=True)

    # The clapper: a half-disc under the base.
    r = 64 * K
    arcpts = [(500 + r * math.cos(math.pi + math.pi * i / 24.0),
               y_bottom - 46 + r * math.sin(math.pi + math.pi * i / 24.0)) for i in range(25)]
    poly(pen, arcpts, clockwise=True)


def g_sun(pen):
    """Sun: a disc and eight rays."""
    circle(pen, 500, 400, 190, clockwise=True)
    for i in range(8):
        a = 2 * math.pi * i / 8
        ca, sa = math.cos(a), math.sin(a)
        px, py = -sa, ca
        w = 38
        r0, r1 = 260, 400
        poly(pen, [
            (500 + r0 * ca + w * px, 400 + r0 * sa + w * py),
            (500 + r1 * ca + w * 0.6 * px, 400 + r1 * sa + w * 0.6 * py),
            (500 + r1 * ca - w * 0.6 * px, 400 + r1 * sa - w * 0.6 * py),
            (500 + r0 * ca - w * px, 400 + r0 * sa - w * py),
        ], clockwise=True)


def g_moon(pen):
    """A crescent in ONE contour (two arcs). A hole overflowing the disc would FILL IN
    under non-zero fill instead of cutting -- seen on the first attempt."""
    import math as _m
    c1, r1 = (470, 390), 320    # disque porteur
    c2, r2 = (640, 480), 300    # circle qui mord
    d = _m.hypot(c2[0] - c1[0], c2[1] - c1[1])
    # where the two circles meet
    a_ = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    h = _m.sqrt(r1 * r1 - a_ * a_)
    mx = c1[0] + a_ * (c2[0] - c1[0]) / d
    my = c1[1] + a_ * (c2[1] - c1[1]) / d
    ux, uy = (c2[0] - c1[0]) / d, (c2[1] - c1[1]) / d
    p1 = (mx + h * -uy, my + h * ux)
    p2 = (mx - h * -uy, my - h * ux)
    def arc(c, r, pa, pb, sens, n=24):
        aa = _m.atan2(pa[1] - c[1], pa[0] - c[0])
        ab = _m.atan2(pb[1] - c[1], pb[0] - c[0])
        if sens > 0:
            while ab <= aa: ab += 2 * _m.pi
        else:
            while ab >= aa: ab -= 2 * _m.pi
        return [(c[0] + r * _m.cos(aa + (ab - aa) * i / n),
                 c[1] + r * _m.sin(aa + (ab - aa) * i / n)) for i in range(n + 1)]
    # the disc's long arc -- the crescent's outside -- then the biting circle's arc back
    chemin = arc(c1, r1, p1, p2, sens=+1) + arc(c2, r2, p2, p1, sens=-1)[1:]
    poly(pen, chemin, clockwise=True)


def g_info(pen):
    """A circled i, drawn to stay legible at 12 px: a THIN ring, a LARGE i, and room.
    (the earlier version -- a 70 ring and a small i -- melted into a donut when small)."""
    ring(pen, 500, 400, 385, 52)
    # The dot is EXACTLY as wide as the stem (130): any larger and it spills over and
    # unbalances the i (reported by the owner).
    circle(pen, 500, 578, 65, clockwise=True)
    rounded_rect(pen, 435, 170, 565, 445, 56, clockwise=True)


def g_refresh(pen):
    """Refresh: a 300-degree arc and an arrow head."""
    cx, cy, r, ep = 500, 400, 260, 84
    a0, a1 = math.radians(60), math.radians(360)
    n = 20
    ext = [(cx + (r + ep / 2) * math.cos(a0 + (a1 - a0) * i / n),
            cy + (r + ep / 2) * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    inn = [(cx + (r - ep / 2) * math.cos(a0 + (a1 - a0) * i / n),
            cy + (r - ep / 2) * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n, -1, -1)]
    poly(pen, ext + inn, clockwise=True)
    # the head sits at the arc's start (angle a0)
    ax = cx + r * math.cos(a0)
    ay = cy + r * math.sin(a0)
    t = a0 - math.pi / 2  # tangente vers l'exterieur de l'arc
    tx, ty = math.cos(t), math.sin(t)
    px, py = -ty, tx
    poly(pen, [
        (ax + 170 * tx, ay + 170 * ty),
        (ax + 150 * px, ay + 150 * py),
        (ax - 150 * px, ay - 150 * py),
    ], clockwise=True)


def g_dots(pen):
    """Three dots stacked (a card's menu)."""
    for cy in (160, 400, 640):
        circle(pen, 500, cy, 78, clockwise=True)


def g_check(pen):
    """Check mark: two arms of constant thickness around the lower vertex."""
    import math as _m
    A = (130, 420)   # bout du bras court (haut gauche)
    V = (380, 150)   # sommet bas de la coche
    B = (880, 660)   # bout du bras long (haut droit)
    e = 62           # half-epaisseur
    def _n(p, q):
        dx, dy = q[0] - p[0], q[1] - p[1]
        l = _m.hypot(dx, dy)
        return (-dy / l, dx / l)
    n1 = _n(A, V)    # normale du bras court
    n2 = _n(V, B)    # normale du bras long
    poly(pen, [
        (A[0] + n1[0] * e, A[1] + n1[1] * e),
        (V[0] + n1[0] * e + n2[0] * e, V[1] + n1[1] * e + n2[1] * e),
        (B[0] + n2[0] * e, B[1] + n2[1] * e),
        (B[0] - n2[0] * e, B[1] - n2[1] * e),
        (V[0], V[1]),
        (A[0] - n1[0] * e, A[1] - n1[1] * e),
    ], clockwise=True)


def g_warn(pen):
    """Warning triangle: the outline, the stem and the dot."""
    poly(pen, [(500, 780), (60, 60), (940, 60)], clockwise=True)
    poly(pen, [(500, 660), (180, 130), (820, 130)], clockwise=False)
    rounded_rect(pen, 455, 320, 545, 560, 40, clockwise=True)
    circle(pen, 500, 220, 55, clockwise=True)


def g_cross(pen):
    """Cross (error, or close): two bars at 45 degrees."""
    import math as _m
    e = 62
    for (A, B) in [((190, 190), (810, 810)), ((190, 810), (810, 190))]:
        dx, dy = B[0] - A[0], B[1] - A[1]
        l = _m.hypot(dx, dy)
        nx, ny = -dy / l * e, dx / l * e
        poly(pen, [(A[0] + nx, A[1] + ny), (B[0] + nx, B[1] + ny),
                   (B[0] - nx, B[1] - ny), (A[0] - nx, A[1] - ny)], clockwise=True)


def g_users(pen):
    """Users: two silhouettes, head and SHOULDERS, as this kind of icon is drawn.

    Trois essais avant celui-ci, et ce qu'ils ont appris :
      - silhouettes qui se chevauchent : elles fusionnent en une masse ;
      - lisere vide pour les separer : en remplissage non-zero, il CREUSE la silhouette
        de devant la ou le fond est absent ;
      - buste rond detache de la tete : on lit quatre boules, pas deux personnes.
    Ce qui marche : un buste en DOME (des epaules), qui touche la tete, et un vrai espace
    entre les deux personnes. Verifie au rendu jusqu'a 16 px.
    """
    import math

    def personne(cx, cy_tete, r_tete, half_width, shoulder_height, base):
        circle(pen, cx, cy_tete, r_tete, clockwise=True)
        pts = []
        n = 26
        for i in range(n + 1):
            a = math.pi - math.pi * i / n          # de gauche a droite, par le sommet
            pts.append((cx + half_width * math.cos(a), base + shoulder_height * math.sin(a)))
        pts.append((cx + half_width, base))
        pts.append((cx - half_width, base))
        poly(pen, pts, clockwise=True)

    # In front: larger, on the left. The shoulders rise to 560 and the head comes down to
    # 545, so they overlap and the silhouette is one single shape.
    personne(cx=350, cy_tete=690, r_tete=148, half_width=205, shoulder_height=370, base=190)
    # Beside it: smaller, a little lower, and NOT touching the first one (60 of gap).
    personne(cx=765, cy_tete=628, r_tete=102, half_width=140, shoulder_height=270, base=215)


ICONS = {
    # name -> (PUA code point, the function that draws it)
    'gear':    (0xE001, g_gear),
    'puzzle':  (0xE002, g_puzzle),
    'flag':    (0xE003, g_flag),
    'bell':    (0xE004, g_bell),
    'sun':     (0xE005, g_sun),
    'moon':    (0xE006, g_moon),
    'info':    (0xE007, g_info),
    'refresh': (0xE008, g_refresh),
    'dots':    (0xE009, g_dots),
    'check':   (0xE00A, g_check),
    'warn':    (0xE00B, g_warn),
    'cross':   (0xE00C, g_cross),
    'users':   (0xE00D, g_users),
}


def main():
    import os
    noms = ['.notdef'] + list(ICONS.keys())
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(noms)
    fb.setupCharacterMap({cp: nom for nom, (cp, _) in ICONS.items()})
    glyphes = {}
    pen = TTGlyphPen(None)
    glyphes['.notdef'] = pen.glyph()
    from fontTools.pens.transformPen import TransformPen
    from fontTools.pens.recordingPen import RecordingPen
    from fontTools.pens.boundsPen import BoundsPen
    for nom, (_, dessin) in ICONS.items():
        # 1. the drawing is recorded, 2. its ink box is measured, 3. it is translated
        # EXACTLY so the ink centre lands on (500, 300) -- the centre of the advance (1000)
        # and of the line (ascent 800 / descent 200). A flat -100 assumed every drawing was
        # centred on (500, 400): false for some of them, hence icons sitting askew.
        rec = RecordingPen()
        dessin(rec)
        bp = BoundsPen(None)
        rec.replay(bp)
        dx, dy = 0, 0
        if bp.bounds:
            x0, y0, x1, y1 = bp.bounds
            dx = 500 - (x0 + x1) / 2.0
            dy = 300 - (y0 + y1) / 2.0
        pen = TTGlyphPen(None)
        rec.replay(TransformPen(pen, (1, 0, 0, 1, dx, dy)))
        glyphes[nom] = pen.glyph()
    fb.setupGlyf(glyphes)
    # LSB = each glyph's REAL xMin: declaring a different one makes the rasterizer shift
    # the drawing (seen: icons slid about 4 px to the left at a 17 px size).
    def lsb(n):
        g = glyphes[n]
        return getattr(g, 'xMin', 0) or 0
    fb.setupHorizontalMetrics({n: (ADV, lsb(n)) for n in noms})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupNameTable({'familyName': 'Vigie Icons', 'styleName': 'Regular',
                       'fullName': 'Vigie Icons', 'psName': 'VigieIcons-Regular',
                       'copyright': 'Sowapps - Vigie, MIT'})
    fb.setupPost()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vigie-icons.ttf')
    fb.save(out)
    print('ecrit', out, os.path.getsize(out), 'octets,', len(ICONS), 'glyphes')


if __name__ == '__main__':
    main()
