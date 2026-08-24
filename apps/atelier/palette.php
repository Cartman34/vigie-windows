<?php
/**
 * Palette du menu du tray, lue DANS apps/tray/tray.ps1.
 *
 * POURQUOI CE FICHIER EXISTE
 * L'Atelier affichait des valeurs recopiées à la main. Elles ont divergé de ce qui est
 * livré — fond bleuté #2b3038 dans l'Atelier contre gris neutre #2c2c2c dans le tray —
 * et l'Atelier ne servait plus à valider quoi que ce soit (D24). Toute recopie finit
 * par diverger ; la seule correction qui tienne est de supprimer la recopie.
 *
 * L'Atelier reste l'endroit où l'on RÈGLE les valeurs : les curseurs partent d'ici,
 * puis le bloc de code à reporter dans tray.ps1 s'écrit sous l'aperçu. Le point de
 * départ, lui, est toujours ce qui est réellement livré.
 *
 * En cas d'échec (fichier introuvable, constante disparue), on renvoie une erreur
 * explicite plutôt qu'une valeur de repli : une palette fausse mais plausible est pire
 * que pas de palette du tout, elle se fait valider sans qu'on voie le problème.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

/** Chemin du tray depuis apps/atelier/. */
$trayPath = dirname(__DIR__) . '/tray/tray.ps1';

function fail(string $message, int $code = 500): never
{
    http_response_code($code);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

if (!is_readable($trayPath)) {
    fail("tray.ps1 introuvable ou illisible : $trayPath");
}

$source = file_get_contents($trayPath);
if ($source === false) {
    fail("Lecture impossible : $trayPath");
}

/**
 * Extrait `Color <Nom> = Color.FromArgb(r, g, b);` et rend « #rrggbb ».
 */
function readColor(string $source, string $name): ?string
{
    $pattern = '/\bColor\s+' . preg_quote($name, '/')
        . '\s*=\s*Color\.FromArgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/';
    if (!preg_match($pattern, $source, $m)) {
        return null;
    }
    return sprintf('#%02x%02x%02x', (int) $m[1], (int) $m[2], (int) $m[3]);
}

/**
 * Extrait `const int <Nom> = <entier>;`.
 */
function readInt(string $source, string $name): ?int
{
    $pattern = '/\bconst\s+int\s+' . preg_quote($name, '/') . '\s*=\s*(-?\d+)\s*;/';
    if (!preg_match($pattern, $source, $m)) {
        return null;
    }
    return (int) $m[1];
}

$colors = ['Surface', 'Hover', 'Border', 'Separator', 'Text', 'TextDisabled'];
$ints   = ['CornerRadius', 'MenuRadius', 'InsetX', 'InsetY', 'TextPadX', 'TextPadY'];

$palette = [];
$missing = [];

foreach ($colors as $name) {
    $value = readColor($source, $name);
    if ($value === null) { $missing[] = $name; } else { $palette[$name] = $value; }
}
foreach ($ints as $name) {
    $value = readInt($source, $name);
    if ($value === null) { $missing[] = $name; } else { $palette[$name] = $value; }
}

if ($missing !== []) {
    fail('Constantes absentes de VigieMenuPalette : ' . implode(', ', $missing)
        . '. Le format de tray.ps1 a change, palette.php doit suivre.');
}

echo json_encode([
    'source'  => 'apps/tray/tray.ps1',
    'palette' => $palette,
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
