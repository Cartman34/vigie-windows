# Seize logiciels installés au lieu d'un

Incident du 06/10 sur la machine du propriétaire, provoqué par moi en éprouvant le bouton de mise à jour winget.
**Rien n'a levé** : chaque maillon a fait exactement ce qu'on lui demandait.

## Ce qui a été demandé, et ce qui a eu lieu

Il avait choisi le paquet d'essai : `7zip.7zip`, 26.02 → 26.03, « petit, autonome, sans conséquence s'il échoue ».

Le journal de l'opération dit `(1/16)`, `(2/16)`… **Seize paquets installés** :

7-Zip · Thunderbird · Notepad++ · VLC · GitHub CLI · VirtualBox · PhysX · GameInput · VS Build Tools ·
Rockstar Launcher · Ubisoft Connect · Python Launcher · **Tabby** · Insomnia · Terminal Windows · **WSL 2.7.13**

## Ce que ça a coûté

- **Tabby a été fermé**, avec le travail qui tournait dedans. La mise à jour désinstalle puis réinstalle : son
  épingle de la barre des tâches a disparu avec l'ancienne installation. Le logiciel était toujours là, en 1.0.237,
  et son raccourci du menu Démarrer aussi.
- **WSL n'a finalement PAS été mis à jour.** Il figurait dans la liste des seize — `(16/16)` dans le journal — mais
  l'installation ne s'est pas appliquée : `winget upgrade` le liste toujours en **2.7.12.0 → 2.7.13** après coup.
  Douze des seize paquets se sont installés, pas tous. J'avais annoncé l'inverse au propriétaire ; c'était faux, et
  ça comptait, puisqu'il s'était réservé ce geste.

## La cause, en deux temps

**1. Une faute d'appel.** L'action `pkg-upgrade` lit `Params.ids`. Mon appel a passé la liste sous `Params.pkgs`.
Elle est arrivée vide.

**2. Un défaut de conception, qui a transformé la faute en incident.** Une liste vide valait **« tout le
gestionnaire »**. `Invoke-PkgUpgrade` est alors passée de `upgrade --id <paquet>` à `upgrade --all`.

Une absence d'information avait été écrite comme une permission maximale. C'est ça, le défaut — pas le nom de
paramètre, qui n'est jamais une sécurité : celui qui appelle peut toujours se tromper.

## Ce qui est en place pour que ça ne puisse plus arriver

**La convention est écrite.** Elle existait dans l'usage — `scripts/check-probes.ps1 -All` fonctionne ainsi depuis
le début — et nulle part dans l'écrit, ce qui est précisément pourquoi elle a été enfreinte. Elle est maintenant
dans `doc/en/developing/conventions.md` et arbitrée par **D131** : *« Tout » se demande, il ne se déduit jamais
d'une absence.*

**Quatre portes refusent**, et la plus importante est la dernière, au plus près du geste :

| Niveau | Sans paquet et sans « tout » explicite |
|---|---|
| `pkg-upgrade.action.ps1` | refuse, et accepte désormais les deux noms employés (`ids` et `pkgs`) |
| `Start-PkgJob` | refuse |
| `pkg-updates.action.ps1` (tâche cliente) | refuse |
| **`Invoke-PkgUpgrade`** — là où `--all` partait | **refuse** |

**Et un vérificateur le tient** : `scripts/dev/check-sets.ps1` exige, de toute fonction agissant sur un ensemble, un
commutateur `-All` et un refus quand rien n'est désigné. Il a trouvé `Invoke-PkgUpgrade` du premier coup — la
fonction même qui avait lancé `upgrade --all`.

## Rejoué, scénario par scénario

```
la fonction, liste vide, sans -All   -> refus : « aucun paquet désigné »
l'action, sans aucun paquet          -> refus : « cochez ce qui doit être mis à jour »
la tâche cliente, sans paquet        -> refus : « aucun paquet désigné »
le drapeau -All existe               -> oui, et c'est le seul moyen de dire « la totalité »
```

## Éprouvé après correctif : un seul paquet, et rien d'autre

Même chemin, même carte, un paquet visé — `7zip.7zip`, déjà à jour, pour ne rien installer de plus sur la machine.

```
=== 7zip.7zip (code -1978335189) === deja a jour, ignore
```

Une ligne, contre seize blocs `(n/16)` la fois précédente. L'opération rend code 0 en 17 s, et le décompte reste à
cinq mises à jour disponibles : **aucune autre n'a bougé**.
