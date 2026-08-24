# Ce que surveille Vigie

[Sommaire](README.md) · [English](../en/features.md)

Chaque carte ci-dessous existe dans le code aujourd'hui (une *sonde* sous
`apps/backend-pode/probes/`) ; chaque bouton est une *action* réelle sous
`apps/backend-pode/actions/`. Rien ici n'est prévu ou souhaité : tout est en place.

Les cartes n'apparaissent que si elles sont pertinentes : pas de carte WSL sans WSL, une
carte par gestionnaire de paquets réellement trouvé dans votre `PATH`.

---

## Windows Update

Détaillé sur sa propre page : **[Windows Update](windows-update.md)**. En résumé :

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Verrouillage des mises à jour** | MAJ automatiques oui/non, verrou ACL sur les dossiers de tâches, nombre de tâches désactivées face à celles encore actives (dépliez pour l'état réel de chacune), redémarrage en attente | *Mode MAJ (déverrouiller)* ou *Verrouiller maintenant* — selon l'état, toujours avec confirmation — et *Lancer l'audit* |
| **Mise à jour du système** | mises à jour détectées dans le cache local de Windows Update, dernière analyse en ligne et son résultat, installation en cours ou dernière installation | *Vérifier les mises à jour* (analyse en ligne, en tâche de fond), *Installer des mises à jour* (ouvre une liste, vous choisissez), *Ouvrir Windows Update* |
| **Historique** | dernier redémarrage, état de démarrage de WaaSMedic | *Ouvrir le dossier* (outillage externe) |

Un **redémarrage en attente s'affiche en orange, pas en rouge** : c'est l'issue normale
d'une installation réussie, pas une panne. Vigie ne redémarre jamais votre machine.

## Système

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Windows** | édition, activation, version | — |
| **Disque C:** | espace libre, seuil d'alerte, taux d'occupation, taille totale. Passe en orange sous le seuil. | *Nettoyage de disque…* (ouvre `cleanmgr` de Windows) |
| **Ressources** | RAM utilisée (%), RAM libre, CPU (%), uptime. Orange au-delà de 90 % de RAM ou de CPU. | — |

## Réseau

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Réseau** | connexion Internet, type de connexion, nom du réseau, état Wi-Fi, IP locale, IP publique, IPv6, adresse MAC, VPN actif, latence, débits descendant et montant, et la date de la mesure | *Obtenir l'IP publique*, *Mesurer débit/latence* |

La latence et le débit ne sont **pas** mesurés en continu : ils affichent « non mesuré »
tant que vous n'avez pas appuyé. La mesure ping `1.1.1.1` et transfère environ 10 Mo en
descente et 5 Mo en montée contre le point de mesure de Cloudflare. C'est le seul endroit
où Vigie parle au monde extérieur en votre nom, et uniquement à votre demande.

## Sécurité

| Carte | Ce qu'elle montre | Boutons |
|---|---|---|
| **Antivirus** | le nom de l'antivirus principal, s'il est actif, si ses définitions sont à jour, et les autres produits détectés. Inactif = rouge. | — |
| **Pare-feu** | l'état de chaque profil du pare-feu Windows. Un profil désactivé est rouge. | — |
| **Sécurité de la virtualisation** | VBS et intégrité mémoire (HVCI) | *Basculer VBS*, *Basculer intégrité mémoire* — les deux avec confirmation |

Les deux bascules de sécurité s'appuient sur un **outillage externe** qui n'est pas livré
avec le dépôt. Sans lui, l'action rend un message clair au lieu d'échouer obscurément —
voir [Configuration](configuration.md#outillage-externe).

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
- Elle ne construit jamais une commande shell à partir de ce que le navigateur lui a
  envoyé.

Le tableau complet : [Sécurité](securite.md).
