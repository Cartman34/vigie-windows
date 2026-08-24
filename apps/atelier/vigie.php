<?php
/**
 * Ouvre Vigie depuis l'Atelier — sans recopier le port.
 *
 * L'adresse de l'app vit dans la config PowerShell (BindAddress dans config/common.psd1,
 * Port dans apps/backend-pode/config/config.psd1). Un lien en dur dans les pages de
 * l'Atelier serait une deuxieme definition qui finirait par deriver (D15) : on LIT la
 * config et on redirige. Si la lecture echoue, on le DIT au lieu de rediriger au hasard.
 */

$root = dirname(__DIR__, 2); // racine du depot (apps/atelier -> apps -> racine)

function lirePsd1(string $chemin, string $cle): ?string {
    $texte = @file_get_contents($chemin);
    if ($texte === false) { return null; }
    // Une affectation simple « Cle = valeur » ; on ne veut pas d'un parseur complet.
    if (preg_match('/^\s*' . preg_quote($cle, '/') . "\s*=\s*'?([^'\r\n;#]+)'?/mi", $texte, $m)) {
        return trim($m[1]);
    }
    return null;
}

$adresse = lirePsd1($root . '/config/common.psd1', 'BindAddress') ?? '127.0.0.1';
$port    = lirePsd1($root . '/apps/backend-pode/config/config.psd1', 'Port');

if ($port === null || !ctype_digit($port)) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Impossible de lire le port de Vigie dans apps/backend-pode/config/config.psd1.\n";
    echo "Le lien de l'Atelier refuse de deviner : corrige la config plutot que ce script.\n";
    return;
}

header('Location: http://' . $adresse . ':' . $port . '/', true, 302);
