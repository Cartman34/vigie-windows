# Sécurité

[Sommaire](README.md) · [English](../en/security.md)

Vigie expose une API REST locale capable de modifier Windows, depuis un processus qui
tourne élevé. Cela mérite un exposé franc de ce qui est protégé et de ce qui ne l'est pas.

---

## Pourquoi elle tourne en administrateur

Le verrou Windows Update écrit sous `HKLM`, désactive des tâches planifiées et pose des ACL
sur des dossiers de tâches. Basculer VBS/HVCI est tout aussi privilégié. Ce qui sert l'API
doit donc être élevé.

- Lancée par la tâche planifiée **`Vigie`**, enregistrée en `RunLevel Highest`.
- Lancée à la main, `run.ps1` **s'élève via UAC**.
- Non élevée, Vigie ne fait pas semblant : le champ *Verrou ACL* affiche « serveur non
  élevé » en valeur neutre, plutôt qu'un faux avertissement.

**Avant toute invite UAC**, les scripts d'installation et de désinstallation affichent une
fenêtre qui énumère les changements concrets et ce qui n'est explicitement *pas* touché.
Échap et la croix **refusent**, et un refus rend le code `3` sans qu'aucune invite système
n'ait été affichée. Les exécutions automatisées passent `-Yes` ; sans bureau, les scripts
expliquent en console et **refusent par défaut**.

## Ce qui est exposé

| | |
|---|---|
| Adresse d'écoute | **`127.0.0.1` uniquement** — jamais `0.0.0.0`, jamais une interface réseau |
| Port | `47600` |
| API | sous `/api/v1` : `GET /health`, `GET /state`, `GET /modules/{id}`, `POST /actions` |
| Authentification | un **jeton Bearer**, exigé partout sauf sur `/health` |
| Stockage du jeton | `apps/backend-pode/var/secrets/api.token`, généré au premier lancement, jamais versionné |

## Les quatre défenses

1. **Liste blanche d'actions.** Le champ `type` de `POST /actions` doit correspondre à
   `^[a-z0-9-]{1,40}$`, vérifié côté route **et** côté aiguillage, et le chemin résolu est
   confiné au dossier `actions/`. Un `type` valant `../../..` est rejeté.
2. **Anti-CSRF.** Sur toute requête modifiante, l'en-tête `Origin`/`Referer` doit
   correspondre à `http://127.0.0.1:PORT` ou `http://localhost:PORT`, sinon `403`. C'est ce
   qui empêche une page web malveillante ouverte chez vous de poster vers votre propre
   machine.
3. **Aucune injection de commande.** Les actions ne construisent jamais une commande à
   partir de l'entrée client. Les `params` ne sont jamais passés à un shell. Chaque action
   est un script fixe sur le disque.
4. **Rien de sensible n'est versionné.** `apps/backend-pode/var/secrets/` (le jeton),
   `apps/backend-pode/var/cache/` (l'état) et `apps/*/var/log/` sont couverts par
   `.gitignore`.

## Le risque résiduel, dit franchement

Le jeton est **injecté dans la page** servie par `/`, route qui n'est elle-même pas
authentifiée — il faut bien que le navigateur puisse charger l'interface. Donc **tout
processus local tournant en tant que vous peut lire `http://127.0.0.1:47600/` et récupérer
le jeton**. Combiné à un serveur élevé, cela reste une voie d'élévation locale plausible.

Ce qui l'atténue aujourd'hui : l'écoute strictement locale, le contrôle d'origine et la
liste blanche d'actions. Ce qui durcirait davantage, si le besoin s'en fait sentir :

- lancer le serveur **non élevé** et n'élever **que l'action** au moment où elle s'exécute
  (une invite UAC par action) ;
- faire tourner le jeton périodiquement ;
- restreindre l'ACL du fichier `apps/backend-pode/var/secrets/api.token`.

Aucune de ces pistes n'est implémentée en v0.1.

## Règles pour qui ajoute une action

- Lui donner un `id` simple, conforme à `[a-z0-9-]`.
- Ne jamais interpoler d'entrée client dans une commande.
- Si elle touche à la sécurité du système, la faire relire ici avant de l'intégrer.

Voir [Sondes et actions](developpement/sondes-et-actions.md) pour la mécanique, et
[`docs/operating/SECURITY.md`](../operating/SECURITY.md) pour la revue de sécurité interne
du projet.

## Ce que Vigie ne fait pas

- Elle n'ouvre aucun port sur votre réseau.
- Elle ne téléphone à personne. Le seul trafic sortant est la recherche de l'IP publique et
  la mesure de débit, tous deux **uniquement quand vous appuyez sur le bouton**.
- Elle ne collecte et ne transmet rien sur votre machine.
