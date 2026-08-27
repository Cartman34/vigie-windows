# Configuration

[Sommaire](../README.md) · [English](../../en/operating/configuration.md)

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
secret** : le jeton d'API vit à part, dans `var/secrets/` (voir *Où Vigie écrit*, plus bas).

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

**Le dossier dépend de l'installation**, et c'est voulu :

- **Vigie installée** (`C:\Program Files\Sowapps\Vigie`) écrit dans **votre profil**, sous
  `%LOCALAPPDATA%\Sowapps\Vigie\var\`. Chaque compte a donc les siens : son jeton, son cache, ses journaux.
  Rien n'est écrit à côté du programme, même si le serveur élevé en aurait le droit — sans quoi tous les comptes
  partageraient un seul jeu de réglages.
- **Vigie lancée depuis un clone git** écrit sur place, sous le `var/` de chaque app.

Les chemins ci-dessous sont donnés relativement à cette racine. Rien de tout cela n'est versionné.

| Chemin | Contenu |
|---|---|
| `var/secrets/api.token` | le jeton d'API, généré au premier lancement |
| `var/cache/` | état agrégé et résultats des tâches de fond |
| `var/run/` | marqueurs des tâches en cours, battement de cœur et ordres du tray |
| `var/log/` | `install_*`, `run_*`, `start_*`, `tray_*`, journaux d'erreur et de requêtes Pode |

## Le numéro de version

Il n'y en a **qu'un**, et il ne se tient pas à la main : une Vigie installée porte la marque gravée dans son archive
au moment de la fabrication, un clone git répond par son **dernier tag**. Les tags sont posés au moment d'un
déploiement, jamais à chaque commit : le numéro répond alors exactement à la question « qu'est-ce qui tourne sur
cette machine ? ». Le commit s'affiche à côté, parce que deux fabrications d'un même tag peuvent différer.

## Ensuite

- [Dépannage](../using/troubleshooting.md) — lire ces journaux
- [Développement](../../en/developing/README.md) — le raisonnement derrière cette organisation
