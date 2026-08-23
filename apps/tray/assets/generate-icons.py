# -*- coding: utf-8 -*-
"""
Genere les icones du tray : ok.ico / warn.ico / error.ico.

    python generate-icons.py <dossier-de-sortie>

POURQUOI CE SCRIPT EST STRUCTURE AINSI
--------------------------------------
La version precedente dessinait UNE SEULE fois a 256 px, puis laissait Pillow reduire
vers chaque taille. Resultat : a 16 px, l'anneau fin et l'arc epais fusionnaient en une
pastille verte illisible. Un detail concu pour 256 px ne survit pas a une reduction en 16.

Ici, chaque taille est dessinee A SA PROPRE RESOLUTION, avec un NIVEAU DE DETAIL adapte :
on retire ce qui devient du bruit avant que ca ne le devienne. C'est du "hinting" d'icone,
la pratique normale quand une meme marque doit tenir de 16 a 256 px.

Chaque taille est tracee en supersampling (x8) puis reduite : les bords sont propres sans
dependre du filtre de reduction de Pillow sur un dessin trop charge.

Geometrie : voir docs/DECISIONS-VALIDEES.md (D01 pour les proportions, D23 pour les
fractions de niveau, D27 pour les graduations sous l'arc, D37 pour les niveaux de detail).
Toute valeur modifiee ici doit l'etre en miroir dans le repli GDI+ de apps/tray/tray.ps1
et dans l'atelier de validation (apps/atelier/index.html).
"""

from PIL import Image, ImageDraw
import math
import os
import sys

# --- Parametres de la marque, en fractions de la taille (D01) -----------------
A0, SPAN = 135.0, 270.0          # depart et amplitude de l'arc
R_ARC = 0.35                     # rayon de l'arc de jauge
R_RING = 0.45                    # rayon de l'anneau exterieur
TRACK = (0x30, 0x36, 0x3d)       # piste (fond d'arc)
TICK = (0x8b, 0x94, 0x9e)        # graduations
WHITE = (0xf0, 0xf6, 0xfc)       # point central

# --- Niveaux de detail (D37) --------------------------------------------------
# En dessous d'un certain nombre de pixels, un element cesse d'etre lisible et devient
# du bruit : il vaut mieux le retirer que le laisser se transformer en tache.
#   min_px : taille minimale de l'icone a partir de laquelle l'element est dessine.
DETAIL = {
    'ring':  48,   # anneau exterieur : trait tres fin, illisible en dessous
    'ticks': 64,   # graduations : sous l'arc plein (D27), pures parasites en petit
    'edge':  32,   # lisere sombre de l'aiguille : moins d'1 px en dessous
}

# Epaisseurs : plus l'icone est petite, plus il faut epaissir pour rester lisible.
def stroke_widths(size):
    if size >= 48:
        return {'arc': 0.110, 'needle': 0.082, 'edge': 0.098, 'hub': 0.095, 'dot': 0.042}
    if size >= 32:
        return {'arc': 0.125, 'needle': 0.095, 'edge': 0.112, 'hub': 0.105, 'dot': 0.046}
    # 16 a 24 px : on assume une marque simplifiee, lisible, plutot qu'une reduction fidele
    return {'arc': 0.150, 'needle': 0.115, 'edge': 0.000, 'hub': 0.125, 'dot': 0.052}


def darken(rgb, f):
    return tuple(int(v * f) for v in rgb)


