# Design système de Vigie — la règle écrite

La maquette vivante est dans l'Atelier : **`apps/atelier/design-systeme.html`**
(`http://127.0.0.1:47610/apps/atelier/design-systeme.html`). Sa palette est **lue en
direct** dans le front par `tokens.php` ; ses exemples de composants sont des
reproductions à maintenir **en miroir** — c'est une discipline du projet : *toute
évolution visuelle du front se répercute sur cette page dans la même livraison*.

## Direction artistique

1. **Sobriété sombre d'abord.** Fond profond (`--bg`), panneaux à peine plus clairs
   (`--panel`, `--panel-2`), bordures discrètes. La couleur est réservée au **sens**
   (statut, sévérité) — jamais décorative. Un thème clair existe ; d'autres pourront
   s'ajouter (cartes-radio de l'onglet Apparence).
2. **Le statut se lit sans lire.** Une seule échelle partout : `ok` vert, `warn` orange,
   `error` rouge, `neutral` sans couleur. Deux liserés distincts (**D46**) : `.modebar`
   sous l'en-tête = statut de l'**application** ; liseré **gauche** d'une carte = statut
   du **module**. « En cours » s'exprime dans le même liseré, jamais ailleurs.
3. **Une action annonce sa sévérité** (**D50**) : `fix` vert (corrige), `info` bleu
   (informe), `danger` rouge (touche la machine). Bouton de résolution : coloré en
   permanence. Action principale : **neutre au repos, sa couleur au survol**. L'icône
   porte toujours la couleur.
4. **Le texte explique, l'infobulle décrit** (**D49**) : valeur courte dans la carte ;
   `help` en infobulle du (i) ; `guide` en dépliant (court) ou fenêtre (long). Tout champ
   `warn`/`error` propose une **résolution ou un guide**.
5. **Icônes à partir d'une police**, habillées en CSS si besoin (le (i) est un `i` de
   police dans un cercle CSS). Le SVG est réservé à la **marque** : jauge du tray
   (générée par `generate-icons.py`) et logo GitHub (`#ghMark`, défini une fois).

## Composants et règles

| Composant | Règle | Décision |
|---|---|---|
| Carte | en-tête (groupe, nom, badge de statut, ↻, ⋮), champs, barre d'actions | D49 |
| Badge de carte | même statut que le liseré du module, icône en police (✓ ! ✕) | D46/D49 |
| Champ | pastille de statut, libellé, (i), valeur colorée à droite | D49 |
| Opération en cours | dire **quoi, sur combien, depuis quand** ; « … » réservé à ce cas | D50 |
| Résultat d'opération | reste visible après coup (guide : « 1 paquet, réussie ») | D43 |
| Action critique | **deux confirmations** : centre/orange puis haut/rouge, libellés différents ; réversible si possible (délai annulable) | D50 |
| Tiroirs | croix de fermeture toujours au bord droit ; Paramètres = tiroir large à navigation latérale | D56 |
| Paramètres | un seul menu ⚙ (Notifications, Modules, Apparence, À propos) ; aucun bouton épars ajouté à l'en-tête | D56 |
| Footer | fixe, toujours visible : version, thème rapide, GitHub | — |

## Où vivent les valeurs

- **Palette et typo du front** : le bloc `:root` de `apps/frontend-web/index.html` —
  l'unique définition (D15). `tokens.php` la sert à l'Atelier.
- **Marque (jauge)** : `apps/tray/assets/generate-icons.py` (D01, D37) — miroir dans
  la page « Marque du tray » et le repli GDI+ de `tray.ps1`.
- **Menu du tray** : classe `VigieMenuPalette` dans `apps/tray/tray.ps1`, servie par
  `palette.php`.
