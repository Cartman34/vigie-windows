# Guide utilisateur

> Public : toi, au quotidien. Comment lancer, lire et piloter le panneau.

## Lancer le panneau

En cible (une fois CORE-AUTOSTART fait) : le panneau se lance seul a l'ouverture
de session ; une **icone dans la barre systeme** (pres de l'horloge) resume
l'etat par sa couleur (vert = conforme, ambre = a surveiller, rouge = action
requise). Un clic ouvre la fenetre.

Aujourd'hui (dev), on le lance a la main :

    powershell -ExecutionPolicy Bypass -File backend\start.ps1

puis on ouvre **http://127.0.0.1:47600/**. Sans back lance, ouvrir
`apps/frontend-web/index.html` montre le mode maquette (donnees simulees).

## Lire le tableau de bord

Regroupe par **theme** (Windows Update, Systeme, WSL, Securite). Chaque **carte**
= un module surveille, avec une pastille de statut et ses valeurs. Le bandeau du
haut indique si on est connecte a l'API (donnees reelles) ou en maquette.

## Actions disponibles (aujourd'hui)

- **Mode MAJ (deverrouiller)** / **Re-verrouiller** (`WU-UPDATEMODE`) : bascule le
  verrouillage Windows Update. Deverrouille pour faire tes mises a jour dans
  Parametres, redemarre quand TU veux, puis re-verrouille. (Confirmation demandee.)
- **Lancer l'audit** (`WU-AUDIT`) : produit un rapport complet de la machinerie
  Windows Update (ecrit dans le dossier LocalAgentAdmin).
- **Ouvrir le dossier** : ouvre l'explorateur sur le dossier d'outillage.
- **Rafraichir** : recharge l'etat (auto toutes les 30 s).

## Themes a venir
Systeme (disque), WSL, Securite (VBS/HVCI) : voir `../implemented/status.md`.

## Raccourcis (scripts)
Installation (une fois) :  `backend\install.ps1`
Lancement :  `backend\run.ps1`  (ou `backend\run.ps1 -Admin` pour activer les
actions Windows Update).
