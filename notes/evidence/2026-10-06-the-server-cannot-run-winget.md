# L'app serveur ne peut pas exécuter winget — mesuré par elle-même

Mesure demandée par le plan de l'étape 2 de **S02** : avant de confier à l'app serveur les mises à jour des paquets
installés pour tout l'ordinateur, vérifier qu'elle atteint winget. **Elle ne peut pas.**

## Comment la mesure a été faite

Une action temporaire, `diag-winget-path`, en lecture seule, exécutée **par l'app serveur elle-même** — c'est le
seul moyen de savoir ce que voit le compte de service, qu'une session ordinaire ne peut pas endosser. Elle a été
retirée aussitôt après.

Trois questions, et non une, pour que l'obstacle soit nommé exactement.

## Ce qu'elle répond

```
compte : Hyperion\VigieService
winget dans le PATH : non
dossiers DesktopAppInstaller : 6
  Microsoft.DesktopAppInstaller_1.29.380.0_x64__8wekyb3d8bbwe -> winget.exe present

porte/choco      : ok=True code=0
porte/winget     : LEVE — StandardOutputEncoding is only supported when standard output is redirected
redirige/winget  : LEVE — An error occurred trying to start process '...\winget.exe'. Accès refusé.
```

| Question | Réponse |
|---|---|
| `Invoke-Native` fonctionne-t-il chez le serveur ? | **Oui** — choco répond, code 0. La porte commune n'est pas en cause. |
| Échoue-t-il sur winget seul ? | **Oui**, sur l'encodage de console, le serveur n'ayant pas de console. |
| Un lancement redirigé passe-t-il ? | **Non** : « Accès refusé » sur l'exécutable lui-même. |

## La cause, et elle est structurelle

Le refus ne porte ni sur le chemin ni sur l'encodage : il porte sur **le droit de lancer le programme**. winget est
livré en paquet MSIX, et un paquet MSIX n'est exécutable que par les comptes **pour lesquels il est enregistré**. Le
fichier est lisible par un processus élevé — c'était la mesure précédente — mais le lancer est autre chose.

C'était déjà écrit dans le dépôt, dans un commentaire de `common.ps1` : « un paquet MSIX n'est lançable que par les
comptes… ». Je ne l'avais pas relié.

## Conséquence sur le plan

**L'étape 2 ne peut pas se faire comme prévue.** Elle reposait sur : gestionnaire installé pour tout l'ordinateur →
l'app serveur, qui est élevée. Pour winget, l'app serveur n'a aucun accès, quel que soit son niveau de privilège.

Donc **les 17 mises à jour winget doivent passer par la session du compte**, y compris les **12 de portée
ordinateur** — qui demanderont une élévation dans cette session. C'est une décision du propriétaire, pas la mienne :
elle met une demande UAC dans sa session.

Ce qui reste valable sans lui : Chocolatey répond au serveur (code 0), donc un gestionnaire installé pour tout
l'ordinateur **et accessible au serveur** suit bien la règle. La règle est juste ; winget en est l'exception, pour
une raison de Windows.
