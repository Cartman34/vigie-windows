# -*- coding: utf-8 -*-
"""Fonte d'icones MAISON de Vigie (vigie-icons.ttf).

Meme philosophie que generate-icons.py pour le tray (D01) : la source de verite est CE
script ; la fonte generee est versionnee a cote et rejouable a l'identique. Les icones
sont de VRAIS caracteres (zone d'usage privee U+E001...), utilises dans le front par la
classe CSS .vi + un data-attribut ou l'entite du glyphe.

Dessin : grille 1000 UPM, ligne de base a 0, icones dessinees dans [0..1000]x[0..800]
environ. Contours TrueType (remplissage non-zero) : contour exterieur en sens horaire,
contour interieur (trou) en sens anti-horaire.

Usage :  python generate-icon-font.py     (ecrit vigie-icons.ttf ici)
"""
import math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1000
ADV = 1000  # chasse unique : les icones sont carrees, l'alignement CSS fait le reste


# --------------------------------------------------------------------------- outils
def cercle(pen, cx, cy, r, horaire=True):
    """Cercle approxime en quadratiques (8 segments). horaire=False => trou."""
    pts = []
    n = 16
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    if horaire:
        pts = pts[::-1]
    pen.moveTo(pts[0])
    # points pairs = sur la courbe, impairs = controles (approximation reguliere)
    for i in range(1, n, 2):
        ctrl = pts[i]
        fin = pts[(i + 1) % n]
        # gonfler legerement le point de controle pour rester proche du cercle vrai
        k = 1.08
        cxx = cx + (ctrl[0] - cx) * k
        cyy = cy + (ctrl[1] - cy) * k
        pen.qCurveTo((cxx, cyy), fin)
    pen.closePath()


def poly(pen, points, horaire=True):
    pts = points[::-1] if horaire else points
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def anneau(pen, cx, cy, r_ext, epais):
    cercle(pen, cx, cy, r_ext, horaire=True)
    cercle(pen, cx, cy, r_ext - epais, horaire=False)


def rect(pen, x0, y0, x1, y1, horaire=True):
    poly(pen, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], horaire)


def rect_arrondi(pen, x0, y0, x1, y1, r, horaire=True):
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
    poly(pen, pts, horaire)


# --------------------------------------------------------------------------- glyphes
def g_gear(pen):
    """Engrenage : 8 dents + anneau."""
    cx, cy, r = 500, 400, 260
    dents = []
    n = 8
    for i in range(n):
        a = 2 * math.pi * i / n
        w = 0.22  # demi-largeur angulaire d'une dent
        for da, rr in ((-w, r), (-w * 0.6, r + 110), (w * 0.6, r + 110), (w, r)):
            dents.append((cx + rr * math.cos(a + da), cy + rr * math.sin(a + da)))
    poly(pen, dents, horaire=True)
    cercle(pen, cx, cy, 120, horaire=False)


def g_puzzle(pen):
    """Piece de puzzle : carre arrondi + tenon en haut + encoche a droite."""
    rect_arrondi(pen, 140, 60, 740, 660, 70, horaire=True)
    cercle(pen, 440, 660 + 60, 130, horaire=True)      # tenon haut (fusionne au carre)
    rect(pen, 320, 600, 560, 690, horaire=True)         # jonction du tenon
    cercle(pen, 700, 360, 125, horaire=False)           # encoche droite, mordant net


def g_flag(pen):
    """Fanion (notifications de l'onglet) : hampe + drapeau."""
    rect(pen, 200, 40, 260, 760, horaire=True)
    poly(pen, [(260, 740), (760, 620), (260, 470)], horaire=True)


def g_bell(pen):
    """Cloche : dome + battant."""
    cx = 500
    pts = [(240, 220), (240, 300)]
    n = 14
    for i in range(n + 1):
        a = math.pi * i / n
        pts.append((cx - 240 * math.cos(a), 300 + 320 * math.sin(a) * 0.92))
    pts += [(760, 300), (760, 220)]
    poly(pen, pts, horaire=True)
    rect(pen, 180, 150, 820, 225, horaire=True)
    cercle(pen, 500, 80, 70, horaire=True)


def g_sun(pen):
    """Soleil : disque + 8 rayons."""
    cercle(pen, 500, 400, 190, horaire=True)
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
        ], horaire=True)


