# Windows Update

[Sommaire](README.md) · [English](../en/windows-update.md)

C'est la fonction phare de Vigie, et celle qui change le comportement de votre machine.
Lisez-la avant d'appuyer sur quoi que ce soit dans la carte *Verrouillage des mises à jour*.

---

## Le problème qu'elle résout

Windows décide seul quand télécharger, installer et **redémarrer**. Sur une machine en
plein travail, en plein rendu ou en plein transfert, cette décision n'est pas la vôtre et
ne se discute pas. Les réglages de report achètent des heures, pas le contrôle.

## Ce que le verrou fait réellement

Verrou posé :

- **Les mises à jour automatiques sont coupées** — `NoAutoUpdate = 1` sous
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`.
- **Un verrou ACL est appliqué** sur les dossiers de tâches planifiées de Windows Update :
  un *refus* pour le compte `SYSTEM` sur `UpdateOrchestrator`, `WindowsUpdate`,
  `InstallService` et `WaaSMedic`. C'est lui qui empêche Windows de réactiver
  silencieusement les tâches qu'il répare par conception.
- Les tâches de mise à jour sont désactivées. Certaines restent « Prêtes » parce que
  Windows les protège sous TrustedInstaller ; elles sont inoffensives tant que les MAJ
  automatiques sont coupées, et la carte montre l'état réel de chacune si vous dépliez le
  champ.

Ce qu'il ne fait **pas** : il ne masque aucune mise à jour, ne bloque pas le service
Windows Update, et ne vous empêche d'installer quoi que ce soit. Il retire à Windows la
capacité d'agir sans vous.

## Lire la carte

| Champ | Ce qu'il faut en penser |
|---|---|
| **MAJ automatiques** | *Non* est l'état verrouillé, celui qu'on veut |
| **Verrou ACL des tâches** | *Non* est fréquent juste après une grosse mise à jour ou un passage en mode MAJ — appuyez sur *Verrouiller maintenant* pour le reposer |
| **Tâches désactivées** / **Tâches actives** | informatif ; dépliez pour l'état réel de chaque tâche |
| **Redémarrage en attente** | orange, et pas une panne : une mise à jour s'est installée et Windows veut terminer. Redémarrez quand cela vous arrange — Vigie ne le fera jamais à votre place |

La carte est verte quand les MAJ automatiques sont coupées, orange sinon, et rouge
uniquement quand un redémarrage est en attente.

---

## Installer les mises à jour

Trois voies, toutes délibérées.

### Depuis Vigie (recommandé)

1. Appuyez sur **Vérifier les mises à jour** dans la carte *Mise à jour du système*. C'est
   une vraie analyse **en ligne** contre les serveurs Microsoft — elle prend des minutes,
   d'où la tâche de fond détachée et la carte marquée « en cours ». Le nombre affiché le
   reste du temps vient du cache local de Windows Update, et il est instantané.
2. Appuyez sur **Installer des mises à jour**. Une fenêtre liste ce qui a été trouvé ;
   **vous choisissez** ce qui s'installe. Une sélection vide est refusée plutôt
   qu'interprétée comme « tout ».
3. L'installation tourne également en tâche de fond. Fermer le navigateur ne l'interrompt
   pas.

Pendant l'analyse ou l'installation, Vigie **lève son propre verrou et le repose ensuite**.
Elle vous le dit. Vous demander de défaire à la main un verrou que l'application a posé
elle-même n'aurait pas de sens : c'est traité en interne.

### Le mode MAJ

Appuyez sur **Mode MAJ (déverrouiller)** dans la carte *Verrouillage des mises à jour*
(confirmation demandée). Windows Update redevient normal : installez ce que vous voulez
depuis les Paramètres, redémarrez quand *vous* le décidez, puis revenez appuyer sur
**Verrouiller maintenant**.

N'oubliez pas la seconde moitié. Verrou levé, Windows peut vous redémarrer, et il le fera.

### Les Paramètres Windows

Le bouton **Ouvrir Windows Update** vous passe simplement la main vers le panneau des
Paramètres. Utile quand vous préférez l'interface de Windows ; l'état du verrou s'applique
toujours.

---

## Verrouiller et déverrouiller exigent un outillage externe

Le côté **lecture** est natif : la carte *Verrouillage des mises à jour* lit elle-même le
registre, les tâches planifiées et les ACL, sans aucune dépendance externe.

Le côté **écriture**, non. `Mode MAJ (déverrouiller)`, `Verrouiller maintenant` et
`Lancer l'audit` appellent un script `update-mode.ps1` / d'audit qui vit **hors de ce
dépôt**, dans un dossier d'outillage que vous désignez avec `ToolsPath`. Non configuré,
ces boutons rendent un message clair — « outillage externe non configuré » — au lieu
d'échouer obscurément. Voir [Configuration](configuration.md#outillage-externe).

C'est une limite réelle de la v0.1, dite ici plutôt que découverte sur la machine.

## Vigie constate le résultat, elle ne croit pas le code de retour

Après un verrouillage, Vigie relit l'ACL et la clé de registre, et rapporte ce qu'elle a
réellement obtenu :

- les deux appliqués → « verrou complet appliqué » ;
- MAJ automatiques coupées mais ACL refusée (dossiers protégés par Windows) → elle le dit,
  et pointe le fichier de journal ;
- ni l'un ni l'autre → elle rapporte l'échec, avec le journal.

On ne vous dit jamais « c'est fait » au motif qu'une commande n'a pas levé d'erreur.

---

## Déverrouiller pour de bon

Retirer Vigie ne **déverrouille pas** Windows Update. Si vous désinstallez, appuyez
d'abord sur **Mode MAJ (déverrouiller)** et vérifiez que le champ *MAJ automatiques*
affiche bien *Oui*. Sinon votre machine garde ses mises à jour automatiques coupées, sans
plus rien à l'écran pour vous dire pourquoi.

## Ensuite

- [Ce que surveille Vigie](fonctionnalites.md) — les autres thèmes
- [Sécurité](securite.md) — pourquoi tout ceci exige les droits administrateur
