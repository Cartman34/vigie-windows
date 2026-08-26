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
    """Piece de puzzle : UN SEUL contour ferme -- corps carre, tenon en haut, encoche a
    gauche. L'ancienne version superposait un carre, un cercle et un rectangle : les
    jonctions se voyaient et l'encoche mordait le bord (signale par l'utilisateur).
    Ici le contour decrit la piece d'un trait, le remplissage ne peut donc pas trahir.
    """
    import math
    r = 115.0
    pts = []
    # Bord bas, de gauche a droite.
    pts += [(170, 170), (830, 170)]
    # Bord droit.
    pts += [(830, 830)]
    # Bord haut : jusqu'au tenon, demi-cercle SORTANT, puis fin du bord.
    pts += [(500 + r, 830)]
    for i in range(1, 20):
        a = math.pi * i / 20.0
        pts.append((500 + r * math.cos(a), 830 + r * math.sin(a)))
    pts += [(500 - r, 830), (170, 830)]
    # Bord gauche : jusqu'a l'encoche, demi-cercle RENTRANT (vers l'interieur), puis bas.
    pts += [(170, 500 + r)]
    for i in range(1, 20):
        a = math.pi / 2 + math.pi * i / 20.0
        pts.append((170 + r * math.cos(a - math.pi), 500 - r * math.sin(a - math.pi)))
    pts += [(170, 500 - r)]
    poly(pen, pts, horaire=True)


def g_flag(pen):
    """Fanion (notifications de l'onglet) : hampe + drapeau."""
    rect(pen, 200, 40, 260, 760, horaire=True)
    poly(pen, [(260, 740), (760, 620), (260, 470)], horaire=True)


def g_bell(pen):
    """Cloche : corps haut et evase, base plate, battant. UN SEUL contour pour le corps.

    L'ancienne version empilait un demi-cercle large et un rectangle : elle paraissait
    ecrasee (signale par l'utilisateur). Ici le corps monte de y=250 a y=790 -- plus haut
    que large -- et s'evase vers le bas, comme une vraie cloche.
    """
    # Corps : cote gauche du bas vers le haut, sommet arrondi, cote droit en miroir.
    gauche = [(300, 250), (300, 430), (318, 560), (360, 665), (425, 735), (500, 760)]
    droite = [(x if x == 500 else 1000 - x, y) for (x, y) in reversed(gauche)]
    poly(pen, gauche + droite, horaire=True)
    # Base : le rebord sur lequel la cloche repose.
    rect_arrondi(pen, 215, 195, 785, 265, 34, horaire=True)
    # Anse au sommet.
    cercle(pen, 500, 800, 52, horaire=True)
    # Battant.
    cercle(pen, 500, 120, 78, horaire=True)


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
    """i cercle, dessine pour rester lisible a 12 px : anneau FIN, i GROS et espace.
    (l'ancienne version - anneau 70, petit i - se fondait en donut a petite taille)."""
    anneau(pen, 500, 400, 385, 52)
    cercle(pen, 500, 585, 82, horaire=True)
    rect_arrondi(pen, 435, 170, 565, 445, 56, horaire=True)


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


def g_users(pen):
    """Utilisateurs : deux silhouettes tete + EPAULES, comme les icones du genre.

    Trois essais avant celui-ci, et ce qu'ils ont appris :
      - silhouettes qui se chevauchent : elles fusionnent en une masse ;
      - lisere vide pour les separer : en remplissage non-zero, il CREUSE la silhouette
        de devant la ou le fond est absent ;
      - buste rond detache de la tete : on lit quatre boules, pas deux personnes.
    Ce qui marche : un buste en DOME (des epaules), qui touche la tete, et un vrai espace
    entre les deux personnes. Verifie au rendu jusqu'a 16 px.
    """
    import math

    def personne(cx, cy_tete, r_tete, demi_largeur, hauteur_epaules, base):
        cercle(pen, cx, cy_tete, r_tete, horaire=True)
        pts = []
        n = 26
        for i in range(n + 1):
            a = math.pi - math.pi * i / n          # de gauche a droite, par le sommet
            pts.append((cx + demi_largeur * math.cos(a), base + hauteur_epaules * math.sin(a)))
        pts.append((cx + demi_largeur, base))
        pts.append((cx - demi_largeur, base))
        poly(pen, pts, horaire=True)

    # Devant : plus grande, a gauche. Les epaules montent jusqu'a 560, la tete descend a
    # 545 : elles se recouvrent, la silhouette est d'un seul tenant.
    personne(cx=350, cy_tete=690, r_tete=148, demi_largeur=205, hauteur_epaules=370, base=190)
    # A cote : plus petite, un peu plus bas, SANS toucher la premiere (espace de 60).
    personne(cx=765, cy_tete=628, r_tete=102, demi_largeur=140, hauteur_epaules=270, base=215)


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
        # 1. Dessin enregistre, 2. boite d'encre mesuree, 3. translation EXACTE pour que
        # le centre d'encre tombe sur (500, 300) -- centre de la chasse (1000) et de la
        # ligne (ascent 800 / descent 200). Un forfait (-100) supposait des dessins tous
        # centres sur (500, 400) : faux pour certains, d'ou des icones de travers.
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
    # LSB = xMin REEL de chaque glyphe : un LSB declare different fait recaler le dessin
    # par le rasterizer (constate : icones glissees a gauche de ~4 px a 17 px).
    def lsb(n):
        g = glyphes[n]
        return getattr(g, 'xMin', 0) or 0
    fb.setupHorizontalMetrics({n: (ADV, lsb(n)) for n in noms})
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
