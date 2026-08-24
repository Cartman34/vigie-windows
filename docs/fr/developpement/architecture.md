# Architecture

[Développement](README.md) · [Sommaire](../README.md) · [English](../../en/development/architecture.md)

---

## Cinq principes

1. **Contract-first.** `apps/backend-pode/api/openapi.yaml` est la source de vérité. Le
   front ne connaît que le contrat ; le back n'en est qu'une implémentation
   (Pode/PowerShell aujourd'hui, remplaçable sans toucher au front).
2. **Générique et extensible.** Aucun module n'est codé en dur. Le back **découvre** les
   sondes (lecture d'état) et les actions (effets de bord), regroupées par thème. Ajouter
   une carte = déposer un fichier — sans modifier le contrat, sans modifier le front.
3. **Front statique.** HTML/CSS/JS pur, aucun rendu serveur, `fetch()` et rien d'autre. Un
   seul fichier.
4. **Jamais bloquant.** Tout ce qui est lent — mise à jour de paquets, mesure réseau,
   analyse en ligne des MAJ, WSL — part en tâche de fond détachée. L'interface reste
   réactive et chaque carte s'actualise seule.
5. **Sécurité.** API strictement locale, jeton Bearer, anti-CSRF, liste blanche d'actions.
   Jamais une porte dérobée. Voir [Sécurité](../securite.md).

## Quatre apps, un dépôt

| App | Techno | Rôle |
|---|---|---|
| `apps/backend-pode` | PowerShell 7 + Pode | sert le front **et** pilote Windows en natif — registre, tâches, ACL, services — sans couche intermédiaire |
| `apps/frontend-web` | un fichier HTML statique | le tableau de bord |
| `apps/tray` | PowerShell + WinForms | une **app à part entière** qui *pilote* le back (le démarre, l'arrête, sonde sa santé) sans en faire partie |
| `apps/atelier` | PHP | outil interne de validation visuelle, jamais dans le produit |

Chaque app a son `config/` et son `var/`. `config/common.psd1` à la racine ne porte que ce
qui est réellement partagé.

## Le contrat REST

Base `http://127.0.0.1:47600/api/v1`.

| Route | Rôle |
|---|---|
| `GET /health` | le service répond-il — la seule route sans jeton |
| `GET /state` | instantané complet : tous les modules, tous les thèmes |
| `GET /modules/{id}` | un module, pour l'interrogation carte par carte |
| `POST /actions` | déclenche une action : `{ type, module, params }` |

Un `Module` porte `id`, `theme`, `label`, `status` (`ok` / `warn` / `error` / `neutral`),
`fields[]` et `actions[]`. C'est tout ce que le front sait d'une carte — et c'est
exactement pourquoi une nouvelle sonde n'exige aucun changement côté front.

## Le chemin d'une requête

```
navigateur ──GET /state──> Pode ──> Get-State ──> cache par sonde ──> *.probe.ps1
           <──JSON────────                                        (les périmées seulement)

navigateur ──POST /actions──> liste blanche ──> <id>.action.ps1 ──┬─> résultat immédiat
                                                                 └─> Start-DetachedAction ──> worker
```

## Agrégation et cache d'état

`Get-State`, dans `lib/common.ps1`, agrège toutes les sondes et met le résultat en cache
dans `var/cache/state-cache.json`.

- **Invalidation par sonde**, sur le mtime du fichier de sonde plus un **TTL propre** : 5 s
  pour les gestionnaires de paquets, 120 s pour le pare-feu, 300 s pour l'antivirus et VBS,
  600 s pour le verrou de mise à jour, 900 s pour les MAJ détectées, 3600 s pour la carte
  Windows. 30 s par défaut.
- **Single-flight**, gardé par un mutex inter-processus : des lecteurs simultanés ne
  déclenchent pas chacun le même recalcul.
- **Serve-stale** : un lecteur qui arrive pendant un rafraîchissement reçoit l'état complet
  précédent, jamais un état à moitié construit. Forcer signifie « recalcule », pas « oublie
  tout » : le cache est toujours chargé d'abord, donc aucune carte ne s'évanouit le temps
  du recalcul.
- Toutes les dates sont ramenées en UTC à un seul endroit. Comparer des dates de `Kind`
  différents est ce qui rendait autrefois le cache silencieusement inopérant.

Une action peut renvoyer `result.invalidate = @('lock.probe.ps1')` pour forcer le recalcul
de sondes précises : la carte reflète alors le changement tout de suite, et non au prochain
TTL.

## Tâches de fond

`Start-DetachedAction` lance un worker dans un `pwsh` détaché, fenêtre cachée — aucune
console visible, pas de restauration d'onglets Terminal. Les paramètres voyagent en JSON
base64, robuste au quoting, et le `pwsh` utilisé est celui du processus courant : aucun
chemin d'installation codé en dur.

Une action longue répond immédiatement avec `result.async = $true` et le `module` à
surveiller. Le front met la carte en « en cours » et l'interroge jusqu'à la fin. Fermer le
navigateur n'interrompt rien.

Les workers écrivent leur progression dans `var/cache/*.json` via `Update-StateJson`, gardé
par un mutex inter-processus ; la sonde correspondante ne fait que **lire** ce fichier.
C'est ce qui garde les sondes rapides et sans effet de bord.

## Le tray, et pourquoi il est à part

Le tray tourne élevé. Depuis une session normale on ne peut ni lire sa ligne de commande,
ni signaler un objet noyau qu'il a créé : il fallait le tuer à l'aveugle, ce qui laissait
une icône fantôme dans la zone de notification.

Il communique donc par fichiers : `scripts/tray.ps1` dépose un **ordre** dans
`apps/tray/var/run/`, le tray le lit et sort proprement, en libérant son icône. Le même
dossier porte un battement de cœur (`tray.alive`, réécrit toutes les 8 s) qui permet de
connaître son état sans inspecter le processus. Inspectable à l'œil, scriptable depuis
n'importe quoi, et ouvert aux évolutions : un nouvel ordre est un nouveau nom de fichier,
sans toucher au mécanisme.

## Version et rechargement

`VERSION`, à la racine, porte la version du produit et rien d'autre ne la porte. À côté, un
**jeton de changement** (build id) : le front compare le sien toutes les 15 secondes et
recharge la page quand une nouvelle version est servie. Deux valeurs distinctes, deux
rôles distincts — la version est pour les humains, le jeton n'est jamais affiché.

## Ensuite

- [Sondes et actions](sondes-et-actions.md) — les points d'extension, en pratique
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml)
