# Revue de securite

L'outil expose une API REST **locale** qui peut piloter Windows, potentiellement
depuis un serveur **eleve** (demarrage automatique). Cette page recense les
risques et les mesures. A relire a chaque ajout d'action.

## Modele de menace
- Ecoute **strictement 127.0.0.1** (jamais 0.0.0.0). Pas d'acces reseau externe.
- Menace principale : un autre **processus local** (ou une page web ouverte dans
  le navigateur) qui tenterait d'appeler l'API pour declencher des actions.

## Risques et mesures
1. **Execution de script arbitraire** via le champ `type` de POST /actions
   (ex. `type = ../../..`).  -> CORRIGE : liste blanche `^[a-z0-9-]{1,40}$` cote
   route ET cote `Invoke-ActionById`, + confinement du chemin resolu au dossier
   `actions/` (Resolve-Path + StartsWith). Toute tentative est rejetee.
2. **CSRF / drive-by localhost** (une page web malveillante POST vers 127.0.0.1)
   -> CORRIGE : sur toute requete modifiante, l'entete **Origin/Referer** doit
   correspondre a http://127.0.0.1:PORT ou http://localhost:PORT, sinon 403.
3. **Jeton Bearer** exige sur toute l'API sauf `/health`. Ecoute locale.
4. **Actions** : n'executent PAS de commande construite depuis l'entree client ;
   les `params` ne sont jamais passes a un shell. Chaque action est un script
   fixe du dossier `actions/`.

## Risque residuel (a connaitre)
- Le **jeton est injecte dans la page** servie par la route `/` (non
  authentifiee, pour que le navigateur puisse charger l'UI). Un processus local
  tournant **en tant que l'utilisateur** peut donc lire http://127.0.0.1:PORT/ et
  recuperer le jeton. Combine a un serveur **eleve**, cela reste une voie
  d'elevation locale possible.
  - Attenuation actuelle : ecoute locale + controle d'origine + liste blanche.
  - Durcissement recommande si besoin de + de surete :
    - Lancer le serveur **en utilisateur** (non eleve) et n'elever **que
      l'action** au moment ou elle s'execute (invite UAC par action).
    - Rotation periodique du jeton.
    - Restreindre l'ACL du fichier `apps/backend-pode/.secrets/api.token`.

## Regle
Toute nouvelle action doit : porter un `id` simple (`[a-z0-9-]`), ne jamais
interpoler d'entree client dans une commande, et etre revue ici si elle touche a
la securite du systeme.

## Note : serveur eleve par conception
Le serveur tourne desormais **en administrateur** (start.ps1 / run.ps1 demandent
l'UAC si besoin), car il doit pouvoir appliquer les actions systeme. Les
protections restent en place : ecoute 127.0.0.1, jeton Bearer, anti-CSRF
(origine locale), liste blanche + confinement des actions. Risque residuel du
jeton injecte : voir plus haut ; durcissement possible (serveur non eleve +
elevation par action) si un jour on veut reduire encore la surface.
