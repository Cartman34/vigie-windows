# Atelier de validation

Outil interne pour **juger et régler à l'œil** ce qu'aucun analyseur syntaxique ne peut
valider : la marque du tray, les icônes réellement livrées, le style du menu, l'écran de
chargement.

> **Pourquoi il existe.** L'agent qui développe ne voit pas l'écran. Sans cette page,
> chaque réglage visuel coûte un aller-retour « je code à l'aveugle, tu corriges après
> coup ». L'atelier rend la décision immédiate, et surtout **reproductible**.

---

## Démarrer

```
apps\atelier\atelier.cmd
```

ou, directement :

```
pwsh -ExecutionPolicy Bypass -File .\apps\atelier\atelier.ps1
```

Le navigateur s'ouvre sur `http://127.0.0.1:47610/apps/atelier/index.html`.
La console affiche les requêtes ; **Ctrl+C** arrête le serveur.

### Toutes les commandes

| Commande | Effet |
|---|---|
| `.\apps\atelier\atelier.ps1` | démarre au premier plan et ouvre le navigateur |
| `.\apps\atelier\atelier.ps1 -Background` | démarre en tâche de fond et rend la main |
| `.\apps\atelier\atelier.ps1 -Status` | indique s'il tourne, sur quel port, avec quel PID |
| `.\apps\atelier\atelier.ps1 -Stop` | arrête l'atelier |
| `.\apps\atelier\atelier.ps1 -NoBrowser` | démarre sans ouvrir d'onglet |
| `Get-Help .\apps\atelier\atelier.ps1 -Full` | aide complète, exemples inclus |

Le script est **idempotent** : relancé alors qu'il tourne déjà, il ouvre simplement le
navigateur au lieu d'échouer.

**Codes de retour** : `0` succès · `1` prérequis manquant (php absent) · `2` échec de
démarrage ou d'arrêt.

---

## Configuration

**Sa propre config** : [`apps/atelier/config/config.psd1`](config/config.psd1).

| Clé | Rôle |
|---|---|
| `BindAddress` | adresse d'écoute — strictement locale |
| `Port` | port de l'Atelier (`47610` par défaut) |
| `StartPage` | page ouverte au démarrage, relative à la racine servie |

L'Atelier **ne lit pas la config du backend** : c'est une app distincte, elle est
maîtresse de ses propres valeurs. **D15** dit « une valeur, une définition » — pas
« un fichier pour toutes les valeurs ».

Le port de Vigie (`47600`) vit, lui, dans `apps/backend-pode/config/config.psd1`. Les deux sont dans
la même plage locale mais **distincts**, pour que les deux apps tournent en même temps.

---

## « Atelier » n'est pas « Vigie »

Deux briques distinctes, à ne jamais confondre (**D28**) :

|  | **Vigie** | **Atelier** |
|---|---|---|
| Nature | l'**application** livrée | cet **outil de développement** |
| Serveur | PowerShell + Pode | PHP (`php -S`) |
| Port | 47600 | **47610** |
| Élévation | oui (`RunLevel Highest`) | **non**, jamais |
| Lancement | tâche planifiée, à l'ouverture de session | à la main |
| Sondes, actions, secrets | oui | **aucun accès** |

PHP est **volontairement cantonné à l'outillage** : il n'entre pas dans l'application.
Les raisons (élévation, concurrence, coût des processus) sont chiffrées dans **D28**.

## Ce que fait le serveur — et ce qu'il ne fait pas

- Serveur **intégré de PHP** (`php -S`), servant la **racine du dépôt** en lecture seule.
- Écoute **strictement en local**. **Aucun droit administrateur** n'est requis.
- Port **distinct** de celui du serveur applicatif (`47600`) : les deux peuvent tourner
  en même temps sans se gêner.
- Il **ne remplace pas** `apps/backend-pode/start.ps1`. C'est un outil de développement : il ne sert
  aucune API, n'exécute aucune sonde et n'a accès à aucun secret.

### Pourquoi un serveur plutôt qu'un double-clic sur le fichier

Ouverte en `file://`, la page ne peut pas faire son travail :

- les chemins relatifs vers `apps/tray/assets/*.ico` cassent dès que le fichier est
  copié ailleurs — d'où des **images cassées** ;
- le navigateur refuse d'afficher `apps/frontend-web/index.html` dans un cadre — d'où un
  **rectangle noir** à la place de l'écran de chargement.

Servie en `http`, la page fonctionne entièrement. Elle reste néanmoins ouvrable en
`file://` : dans ce cas elle **le dit** au lieu d'afficher des cassures silencieuses.

---

## Ce que contient la page

### Marque du tray
Reproduction exacte de [`apps/tray/assets/generate-icons.py`](../tray/assets/generate-icons.py),
avec un curseur de **fraction**, le choix de l'état, et un rendu de 16 à 128 px — dont
une bande imitant la barre des tâches pour juger le contraste réel.

### Icônes réellement livrées
Les `.ico` du dépôt, à côté de la simulation. S'ils diffèrent, **le générateur n'a pas été
rejoué**.

> Réserve honnête : un navigateur choisit une seule sous-image du `.ico` et la
> redimensionne. Le rendu à 16 px ici n'est donc pas exactement celui de Windows, qui pioche
> la vraie sous-image 16×16.

### Menu du tray
Reproduction réglable de ce que dessine `VigieMenuRenderer` : arrondi du menu, arrondi et
marge du survol, hauteur d'item, palette complète. Un bloc de code affiche **les valeurs
exactes à recopier** dans `VigieMenuPalette` ([`apps/tray/tray.ps1`](../tray/tray.ps1)).

### Écran de chargement
`apps/frontend-web/index.html` en direct, rechargeable pour revoir le splash.

---

## Règle à respecter

Les géométries de la page sont une **reproduction** du code, pas sa source.
Toute valeur retenue doit être reportée **en miroir** :

1. dans le code (`generate-icons.py`, `tray.ps1`, …) ;
2. dans [`docs/progress/decisions.md`](../../docs/progress/decisions.md).

Sans cela l'atelier devient trompeur — c'est précisément ce qu'il sert à éviter.

---

## En cas de problème

| Symptôme | Cause | Solution |
|---|---|---|
| « php introuvable » | PHP absent du `PATH` | l'installer, ou ouvrir la page en `file://` (fonctions réduites) |
| Bandeau rouge « pas ouverte depuis le dépôt » | page ouverte en `file://` ou copiée ailleurs | passer par `apps\atelier\atelier.cmd` |
| Icônes en croix rouge | mêmes causes, ou `.ico` absents | vérifier `apps/tray/assets/` |
| Port déjà utilisé | un atelier tourne déjà | `.\apps\atelier\atelier.ps1 -Status`, puis `-Stop` |
| Le serveur ne s'arrête pas | processus détaché | `.\apps\atelier\atelier.ps1 -Stop` (retrouve le PID par le port) |
| Les icônes ne changent pas | générateur non rejoué | régénérer les `.ico`, puis recharger la page |
