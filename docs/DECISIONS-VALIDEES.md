# Décisions validées — à ne JAMAIS perdre

> Règle : toute décision validée par l'utilisateur est consignée ici **et** son
> support (maquette HTML, paramètres exacts) est copié dans `docs/maquettes-validees/`.
> Ces fichiers vivent dans le dépôt, sur la machine — jamais uniquement dans une
> discussion ou un environnement éphémère.

## Icône du tray (jauge)
- **Base validée** : maquette `docs/maquettes-validees/icone-tray_needle-liseres2.html`, option **« B — Teinte 0,72 »**.
- Caractéristiques de l'option B (fractions de la taille `s`) :
  - anneau : rayon `0.45`, trait `0.024`, couleur du statut à opacité `0.35` ;
  - piste (fond d'arc) : couleur `#30363d`, largeur `sw = 0.11`, extrémités rondes, de `135°` sur `270°` ;
  - arc de valeur : couleur du statut, largeur `0.11`, de `135°` sur `frac*270°` ;
  - **graduations** : 6 traits radiaux de `r*0.98` à `r*0.80`, `#8b949e` opacité `0.35`, largeur `0.02` ;
  - aiguille : du **talon** `pt(-0.06, ang)` à la pointe `pt(r*0.92, ang)` ;
    - liseré : teinte foncée `darken(couleur, 0.72)` opacité `0.95`, largeur `0.098` ;
    - aiguille : couleur du statut, largeur `0.082` ;
  - moyeu : couleur du statut, rayon `0.095` ; point central blanc `#f0f6fc` rayon `0.042` ;
  - fractions du niveau : conforme `0.88`, à surveiller/démarrage `0.50`, erreur `0.14` ;
  - couleurs : ok `#3fb950`, warn `#d29922`, err `#f85149`.
- **Statut reflété** : celui de l'APP (via /health) — 3 états seulement : marche (vert) / démarrage (orange) / erreur ou arrêt (rouge). Jamais l'état des composants.

## Reproduction en .ico (déployée)
- Générée à l'identique de l'option B par `backend/assets/tray/generer-icones_B.py` (PIL) → `ok.ico` / `warn.ico` / `error.ico` (multi-résolutions 16→256).
- Chargées par `tray.ps1` (fonction `setIcon`), avec repli sur le dessin GDI+ si un fichier manque.
- **CONFIRMÉ par l'utilisateur (aperçu B)** : on garde graduations + talon d'aiguille, fidèle à la maquette.

## Nom du projet (validé)
- **Dépôt GitHub** : « Vigie Windows » (slug `vigie-windows`).
- **Interface** : nom court **« Vigie »**, affiché **à la place de « Control Panel »** (discret, pas en gros). Le titre principal de la barre reste le **nom de la machine** (dynamique).
- Nom de code interne historique : « HYPERION » (peut rester dans le code/commentaires).
- À faire (noté) : écran de chargement soigné avec « Vigie » en gros ; lien GitHub retrouvable dans l'app.
