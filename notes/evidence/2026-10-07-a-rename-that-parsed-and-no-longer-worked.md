# Un renommage qui parsait, et qui ne marchait plus

Le 07/10, en descendant le cliquet de S07, j'ai renommé quatre fichiers d'un coup. Les quinze vérificateurs sont
passés au vert, le compte est tombé de 450 à 389, et j'ai annoncé la tranche faite. Elle était cassée.

## Ce qui s'est passé

`disk-scan.worker.ps1` déclare une fabrique de nœuds :

```powershell
function New-Noeud { param([string]$Chemin, [string]$Nom, [int]$Prof, $Parent) ... }
$racine = New-Noeud -Chemin $racineChemin -Nom $racineChemin -Prof 0 -Parent $null
```

Mon outil remplaçait `$Chemin` et `${Chemin}` — **les deux écritures d'une variable**. Il ne connaissait pas la
troisième face d'un paramètre : **son site d'appel**, `-Chemin`. Après renommage, la fonction attendait `-NodePath`
et recevait toujours `-Chemin` : PowerShell n'a pas de paramètre de ce nom, le lien se fait sur le positionnel, et
les nœuds sont nés sans chemin.

**Mesuré** : l'arbre d'essai rendait `2 dossiers, 4 fichiers` avant, `1 dossier, 0 fichier` après. Le fichier
parsait parfaitement.

## Pourquoi aucun vérificateur ne l'a vu, et ne pouvait le voir

Les quinze vérificateurs **lisent** le code — ils le parsent, ils comparent des contrats, ils comptent. Aucun
n'exécute un worker : un worker parcourt un disque, écrit dans `var/`, dure des minutes. Un fichier qui parse et
dont les paramètres ne se lient plus franchit donc tous les contrôles sans un mot. C'est le même angle mort que
celui qui a fait naître `check-probes.ps1` le 24/08, un cran plus bas : là, un paramètre passé deux fois ; ici, un
paramètre qui n'existe plus.

Dire que les vérificateurs « auraient attrapé ça » était faux, et je l'ai affirmé avant de mesurer.

## Ce qui est en place depuis

**L'outil renomme par l'arbre, pas par expression régulière**, et il couvre les deux faces d'un nom : la variable
(`$nom`, `${nom}`, `"$nom"`) et le site d'appel du paramètre (`-nom`). Il relève des intervalles dans le fichier et
les applique de la fin vers le début, puis il reparse et vérifie qu'aucun ancien nom ne subsiste **ni en variable
ni en paramètre**.

**Et un renommage est prouvé en l'exécutant.** Avant : on lance le fichier sur une entrée, on garde la sortie.
Après : on le relance sur la même entrée, et les deux sorties doivent être identiques. La comparaison est
**canonique** — clés triées en profondeur, horodatages ôtés — parce que l'ordre des clés d'une table PowerShell
n'est pas stable d'une exécution à l'autre et fait croire à une différence là où il n'y en a aucune.

**La tranche est donc dimensionnée par ce qui peut être exécuté, pas par ce qui peut être édité.**
`show-confirm.ps1` est sorti de la tranche pour cette raison : il ouvre une fenêtre, et on ne compare pas deux
exécutions sans l'afficher.

## Ce que ça a donné

Trois fichiers, prouvés un par un sur la même entrée, sortie identique au canon :

| Fichier | Épreuve | Avant | Après |
|---|---|---|---|
| `disk-scan.worker.ps1` | arbre jetable de 4 dossiers, 4 fichiers, 24 000 octets | `4 dossiers, 4 fichiers` | identique au canon |
| `check-probes.ps1` | `-All`, 19 sondes, 21 modules | 1 manquement, code 1 | identique, code 1 |
| `vigie-fetch.ps1` | `-Source local -Force`, fabrication complète | archive de 236 fichiers, code 0 | sortie identique, code 0 |

Compte des identifiants français : **450 → 404**. Cliquet abaissé à 404.
