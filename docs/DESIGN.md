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
5. **Un nom technique ne s'affiche jamais seul** (**D64**) : un nom de processus se
   montre sous la forme *description Windows (nom technique)* — « Processus d'exécution
   client-serveur (csrss) » — et sa ligne porte une **infobulle** donnant le **chemin
   absolu**, l'éditeur, la version et les PID. Contrat : `table.tips`, tableau parallèle à
   `table.rows` ; la bulle est posée sur la **ligne** (`<tr title>`), jamais sur chaque
   cellule — deux bulles imbriquées se disputent le survol.
6. **Icônes : notre propre fonte** (`vigie-icons.ttf`, **D58**) — générée par
   `apps/frontend-web/assets/generate-icon-font.py`, embarquée en data-URI, utilisée par
   `<span class="vi">&#xE001;</span>`. Un glyphe manquant se **dessine** dans le
   générateur (une fonction par icône), on n'importe pas de bibliothèque. Le SVG est
   réservé à la **marque** : jauge du tray (`generate-icons.py`) et logo GitHub
   (`#ghMark`, défini une fois).

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
| **Emboîtement** | le cadre (bordure + coins) appartient au bloc **parent**, un seul niveau ; dedans, bande de titre et lignes **pleine largeur**, séparées d'un filet | D88 |
| **Composants** | `UI.bande`, `UI.liste`, `UI.ligne`, `UI.interrupteur`, `UI.etiquette`, `UI.note`, `UI.carte` — une seule écriture de chaque morceau ; un motif qui se répète devient un composant **avant** d'être copié | D88 |

## Où vivent les valeurs

- **Palette et typo du front** : le bloc `:root` de `apps/frontend-web/index.html` —
  l'unique définition (D15). `tokens.php` la sert à l'Atelier.
- **Icônes d'interface** : `apps/frontend-web/assets/generate-icon-font.py` (D58) —
  la table des glyphes (nom → point de code) vit là ; la fonte `.ttf` générée est
  versionnée à côté et montrée sur la page « Design système » de l'Atelier.
- **Marque (jauge)** : `apps/tray/assets/generate-icons.py` (D01, D37) — miroir dans
  la page « Marque du tray » et le repli GDI+ de `tray.ps1`.
- **Menu du tray** : classe `VigieMenuPalette` dans `apps/tray/tray.ps1`, servie par
  `palette.php`.
