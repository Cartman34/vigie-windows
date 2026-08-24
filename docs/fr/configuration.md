# Configuration

[Sommaire](README.md) · [English](../en/configuration.md)

Vigie est livrée avec une configuration **générique et versionnée**, valable sur n'importe
quelle machine, et prend ce qui est propre à un poste dans un **fichier local ignoré par
git**. On ne modifie jamais le fichier versionné pour adapter Vigie à son PC.

Chaque valeur n'est définie qu'à un seul endroit ; tout le reste en dérive.

---

## Les trois couches

Chaque app fusionne, dans cet ordre — la plus spécifique gagne :

| Fichier | Portée | Versionné |
|---|---|---|
| `config/common.psd1` | partagé par tous les serveurs locaux du dépôt | oui |
| `apps/backend-pode/config/config.psd1` | les réglages propres à Vigie | oui |
| `apps/backend-pode/config/config.local.psd1` | **votre machine** | **non** (`.gitignore`) |

### `config/common.psd1`

| Clé | Valeur | Signification |
|---|---|---|
| `BindAddress` | `127.0.0.1` | adresse d'écoute de **tous** les serveurs du dépôt. Strictement locale : rien ici n'est destiné à être exposé. |
| `PortRangeStart` / `PortRangeEnd` | `47600` / `47699` | la plage de ports réservée au projet. Chaque app y choisit le sien. |

### `apps/backend-pode/config/config.psd1`

| Clé | Défaut | Signification |
|---|---|---|
| `Port` | `47600` | le port d'écoute de Vigie |
| `ApiBase` | `/api/v1` | préfixe des routes REST |
| `ToolsPath` | *(vide)* | dossier d'outillage externe, optionnel — voir plus bas |

L'URL du tableau de bord et celle de l'API en **dérivent** (`Get-AppUrl`, `Get-ApiUrl`) :
elles ne sont réécrites nulle part ailleurs dans le code.

---

## Vos surcharges locales

```powershell
Copy-Item apps/backend-pode/config/config.local.sample.psd1 apps/backend-pode/config/config.local.psd1
```

N'y mettez **que** ce qui ne peut pas être générique. Toute clé présente écrase
`config.psd1` ; toute clé absente garde la valeur par défaut. **N'y mettez jamais de
secret** : le jeton d'API vit à part, dans `apps/backend-pode/var/secrets/`.

```powershell
@{
    ToolsPath = 'C:\chemin\vers\LocalAgentAdmin\tools'
    # Port = 47601   # seulement si 47600 est déjà pris sur cette machine
}
```

Redémarrez le serveur après modification (menu du tray → *Redémarrer le serveur*).

---

## Outillage externe

`ToolsPath` désigne un dossier de **scripts d'administration qui ne sont pas livrés avec ce
dépôt**. Son dossier parent devient la racine d'administration.

| Action | Script appelé |
|---|---|
| *Mode MAJ (déverrouiller)* / *Verrouiller maintenant* | `<ToolsPath>\update-mode.ps1` |
| *Lancer l'audit* | `<ToolsPath>\audit-update-tasks.ps1` |
| *Basculer VBS* | `<parent>\toggle-vbs.ps1` |
| *Basculer intégrité mémoire* | `<parent>\toggle-hvci.ps1` |
| *Ouvrir le dossier* | ouvre la racine d'administration dans l'explorateur |

Laissez `ToolsPath` vide et ces boutons rendent un message clair — *« outillage externe non
configuré »* — au lieu d'échouer obscurément. **Tout le reste fonctionne sans lui** :
chaque sonde lit le système nativement, y compris l'état du verrou Windows Update.

Cette dépendance externe est une limite connue de la v0.1.

---

## Où Vigie écrit

Chaque app garde ses fichiers sous son propre `var/`. Rien de tout cela n'est versionné.

| Chemin | Contenu |
|---|---|
| `apps/backend-pode/var/secrets/api.token` | le jeton d'API, généré au premier lancement |
| `apps/backend-pode/var/cache/` | état agrégé et résultats des tâches de fond |
| `apps/backend-pode/var/log/` | `install_*`, `run_*`, `start_*`, journaux d'erreur et de requêtes Pode |
| `apps/tray/var/log/` | journaux `tray_*` |
| `apps/tray/var/run/` | battement de cœur et fichiers d'ordre du tray |

## Le numéro de version

La version du produit vit dans le fichier **`VERSION`** à la racine du dépôt, et nulle part
ailleurs. Il ne porte que le numéro nu (`0.1`) ; le préfixe `v` est ajouté une fois, à
l'affichage. Il ne change que sur décision explicite, pas au fil des commits.

## Ensuite

- [Dépannage](depannage.md) — lire ces journaux
- [Développement](developpement/README.md) — le raisonnement derrière cette organisation
