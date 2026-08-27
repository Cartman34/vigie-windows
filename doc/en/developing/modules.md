# Créer et maintenir un module — LA référence

> Ce document est **la** marche à suivre : toute création ou modification de module s'y
> conforme, et tout brief de sous-agent qui touche aux sondes pointe ici. Ce qui suit est
> issu des décisions (D41, D43, D44, D48, D49, D50, D57) — le détail de chaque règle est
> dans `doc/progress/decisions.md`.

## Le modèle en une phrase

Un **module** = un **dossier de sondes** (`apps/backend-pode/probes/<id>/`), déclaré par un
`module.psd1` versionné ; chaque **sonde** (`*.probe.ps1`) rend une ou plusieurs
**cartes** ; l'utilisateur active/coupe le module et règle ses **paramètres** dans le menu
Paramètres.

## Créer un module, pas à pas

1. **Le dossier** : `apps/backend-pode/probes/<id>/` — `<id>` en anglais, en minuscules ;
   c'est aussi l'identifiant du thème (groupe à l'écran).
2. **La déclaration** `module.psd1` :
   ```powershell
   @{
       Label       = 'Nom affiché'          # français accentué
       Description = 'Une phrase.'          # affichée dans Paramètres > Modules
       Config      = @{ SeuilX = 10 }       # valeurs par DÉFAUT, versionnées (D57)
       Parameters  = @(                     # les clés de Config réglables à l'écran
           @{ Key='SeuilX'; Label='…'; Type='int'; Unit='%'; Help='…' }
       )
   }
   ```
   Tout défaut réglable vit dans `Config` ; la sonde ne lit JAMAIS le fichier local de
   surcharge — uniquement `Get-ModuleSetting -Unit '<id>' -Key 'SeuilX'` (avec un filet
   en dur si la déclaration disparaissait).
3. **Le thème** : ajouter l'entrée dans `$script:ThemeCatalog` (`lib/common.ps1`) — id du
   dossier, label français.
4. **Le TTL** : ajouter la sonde dans `$script:ProbeTtls` (`lib/common.ps1`) — court si ça
   bouge vite (5–15 s), long si c'est stable (10–60 min). Sans entrée : 30 s.
5. **La sonde** `<nom>.probe.ps1` : en tête, le commentaire dit CE QU'ELLE RÉPOND et
   comment elle mesure ; puis `New-ModuleObject -Id … -Theme '<id du dossier>' -Label …
   -Status … -Fields @(New-Field …)`. LECTURE SEULE : une sonde n'agit jamais.

## Ce qu'une carte doit dire (D49 — le contrôleur le vérifie)

- Le **statut du module** ne dépasse jamais celui de son pire champ.
- Tout champ porte une **aide** (`-Help`) : elle décrit ce que MONTRE le champ (infobulle).
- Tout champ `warn`/`error` porte **un bouton de résolution** (`-FixAction`) — TOUJOURS
  (**D66**) — et, en plus, un `-Guide` qui explique. Le bouton répare, ou mène à l'endroit
  où l'utilisateur décide (Gestionnaire des tâches, de périphériques…). Ce qui ne se résout
  pas ne s'alerte pas : une attente reste **neutre**. `check-probes.ps1` le vérifie.
- Une **information attendue mais absente** est un `warn` avec une piste de solution,
  jamais une ligne muette.
- Pendant une opération : dire **quoi, sur combien, depuis quand** ; après : le **résultat
  reste visible**. Les points de suspension sont réservés à une action en cours (D50).
- Toute action citée par un champ doit exister dans `actions/` ; libellés d'actions selon
  `kind`/`severity`/`busyLabel` (D50).

## Testabilité : une sonde doit pouvoir s'éprouver SANS son événement

Une sonde dont une branche ne s'exécute que dans une situation rare (un jeu qui tourne,
une panne, un verrou posé) doit offrir un **moyen de forcer cette branche** avec de
vraies données — quitte à ce qu'elles vaillent 0 :

- convention : une variable d'environnement `VIGIE_FAKE_<QUOI>` documentée en tête de la
  sonde (exemple : `VIGIE_FAKE_GAME='chrome'` fait traiter chrome comme le jeu) ;
- la simulation ne fabrique **pas** de fausses valeurs : elle force le **chemin**, les
  mesures restent réelles ;
- l'épreuve fait partie de la validation avant livraison (voir ci-dessous) ;
- une **charge fabriquée** (GPU, CPU, disque) ne se lance **jamais sans l'autorisation
  explicite de l'utilisateur, redemandée à chaque fois** (**D62**) — la recette qui suit
  n'est utilisable que dans ce cadre :
  `scripts/dev/gpu-load.html` (WebGL lourd) lancé dans un Chrome à profil jetable fait
  monter le GPU pour éprouver la détection de jeu — avec OBLIGATOIREMENT
  `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding
  --disable-background-timer-throttling` (Chrome gèle le rendu d'une fenêtre occultée,
  constaté en session distante), puis `taskkill /T` sur le PID lancé et suppression du
  profil. Éprouvé le 24/08 : chrome vu à 19 % GPU et désigné comme jeu, sans simulation.

## Valider avant de livrer (dans cet ordre)

> **Ce qui suit est le test COURANT : du contrat, rien d'autre** (**D63**). Les sondes
> sont en lecture seule. Exécuter une **action** ou un **worker** pour de vrai, ou piloter
> l'application de bout en bout, est un test d'**intégration** : il se **demande** à
> l'utilisateur, à chaque fois — comme toute charge fabriquée (**D62**).

```powershell
# 1. Boucle de dev : la sonde touchée, exécutée pour de vrai
pwsh -File .\scripts\check-probes.ps1 -Only <id>
# 2. Les branches rares, forcées (si la sonde en a)
$env:VIGIE_FAKE_GAME='chrome'; pwsh -File .\scripts\check-probes.ps1 -Only gaming; Remove-Item Env:VIGIE_FAKE_GAME
# 3. Avant fusion : la passe complète
pwsh -File .\scripts\check-probes.ps1 -All
```

Le parseur ne suffit pas (D50bis) ; le code de retour ne suffit pas non plus : on
**constate** la sortie (D43). Dates : UTC en écriture, `ConvertTo-UtcDate` en relecture
(D44).

## Maintenir

- Un seuil ou réglage nouveau → une clé `Config` + une entrée `Parameters`, jamais un
  nombre en dur ajouté dans la sonde.
- Une évolution visible à l'écran → répercuter la page « Design système » de l'Atelier
  dans la même livraison (`doc/en/developing/design.md`).
- Un nouveau module → il apparaît automatiquement dans Paramètres > Modules (catalogue) ;
  vérifier que couper/rallumer fonctionne.
- Après toute modification servie : recharger la page **servie** (jamais `file://`, D47).
