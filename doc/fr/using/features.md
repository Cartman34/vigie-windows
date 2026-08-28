# Ce que surveille Vigie

[Sommaire](../README.md) · [English](../../en/using/features.md)

Chaque carte ci-dessous existe dans le code aujourd'hui (une *sonde* sous
`apps/backend-pode/probes/`) ; chaque bouton est une *action* réelle sous
`apps/backend-pode/actions/`. Rien ici n'est prévu ou souhaité : tout est en place.

Les cartes n'apparaissent que si elles sont pertinentes : pas de carte WSL sans WSL, une
carte par gestionnaire de paquets réellement trouvé dans votre `PATH`.

---

## L'interface, en détail

### Le menu du tray

Un clic droit sur l'icône ouvre ce menu. Le tray interroge le serveur toutes les 8 secondes : la couleur de la jauge
n'a jamais plus de quelques secondes de retard.

| Entrée | Effet |
|---|---|
| **Afficher l'application** | ouvre le tableau de bord dans une fenêtre dédiée (Edge ou Chrome en mode `--app` : ni barre d'adresse, ni onglets) |
| Ouvrir dans le navigateur | ouvre le tableau de bord dans un onglet ordinaire |
| *État : …* | non cliquable — l'état courant, en toutes lettres |
| Relancer l'application | redémarre l'app de la barre système, et le serveur avec |
| Redémarrer le serveur | arrête puis relance le serveur Pode |
| Ouvrir les journaux | ouvre le dossier de journaux du serveur dans l'explorateur |
| À propos de Vigie | ouvre le dépôt GitHub |
| Quitter | ferme Vigie (le serveur s'arrête avec) |

La fenêtre dédiée exige un navigateur Chromium. À défaut, utilisez « Ouvrir dans le navigateur ».

### L'anatomie d'une carte

Le **liseré sous l'en-tête de page** est la connexion à l'API : vert = données en direct, orange = maquette (le serveur
est injoignable, la page s'est repliée sur un jeu d'exemple), rouge = erreur. À ne pas confondre avec le **liseré du
bord gauche d'une carte**, qui porte le statut de CE module :

| Statut | Signification |
|---|---|
| Vert | conforme, rien à faire |
| Orange | à surveiller |
| Rouge | un problème |
| Neutre | informatif, ou non mesurable pour l'instant |

Un liseré gauche **qui clignote** signale une tâche de fond en cours sur cette carte : mise à jour de paquets, analyse
du disque, mesure réseau. La page interroge cette carte toute seule, et vous pouvez fermer le navigateur : la tâche
continue.

### Les icônes des boutons

| Icône | Signification |
|---|---|
| Triangle | s'exécute immédiatement |
| Triangle d'avertissement orange | demande d'abord confirmation |
| Liste cochée | ouvre une fenêtre où vous choisissez ce qui sera appliqué |
| Flèche sortante | passe la main à un logiciel externe (Paramètres Windows, nettoyage de disque, explorateur) |

---

## Windows Update

Détaillé sur sa propre page : **[Windows Update](windows-update.md)**. En résumé :

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Verrouillage des mises à jour** | MAJ automatiques oui/non, verrou ACL sur les dossiers de tâches, nombre de tâches désactivées face à celles encore actives (dépliez pour l'état réel de chacune), redémarrage en attente | *Mode MAJ (déverrouiller)* ou *Verrouiller maintenant* — selon l'état, toujours avec confirmation — et *Lancer l'audit* |
| **Mise à jour du système** | mises à jour détectées dans le cache local de Windows Update, dernière analyse en ligne et son résultat, installation en cours ou dernière installation | *Vérifier les mises à jour* (analyse en ligne, en tâche de fond), *Installer des mises à jour* (ouvre une liste, vous choisissez), *Ouvrir Windows Update* |
| **Historique** | dernier redémarrage, état de démarrage de WaaSMedic | *Ouvrir le dossier* — proposé **seulement** si un dossier d'administration est configuré |

Un **redémarrage en attente s'affiche en orange, pas en rouge** : c'est l'issue normale
d'une installation réussie, pas une panne. Vigie ne redémarre jamais votre machine.

## Système

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Windows** | édition, activation, version | — |
| **Disque C:** | espace libre, seuil d'alerte, taux d'occupation, taille totale. Passe en orange sous le seuil. | *Nettoyage de disque…* (ouvre `cleanmgr` de Windows) |
| **Ressources** | RAM utilisée (%), RAM libre, CPU (%), uptime. Orange au-delà de 90 % de RAM ou de CPU. | — |

## Alimentation

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Alimentation** | source (secteur ou batterie), niveau de la batterie, sens du courant, et surtout : **le chargeur suit-il ?** | *Options d'alimentation* (ouvre les Paramètres Windows) |

Cette carte n'existe **que sur une machine à batterie** : un poste fixe n'a rien à en dire. Son intérêt est le cas
qu'on ne voit pas autrement : branché au secteur **et** batterie en décharge. C'est que le chargeur ne couvre pas la
consommation — le processeur et le GPU vont être bridés, et la batterie se videra malgré le branchement. La carte
passe alors en orange et le dit en toutes lettres.

## Gaming

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Gaming** | carte graphique, VRAM utilisée sur le total réel, température GPU, jeu détecté et ce qu'il consomme, autres applications gourmandes pendant la partie, alimentation | *Gestionnaire des tâches*, *Gestionnaire de périphériques* |

C'est un **outil de diagnostic** : quand le jeu rame, la carte montre qui prend quoi — processeur, GPU, VRAM, mémoire,
entrées/sorties — et désigne l'application qui pompe pendant la partie. Elle ne règle rien toute seule et ne modifie
aucun réglage : elle regarde.

## Réseau

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Réseau** | connexion Internet, type de connexion, nom du réseau, état Wi-Fi, IP locale, IP publique, IPv6, adresse MAC, VPN actif, latence, débits descendant et montant, et la date de la mesure | *Obtenir l'IP publique*, *Mesurer débit/latence* |

La latence et le débit ne sont **pas** mesurés en continu : ils affichent « non mesuré »
tant que vous n'avez pas appuyé. La mesure ping `1.1.1.1` et transfère environ 10 Mo en
descente et 5 Mo en montée contre le point de mesure de Cloudflare. C'est le seul endroit
où Vigie parle au monde extérieur en votre nom, et uniquement à votre demande.

## Comptes

Deux cartes, parce que ce sont deux questions différentes : *qui* a Vigie, et *comment* elle est installée.

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Comptes** | un compte Windows par ligne : administrateur ou standard, Vigie activée ou non, et le défaut de sa tâche de démarrage s'il y en a un | *Détails des comptes*, *Actualiser la liste*, *Gérer les comptes* |
| **Déploiement** | installation partagée et sa version, PowerShell 7, état du démarrage automatique, dernière mise à jour, stockage occupé | *Mettre à jour l'installation*, *Vérifier le démarrage de Vigie*, *Mise à jour de Vigie* |

**Activer un compte, c'est lui poser sa tâche de démarrage** — au niveau que Windows lui accorde, jamais plus : élevé
pour un administrateur, limité pour un compte standard. Vigie ne donne aucun pouvoir supplémentaire à personne.

### Les trois états du démarrage automatique

C'est la ligne à lire quand Vigie ne se lance pas sur un compte. Elle distingue ce qui est cassé de ce qui attend, et
la différence n'est pas cosmétique : dans un cas il y a un geste à faire, dans l'autre il n'y en a aucun.

| État | Ce que ça veut dire | Ce qu'on peut faire |
|---|---|---|
| **Opérationnel** | chaque compte qui a Vigie porte une tâche saine | rien |
| **À confirmer** | la tâche est correctement installée, mais son dernier lancement s'est mal passé — ou elle n'a jamais tourné | rien : c'est la prochaine ouverture de session de ce compte qui tranchera |
| **Hors service** | la tâche ne peut pas lancer l'application : interpréteur disparu, chemin illisible, tâche désactivée dans Windows | *Vérifier le démarrage de Vigie* |

Le bouton de réparation n'apparaît **que** dans le troisième cas. Il réécrit la tâche avec l'interpréteur de la machine
et l'emplacement réel de l'application, la réactive si Windows l'avait désactivée, puis **vérifie**. Il ne prétend
jamais avoir réparé un échec passé : celui-là ne s'efface qu'au prochain démarrage.

### Diagnostiquer un compte qui ne démarre pas

*Détails des comptes* est la porte d'entrée. Pour chaque compte : ses qualités, sa dernière session, ses données Vigie,
et — c'est là que ça se joue — **la ligne de commande exacte de sa tâche, son état, sa dernière exécution et son code de
retour**. C'est ce qui permet de distinguer « la tâche n'existe pas » de « elle existe et meurt aussitôt ».

Une session Windows ordinaire ne voit pas ces informations : seul le serveur de Vigie, qui tourne élevé, peut les lire.
D'où la règle : on diagnostique par Vigie, jamais depuis une fenêtre de commandes.

## Sécurité

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Antivirus** | le nom de l'antivirus principal, s'il est actif, si ses définitions sont à jour, et les autres produits détectés. Inactif = rouge. | — |
| **Pare-feu** | l'état de chaque profil du pare-feu Windows. Un profil désactivé est rouge. | — |
| **Sécurité de la virtualisation** | VBS et intégrité mémoire (HVCI) | *Basculer VBS*, *Basculer intégrité mémoire* — les deux avec confirmation |

Les deux bascules sont **natives** : elles écrivent la valeur dans le registre
(`HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard`), après une sauvegarde `.reg` déposée
dans les journaux de Vigie. Elles exigent un serveur **administrateur** et le disent
clairement sinon.

**Elles ne prennent effet qu'au redémarrage.** La carte l'affiche : tant que la demande
n'est pas appliquée, une ligne *En attente de redémarrage* apparaît et le bouton
*Redémarrer Windows* — différé de 60 secondes, annulable — est proposé sur cette carte.
Recliquer sur la bascule avant d'avoir redémarré **annule simplement la demande**.

Désactiver VBS coupe aussi l'intégrité mémoire, qui ne peut pas fonctionner sans elle ;
l'inverse n'est pas vrai, activer VBS n'active pas l'intégrité mémoire dans votre dos.
Si une valeur ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI
ou par une stratégie d'entreprise, et Vigie ne peut pas passer outre.

## WSL

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **WSL2** | si WSL est installé, la distribution par défaut, et un statut *Actif / Inactif* coloré | *Démarrer* à l'arrêt ; *Redémarrer* et *Arrêter* en marche |

Seuls les boutons pertinents pour l'état courant sont affichés. « Inactif » colore en rouge
le champ **et** la carte.

## Gestionnaires de paquets

Une carte par gestionnaire trouvé dans votre `PATH`, dans ce catalogue :

| Gestionnaire | Version | Vérifier les MAJ | Tout mettre à jour |
|---|---|---|---|
| winget | oui | oui | oui |
| Chocolatey | oui | oui | oui |
| Scoop | oui | oui | oui |
| npm | oui | oui | oui |
| RubyGems | oui | oui | oui |
| pnpm | oui | oui | — |
| pip (Python) | oui | oui | — |
| Yarn, pipx, Cargo, .NET SDK | oui | — | — |

Chaque carte donne la version installée et son chemin, plus le nombre de mises à jour
disponibles et la liste des paquets une fois la vérification faite. *Vérifier les mises à
jour* et *Mettre à jour* tournent en **tâches de fond détachées** : la carte passe « en
cours », la page l'interroge, et fermer le navigateur n'interrompt rien. Une tâche qui ne
produit rien pendant 45 minutes est considérée perdue et la carte cesse de tourner.

Si aucun gestionnaire n'est trouvé, une carte neutre le dit.

---

## Ce que Vigie ne fait jamais

- Elle ne redémarre jamais votre machine, et ne laisse pas Windows le faire tant que le
  verrou est posé.
- Elle n'installe jamais une mise à jour Windows que vous n'avez pas sélectionnée : une
  liste vide est refusée plutôt qu'interprétée comme « tout ».
- Elle n'écoute jamais en dehors de `127.0.0.1`.
- Elle ne va jamais chercher du code toute seule : télécharger une nouvelle version demande votre geste, et une
  version plus ancienne que celle installée est refusée.
- Elle ne construit jamais une commande shell à partir de ce que le navigateur lui a
  envoyé.

Le tableau complet : [Sécurité](../operating/security.md).
