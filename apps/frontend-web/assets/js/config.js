// @author Florent HAZARD <f.hazard@sowapps.com>

// @author Florent HAZARD <f.hazard@sowapps.com>
// ===== Constantes de l'application (source unique de verite) =====
// L'URL du depot est volontairement une CONSTANTE et non un reglage : elle ne doit pas
// pouvoir changer facilement. Cote PowerShell, son equivalent est $RepoUrl dans client.ps1.
export const REPO_URL        = 'https://github.com/Cartman34/vigie-windows';   // D09
export const SPLASH_MIN_MS   = 550;     // duree minimale d'affichage (evite un flash desagreable)
export const SPLASH_MAX_MS   = 90000;   // garde-fou : l'ecran ne reste jamais bloque (delai max de /state)
export const SPLASH_FADE_MS  = 450;     // doit rester egal a la transition CSS de #splash (--splash-fade)
export const REFRESH_MS      = 60000;   // rafraichissement automatique de l'etat
export const VERSION_POLL_MS = 15000;   // detection d'une nouvelle version servie