def g_moon(pen):
    """Croissant en UN SEUL contour (deux arcs). Un trou qui deborde du disque se
    REMPLIRAIT (remplissage non-zero) au lieu de creuser -- constate sur le premier essai."""
    import math as _m
    c1, r1 = (470, 390), 320    # disque porteur
    c2, r2 = (640, 480), 300    # cercle qui mord
    d = _m.hypot(c2[0] - c1[0], c2[1] - c1[1])
    # intersections des deux cercles
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
    # grand arc du disque (exterieur du croissant), puis arc du cercle mordant en retour
    chemin = arc(c1, r1, p1, p2, sens=+1) + arc(c2, r2, p2, p1, sens=-1)[1:]
    poly(pen, chemin, horaire=True)


def g_info(pen):
    """i cercle : anneau + point + fut."""
    anneau(pen, 500, 400, 360, 70)
    cercle(pen, 500, 560, 62, horaire=True)
    rect_arrondi(pen, 445, 205, 555, 460, 48, horaire=True)


def g_refresh(pen):
    """Rafraichir : arc 300 degres + pointe de fleche."""
    cx, cy, r, ep = 500, 400, 260, 84
    a0, a1 = math.radians(60), math.radians(360)
    n = 20
    ext = [(cx + (r + ep / 2) * math.cos(a0 + (a1 - a0) * i / n),
            cy + (r + ep / 2) * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    inn = [(cx + (r - ep / 2) * math.cos(a0 + (a1 - a0) * i / n),
            cy + (r - ep / 2) * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n, -1, -1)]
    poly(pen, ext + inn, horaire=True)
    # pointe au depart de l'arc (angle a0)
    ax = cx + r * math.cos(a0)
    ay = cy + r * math.sin(a0)
    t = a0 - math.pi / 2  # tangente vers l'exterieur de l'arc
    tx, ty = math.cos(t), math.sin(t)
    px, py = -ty, tx
    poly(pen, [
        (ax + 170 * tx, ay + 170 * ty),
        (ax + 150 * px, ay + 150 * py),
        (ax - 150 * px, ay - 150 * py),
    ], horaire=True)


def g_dots(pen):
    """Trois points verticaux (menu de carte)."""
    for cy in (160, 400, 640):
        cercle(pen, 500, cy, 78, horaire=True)


def g_check(pen):
    """Coche : deux bras d'epaisseur constante autour du sommet bas."""
    import math as _m
    A = (130, 420)   # bout du bras court (haut gauche)
    V = (380, 150)   # sommet bas de la coche
    B = (880, 660)   # bout du bras long (haut droit)
    e = 62           # demi-epaisseur
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
    ], horaire=True)


def g_warn(pen):
    """Triangle d'avertissement : contour + fut + point."""
    poly(pen, [(500, 780), (60, 60), (940, 60)], horaire=True)
    poly(pen, [(500, 660), (180, 130), (820, 130)], horaire=False)
    rect_arrondi(pen, 455, 320, 545, 560, 40, horaire=True)
    cercle(pen, 500, 220, 55, horaire=True)


def g_cross(pen):
    """Croix (erreur / fermer) : deux barres a 45 degres."""
    import math as _m
    e = 62
    for (A, B) in [((190, 190), (810, 810)), ((190, 810), (810, 190))]:
        dx, dy = B[0] - A[0], B[1] - A[1]
        l = _m.hypot(dx, dy)
        nx, ny = -dy / l * e, dx / l * e
        poly(pen, [(A[0] + nx, A[1] + ny), (B[0] + nx, B[1] + ny),
                   (B[0] - nx, B[1] - ny), (A[0] - nx, A[1] - ny)], horaire=True)


ICONS = {
    # nom -> (point de code PUA, dessinateur)
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
    for nom, (_, dessin) in ICONS.items():
        pen = TTGlyphPen(None)
        dessin(pen)
        glyphes[nom] = pen.glyph()
    fb.setupGlyf(glyphes)
    fb.setupHorizontalMetrics({n: (ADV, 0) for n in noms})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupNameTable({'familyName': 'Vigie Icons', 'styleName': 'Regular',
                       'fullName': 'Vigie Icons', 'psName': 'VigieIcons-Regular',
                       'copyright': 'Vigie project, MIT'})
    fb.setupPost()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vigie-icons.ttf')
    fb.save(out)
    print('ecrit', out, os.path.getsize(out), 'octets,', len(ICONS), 'glyphes')


if __name__ == '__main__':
    main()