def draw_mark(size, color, frac, supersample=8):
    """Dessine la marque a `size` pixels, avec le detail adapte a cette taille."""
    M = size * supersample
    img = Image.new('RGBA', (M, M), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = M / 2.0
    r = M * R_ARC
    w = stroke_widths(size)
    R, G, B = color
    val = (R, G, B, 255)

    def pt(radius, deg):
        a = math.radians(deg)
        return (cx + radius * math.cos(a), cy + radius * math.sin(a))

    def arc_round(radius, a0, a1, col, width):
        """Arc a extremites arrondies : Pillow ne sait pas les faire nativement.

        PIEGE : `ImageDraw.arc(..., width=w)` epaissit le trait VERS L'INTERIEUR du
        rectangle englobant. Un rectangle de rayon `radius` donne donc un trait occupant
        [radius - w, radius], d'axe `radius - w/2` -- alors que SVG centre le trait SUR
        le trace, soit [radius - w/2, radius + w/2].

        Consequences de l'ancienne version : l'arc etait decale vers l'interieur d'une
        demi-epaisseur, et les disques de coin, centres sur `radius`, depassaient vers
        l'exterieur en formant des bosses visibles. C'est ce qui faisait diverger les
        .ico de la simulation de l'atelier.

        On elargit donc le rectangle a `radius + w/2` : le trait retombe centre sur
        `radius`, exactement comme en SVG, et les coins se centrent sur `radius`.
        """
        outer = radius + width / 2.0
        d.arc([cx - outer, cy - outer, cx + outer, cy + outer], a0, a1,
              fill=col, width=int(round(width)))
        cr = width / 2.0
        for a in (a0, a1):
            px, py = pt(radius, a)
            d.ellipse([px - cr, py - cr, px + cr, py + cr], fill=col)

    def line_round(p0, p1, col, width):
        d.line([p0[0], p0[1], p1[0], p1[1]], fill=col, width=int(round(width)))
        cr = width / 2.0
        for (px, py) in (p0, p1):
            d.ellipse([px - cr, py - cr, px + cr, py + cr], fill=col)

    # 1) Anneau exterieur — seulement quand il a la place d'exister
    if size >= DETAIL['ring']:
        rr = M * R_RING
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                  outline=(R, G, B, int(0.35 * 255)),
                  width=max(1, int(round(M * 0.024))))

    # 2) Piste, puis graduations, puis arc de valeur par-dessus (D27)
    sw = M * w['arc']
    arc_round(r, A0, A0 + SPAN, TRACK + (255,), sw)

    if size >= DETAIL['ticks']:
        tw = max(1, int(round(M * 0.02)))
        for i in range(7):                       # 7 traits, bornes comprises (D01)
            a = A0 + (i / 6.0) * SPAN
            d.line([pt(r * 0.98, a), pt(r * 0.80, a)],
                   fill=TICK + (int(0.35 * 255),), width=tw)

    ang = A0 + frac * SPAN
    arc_round(r, A0, ang, val, sw)

    # 3) Aiguille — le lisere sombre disparait quand il ferait moins d'un pixel
    heel, tip = pt(-M * 0.06, ang), pt(r * 0.92, ang)
    if size >= DETAIL['edge'] and w['edge'] > 0:
        line_round(heel, tip, darken((R, G, B), 0.72) + (int(0.95 * 255),), M * w['edge'])
    line_round(heel, tip, val, M * w['needle'])

    # 4) Moyeu et point central
    hr = M * w['hub']
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=val)
    wr = M * w['dot']
    d.ellipse([cx - wr, cy - wr, cx + wr, cy + wr], fill=WHITE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def make(color, frac, out_path, sizes=(16, 20, 24, 32, 48, 256)):
    frames = [draw_mark(s, color, frac) for s in sizes]
    largest = frames[-1]
    # append_images : chaque sous-image est celle qu'on a dessinee POUR cette taille,
    # au lieu d'une reduction de la plus grande.
    largest.save(out_path, format='ICO', sizes=[(s, s) for s in sizes],
                 append_images=frames[:-1])


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: python generate-icons.py <dossier-de-sortie>")
        raise SystemExit(2)
    out = sys.argv[1]
    if not os.path.isdir(out):
        print("dossier introuvable : " + out)
        raise SystemExit(1)

    # Fractions du niveau (D23) : conforme = jauge PLEINE.
    make((63, 185, 80), 1.00, os.path.join(out, 'ok.ico'))
    make((210, 153, 34), 0.50, os.path.join(out, 'warn.ico'))
    make((248, 81, 73), 0.14, os.path.join(out, 'error.ico'))
    print('OK', sorted(x for x in os.listdir(out) if x.endswith('.ico')))
