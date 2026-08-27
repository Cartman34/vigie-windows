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
| `ToolsPath` | *(vide)* | dossier d'outillage externe, facultatif — ne conditionne plus Windows Update, voir plus bas |

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

`ToolsPath` est **facultatif**. **Aucune fonction de Vigie n'en dépend plus.**

**Tout est natif** — le verrouillage de Windows Update (*Mode MAJ*, *Verrouiller
maintenant*), son *audit*, et les bascules *VBS* et *intégrité mémoire* sont implémentés
dans ce dépôt (`lib/common.ps1` : `Set-UpdateLock`, `Invoke-UpdateAudit`,
`Set-DeviceGuardFeature`). Ils exigent seulement que le serveur tourne **en
administrateur**, et le disent clairement si ce n'est pas le cas.

Si `ToolsPath` est renseigné **et** contient `update-mode.ps1`, Vigie préfère ce script pour
le verrou : les installations historiques gardent leur comportement, sans que son absence
bloque quoi que ce soit.

**Le seul usage restant** est *Ouvrir le dossier*, qui ouvre la racine d'administration
(`<parent>` de `ToolsPath`) dans l'explorateur. C'est légitime : ce bouton n'a de sens que
s'il existe un dossier à ouvrir. Sans chemin configuré — ou s'il pointe dans le vide — la
carte **ne propose pas le bouton du tout**, plutôt que d'afficher un bouton mort.

**Tout le reste fonctionne sans lui** : chaque sonde lit le système nativement.

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

- [Dépannage](troubleshooting.md) — lire ces journaux
- [Développement](../en/developing/README.md) — le raisonnement derrière cette organisation
