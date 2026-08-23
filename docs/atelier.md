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
docs\atelier.cmd
```

ou, directement :

```
pwsh -ExecutionPolicy Bypass -File .\docs\atelier.ps1
```

Le navigateur s'ouvre sur `http://127.0.0.1:47610/docs/atelier-validation.html`.
La console affiche les requêtes ; **Ctrl+C** arrête le serveur.

### Toutes les commandes

| Commande | Effet |
|---|---|
| `.\docs\atelier.ps1` | démarre au premier plan et ouvre le navigateur |
| `.\docs\atelier.ps1 -Background` | démarre en tâche de fond et rend la main |
| `.\docs\atelier.ps1 -Status` | indique s'il tourne, sur quel port, avec quel PID |
| `.\docs\atelier.ps1 -Stop` | arrête l'atelier |
| `.\docs\atelier.ps1 -NoBrowser` | démarre sans ouvrir d'onglet |
| `Get-Help .\docs\atelier.ps1 -Full` | aide complète, exemples inclus |

Le script est **idempotent** : relancé alors qu'il tourne déjà, il ouvre simplement le
navigateur au lieu d'échouer.

**Codes de retour** : `0` succès · `1` prérequis manquant (php absent) · `2` échec de
démarrage ou d'arrêt.

---

## Configuration

**Un seul endroit** : [`backend/config.psd1`](../backend/config.psd1).

| Clé | Rôle |
|---|---|
| `BindAddress` | adresse d'écoute — strictement locale |
| `AtelierPort` | port de l'atelier (`47610` par défaut) |

Ces valeurs ne sont **recopiées nulle part ailleurs** : le script les lit via `Get-Config`,
et l'URL en dérive. Changer le port ici suffit.

Pour un réglage propre à ta machine (port déjà pris, par exemple), ne modifie pas
`config.psd1` : crée `backend/config.local.psd1` à partir de
`backend/config.local.sample.psd1`. Il est ignoré par git.

---

## Ce que fait le serveur — et ce qu'il ne fait pas

- Serveur **intégré de PHP** (`php -S`), servant la **racine du dépôt** en lecture seule.
- Écoute **strictement en local**. **Aucun droit administrateur** n'est requis.
- Port **distinct** de celui du serveur applicatif (`47600`) : les deux peuvent tourner
  en même temps sans se gêner.
- Il **ne remplace pas** `backend/start.ps1`. C'est un outil de développement : il ne sert
  aucune API, n'exécute aucune sonde et n'a accès à aucun secret.

### Pourquoi un serveur plutôt qu'un double-clic sur le fichier

Ouverte en `file://`, la page ne peut pas faire son travail :

- les chemins relatifs vers `backend/assets/tray/*.ico` cassent dès que le fichier est
  copié ailleurs — d'où des **images cassées** ;
- le navigateur refuse d'afficher `frontend/index.html` dans un cadre — d'où un
  **rectangle noir** à la place de l'écran de chargement.

Servie en `http`, la page fonctionne entièrement. Elle reste néanmoins ouvrable en
`file://` : dans ce cas elle **le dit** au lieu d'afficher des cassures silencieuses.

---

## Ce que contient la page

### Marque du tray
Reproduction exacte de [`backend/assets/tray/generer-icones.py`](../backend/assets/tray/generer-icones.py),
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
exactes à recopier** dans `VigieMenuPalette` ([`backend/tray.ps1`](../backend/tray.ps1)).

### Écran de chargement
`frontend/index.html` en direct, rechargeable pour revoir le splash.

---

## Règle à respecter

Les géométries de la page sont une **reproduction** du code, pas sa source.
Toute valeur retenue doit être reportée **en miroir** :

1. dans le code (`generer-icones.py`, `tray.ps1`, …) ;
2. dans [`DECISIONS-VALIDEES.md`](DECISIONS-VALIDEES.md).

Sans cela l'atelier devient trompeur — c'est précisément ce qu'il sert à éviter.

---

## En cas de problème

| Symptôme | Cause | Solution |
|---|---|---|
| « php introuvable » | PHP absent du `PATH` | l'installer, ou ouvrir la page en `file://` (fonctions réduites) |
| Bandeau rouge « pas ouverte depuis le dépôt » | page ouverte en `file://` ou copiée ailleurs | passer par `docs\atelier.cmd` |
| Icônes en croix rouge | mêmes causes, ou `.ico` absents | vérifier `backend/assets/tray/` |
| Port déjà utilisé | un atelier tourne déjà | `.\docs\atelier.ps1 -Status`, puis `-Stop` |
| Le serveur ne s'arrête pas | processus détaché | `.\docs\atelier.ps1 -Stop` (retrouve le PID par le port) |
| Les icônes ne changent pas | générateur non rejoué | régénérer les `.ico`, puis recharger la page |
