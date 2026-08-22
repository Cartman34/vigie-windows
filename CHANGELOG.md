# Changelog

## [non publie]
### Ajoute
- Scaffold initial du projet (arborescence, conventions, doc 4 volets).
- Contrat REST v1 (`api/openapi.yaml`).
- Maquette front generique (thèmes + modules + actions), branchee sur un mock.
### A faire
- Backend Pode implementant le contrat.
- Modele de sondes/actions auto-decouvert par thème.
- Icone barre systeme + fenetre WebView2 + lancement a l'ouverture de session.

## 2026-08-19 — Backend + front branches
### Ajoute
- Backend Pode : `backend/start.ps1`, `backend/server.ps1`, `backend/lib/common.ps1`.
- Endpoints : `/health`, `/state`, `/modules/{id}`, `/actions` (jeton Bearer).
- Sondes Windows Update : `wu-lock`, `wu-history` (lecture directe).
- Actions : `update-mode-on`, `update-mode-off`, `run-audit`, `open-folder`.
- Front v2 : consomme le contrat (API en direct + repli mock).
- Documentation : `docs/conventions.md`, `docs/technologies.md`, mise a jour des
  4 volets ; fichier de suivi `SUIVI.md` ; fichier d'init renomme
  `PRISE-EN-MAIN.md` (nom non-standard).

## 2026-08-19 (b) — Scripts install/lancement
### Ajoute
- `backend/install.ps1` (idempotent) : NuGet, PSGallery, Pode, jeton — sans invite.
- `backend/run.ps1` : lancement + ouverture navigateur ; options -Admin, -NoBrowser.

## 2026-08-19 (c) — Idempotence
### Modifie
- `start.ps1`/`run.ps1` : garde "deja en cours" (via `Test-ServerUp`), plus de
  double demarrage.
- `docs/conventions.md` : regle "tous les scripts idempotents".

## 2026-08-19 (d) — Organisation des ports
### Modifie
- Port par defaut 8787 -> 47600 ; documente comme configurable.
### Ajoute
- `LocalWork/PORTS.md` : registre des ports (plage 47600-47699).
- `docs/conventions.md` : convention d'allocation des ports.

