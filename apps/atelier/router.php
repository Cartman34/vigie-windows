<?php
/**
 * Routeur de l'Atelier — filtre de sécurité du serveur de développement.
 *
 * L'Atelier sert la RACINE du dépôt, parce qu'il doit lire des fichiers de plusieurs
 * apps (les icônes du tray, le frontend, le contrat). Sans filtre, il exposerait aussi
 * tout le reste — dont apps/<app>/var/secrets/api.token, le jeton de l'API de Vigie.
 *
 * Ce routeur refuse explicitement ce qui ne doit jamais sortir. Il rend `false` pour
 * tout le reste, ce qui laisse le serveur intégré de PHP servir le fichier normalement.
 *
 * Principe : liste de REFUS explicite, pas de liste d'autorisation. Une liste
 * d'autorisation casserait dès qu'on ajoute une ressource à la page, et la tentation
 * serait alors de l'élargir jusqu'à ne plus rien filtrer.
 */

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?? '/';
$path = rawurldecode($path);
// Normalise les antislashs : sous Windows, /apps\backend-pode\var\ atteindrait le
// même fichier en contournant un motif qui ne testerait que les slashs.
$normalized = str_replace('\\', '/', $path);

$denied = [
    '#(^|/)var(/|$)#',      // donnees d'execution : cache, journaux, SECRETS
    '#(^|/)config(/|$)#',   // configurations, y compris les surcharges machine
    '#(^|/)\.#',            // tout element cache : .git, .gitignore, .secrets...
    '#\.psd1$#i',           // fichiers de config PowerShell, ou qu'ils soient
    '#\.log$#i',            // journaux
    '#\.token$#i',          // jetons
];

foreach ($denied as $pattern) {
    if (preg_match($pattern, $normalized)) {
        http_response_code(403);
        header('Content-Type: text/plain; charset=utf-8');
        echo "403 - L'Atelier ne sert pas ce chemin.\n";
        echo "Les donnees d'execution (var/) et les configurations ne sont jamais exposees.\n";
        return true;
    }
}

// false = « je ne prends pas en charge », le serveur intégré sert le fichier.
return false;
