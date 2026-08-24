# Développement

[Sommaire](../README.md) · [English](../../en/development/README.md)

Cette section s'adresse à qui lit ou modifie le code. Pour simplement *utiliser* Vigie,
tout est dans la [documentation utilisateur](../README.md#pour-lutilisateur).

---

## Arborescence du dépôt

```
README.md / README.fr.md   Points d'entrée (EN / FR)
VERSION                    Le numéro de version du produit, et nulle part ailleurs
config/common.psd1         Réglages partagés par tous les serveurs locaux du dépôt
apps/
  backend-pode/            Le serveur applicatif (PowerShell + Pode)
    api/openapi.yaml         LE CONTRAT REST — source de vérité
    lib/common.ps1           Helpers partagés : état, cache, config, élévation, tâches
    probes/<theme>/*.probe.ps1     Lecture d'état, une carte chacune
    actions/<id>.action.ps1        Effets de bord, un bouton chacun
    workers/*.worker.ps1           Tâches longues, détachées
    config/                        config.psd1 + config.local.sample.psd1
  frontend-web/index.html  Tout le front : un fichier HTML statique
    mock/state.json          État d'exemple, servi quand l'API est injoignable
  tray/tray.ps1            L'app de la barre système (WinForms) + assets/
  atelier/                 Outil interne de validation visuelle (PHP) — hors produit
scripts/                   install, run, démarrage auto, désinstallation, pilote du tray, hooks git
docs/                      Cette documentation + les documents de travail internes
```

## Lancer depuis les sources

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install.ps1   # prérequis, une fois
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1       # démarre (s'élève via UAC)
```

Le front seul, sans serveur, se replie sur `apps/frontend-web/mock/state.json` — mais
**servez-le en HTTP**, jamais en `file://` : les chemins relatifs des ressources cassent et
le navigateur refuse d'afficher la page dans un cadre.

## Deux choses à ne jamais confondre

| | **Vigie** | **Atelier** |
|---|---|---|
| Nature | le **produit** | un **outil de développement** interne |
| À quoi ça sert | surveiller et piloter le PC | juger à l'œil ce qu'aucun parseur ne valide |
| Serveur | PowerShell + Pode | PHP (`php -S`) |
| Port | **47600** | **47610** |
| Élévation | **oui** (`RunLevel Highest`) | **jamais** |
| Lancé par | la tâche planifiée `Vigie`, à l'ouverture de session | à la main |
| Accès aux sondes, actions, secrets | oui | **aucun** |

**Pourquoi PowerShell reste le serveur de l'application, et pas PHP :**

1. **L'élévation.** Le verrou Windows Update pose des ACL, désactive des tâches planifiées
   et écrit dans `HKLM`. Ce qui sert l'API doit donc être élevé — et un serveur HTTP
   tournant en administrateur est une surface d'attaque bien plus large qu'un processus
   PowerShell dédié.
2. **La concurrence.** `php -S` traite **une requête à la fois** (mesuré : 2 s seule, 4,0 s
   à deux). L'interface rafraîchit carte par carte et interroge en boucle : une sonde lente
   bloquerait tout le reste.
3. **Le coût des processus.** Un `pwsh` froid coûte **~350 ms** avant de travailler. À 12
   sondes, un appel par sonde ferait **~4,2 s** de pur démarrage à chaque rafraîchissement
   complet. Tout vit dans un runtime déjà chaud : `/health` répond en **65 ms**.

PHP est volontairement cantonné à l'outillage. Voir
[`apps/atelier/README.md`](../../../apps/atelier/README.md).

## Conventions

- **On parle français, le code est en anglais.** Identifiants, noms de fichiers et symboles
  en anglais ; les documents internes et les décisions en français.
- **Pas de duplication.** Une valeur n'est définie qu'à un endroit, tout en dérive. Un sujet
  n'est documenté qu'à un endroit, tout y renvoie.
- **Toujours traiter erreurs, sortie et code retour** — via `Invoke-Native`, partagé.
- **Scripts idempotents.** Relancer un script doit être sans conséquence.
- **PowerShell 7 et UTF-8 avec accents**, sauf les lanceurs (`.cmd`, `.vbs`), qui restent
  **ASCII pur**.
- **Vérifier les prérequis en amont**, et **valider avant de dire « prêt »** — ne jamais
  rapporter une validation qu'on n'a pas faite.
- **Constater le résultat, ne pas croire le code de retour.** Après un changement, relire le
  système et rapporter ce qu'on a réellement obtenu.

Le détail : [`docs/conventions.md`](../../conventions.md) et
[`docs/technologies.md`](../../technologies.md).

## Comment valider un changement

| Quoi | Comment |
|---|---|
| PowerShell | `[System.Management.Automation.Language.Parser]::ParseFile(...)` sur chaque `.ps1` / `.psd1` modifié, et on rapporte la sortie réelle |
| JavaScript du front | charger la page **en HTTP** dans un navigateur et lire la console. Une erreur de syntaxe empêche l'exécution de tout le bloc `<script>` : vérifier qu'une constante définie en fin de fichier existe prouve que le fichier parse |
| Lanceurs | `.cmd` et `.vbs` doivent rester ASCII, octet par octet |
| Tout ce qui est visuel | l'Atelier — voir [`apps/atelier/README.md`](../../../apps/atelier/README.md) |

## À ne jamais committer

`apps/backend-pode/var/secrets/` (le jeton d'API), `apps/backend-pode/var/cache/`,
`apps/*/var/log/`, `*.bak-*`. Le `.gitignore` les couvre ; vérifiez `git status` malgré tout.

## Pour aller plus loin

- [Architecture](architecture.md) — contract-first, les quatre apps, le chemin d'une requête
- [Sondes et actions](sondes-et-actions.md) — ajouter une carte ou un bouton
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — le contrat lui-même

## Les documents de travail internes

Mémoire du projet, pas documentation d'usage — à lire avant de proposer un changement qui
reviendrait sur une décision déjà tranchée.

- [`docs/DECISIONS-VALIDEES.md`](../../DECISIONS-VALIDEES.md) — chaque décision tranchée, numérotée `D01`…, avec le raisonnement et les pistes écartées
- [`docs/REPRISE.md`](../../REPRISE.md) — où en est le projet, et le backlog
- [`SUIVI.md`](../../../SUIVI.md), [`CHANGELOG.md`](../../../CHANGELOG.md)
- [`docs/targeting/features.md`](../../targeting/features.md) — les fonctionnalités cibles par ID · [`docs/implemented/status.md`](../../implemented/status.md) — ce qui est réellement fait, avec les mêmes ID
- [`docs/operating/SECURITY.md`](../../operating/SECURITY.md) — la revue de sécurité interne