## 2026-08-19 (e) — Fix encodage PowerShell 5.1
### Corrige
- `.ps1`/`.psd1` reconvertis en ASCII pur (les accents/tiret cadratin cassaient
  l'analyse en Windows PowerShell 5.1). Regle documentee dans conventions.md.

## 2026-08-19 (f) - Cible PowerShell 7 + UTF-8
### Modifie
- `install/start/run.ps1` : bascule auto en pwsh (PS7), UTF-8 natif ; install.ps1
  installe PS7 via winget si absent. Lanceurs conserves en ASCII pour la bascule.
- `docs/conventions.md` : PS7 + UTF-8 remplace la contrainte ASCII generale.

## 2026-08-19 (g) - Journalisation fichier
### Ajoute
- `lib/common.ps1` : `Get-LogDir`, `Write-Log`.
- `install.ps1`/`start.ps1` : transcript + journalisation dans backend/logs/.
- `server.ps1` : logs Pode (erreurs + requetes) sur fichier.

## 2026-08-19 (h) - Front operationnel + UI
### Corrige
- Balise <script> non fermee dans index.html (JS non execute).
### Ajoute
- UI-STATUS : accent de couleur + icone de statut par carte.
- UI-ACTION-TRACK : panneau de suivi des actions (etat + message + heure).

## 2026-08-19 (i) - Statut par parametre
### Ajoute
- Contrat : champ `status` par `Field` (ok/warn/error/neutral).
- Sondes wu-lock / wu-history : statut renseigne par ligne.
- Front : pastille de couleur + valeur teintee par parametre.

## 2026-08-19 (j) - Widgets Disque/WSL/Securite + acces permanent + aide
### Ajoute
- Sondes system/disk, wsl/wsl, security/vbs + actions associees.
- Field.help (contrat) + infobulles front.
- install-autostart.ps1 / uninstall-autostart.ps1 (tache au logon + raccourci).

## 2026-08-19 (k) - UX statuts/actions
### Corrige
- Icone d'aide (glyphe non supporte) -> "i" dessine en CSS.
- Bug 500 : catch de Get-State utilisait $_ (l'erreur) au lieu du nom de fichier.
- New-ModuleObject accepte 'neutral' (statut module info).
### Ajoute
- Depliage du detail par parametre (clic sur "i"), colore selon le statut.
- Field.status 'neutral' rendu (anneau creux + badge Info).
- Action.help : tooltip par action + explication reprise dans la confirmation.

## 2026-08-19 (l) - Widgets complets + vue dense
### Ajoute
- Sondes : system/os (edition+activation), system/perf (RAM/CPU/uptime),
  security/defender (temps reel + definitions + derniere analyse),
  security/firewall (profils), network/net (connexion/IP/VPN),
  windows-update/pending (MAJ detectees, recherche LOCALE sans installer).
- Theme 'Reseau'.
### Modifie
- Front : vue compacte (beaucoup d'infos d'un coup) ; delai /state 30 s ;
  rafraichissement auto 60 s.

## 2026-08-19 (n) - Securite + remediation + UI tuiles
### Securite (revue : docs/operating/SECURITY.md)
- CRITIQUE : POST /actions permettait une traversee de chemin via `type`
  (execution de script arbitraire sur serveur eleve). Corrige : liste blanche +
  confinement du chemin (route + Invoke-ActionById).
- Anti-CSRF : controle d'origine locale sur les requetes modifiantes.
### Ajoute
- Remediation : Field.fixAction (action programmable) / Field.guide (instructions
  manuelles) ; bouton "Resoudre" ; popin d'instructions.
- Action.kind (immediate/confirm/manual) + icones ; confirmation explicative.
### Modifie
- Vue en tuiles ; valeur coloree selon le statut ; details deplies conserves
  entre les refresh ; icone "i" fiable.

## 2026-08-19 (o) - UI lisible + elevation
### Corrige
- Retour aux LIGNES lisibles (label a gauche, valeur coloree a droite) au lieu
  des tuiles ; contenu en pleine largeur.
### Modifie
- start.ps1 / run.ps1 : auto-elevation (demande UAC si besoin) pour que le
  serveur tourne avec les droits. Protections maintenues (voir SECURITY.md).

## 2026-08-19 (p) - antivirus reel, reseau, pare-feu, version, UX refresh
### Corrige
- Antivirus : lecture via SecurityCenter2 -> affiche l'antivirus REEL (Avast...),
  plus seulement Defender.
- Pare-feu : comparaison d'etat robuste (etait "Non" a tort).
- Reseau : connectivite detectee sur tout profil (IPv4/IPv6).
- Texte ACL clarifie (serveur eleve par defaut).
### Ajoute
- Reseau : action "Mesurer debit/latence" (ping + ~10 Mo), resultat memorise
  (.state/netmeasure.json) et affiche.
- Version applicative (Get-AppVersion) exposee (/health, /state, injectee dans
  la page) : la page se RECHARGE seule si la version serveur change.
- Indicateur "Actualisation en cours" (spinner + bouton desactive) a chaque refresh.

## 2026-08-19 (q) - masonry, valeur en face, accents, cache
### Modifie
- Cartes en MASONRY (colonnes qui se remplissent) au lieu de bandes par theme ;
  le theme devient une etiquette sur la carte.
- Champs : valeur en face du label (passe dessous si longue, alignee a droite).
- ACCENTS ajoutes partout (labels/aides des sondes, themes) - possible en PS7/UTF-8.
### Ajoute
- Cache par sonde avec TTL (perf 8s ... os 3600s) : rafraichissements legers,
  plus de recalcul complet a chaque fois. Invalidation auto si le code des
  sondes change (empreinte _codeStamp).
