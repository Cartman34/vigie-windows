<?php
/**
 * @author Florent HAZARD <f.hazard@sowapps.com>
 *
 * Les SENTINELLES declarees par les modules, lues DANS leurs module.psd1.
 *
 * POURQUOI CE FICHIER EXISTE
 * Recopier la liste a la main dans une page HTML, c'est la condamner a diverger : le jour
 * ou un module en declare une de plus, l'Atelier montre l'ancienne liste et se fait
 * valider sans qu'on voie le probleme (D24). On lit donc la source, comme palette.php lit
 * tray.ps1.
 *
 * En cas d'echec, on renvoie une erreur explicite plutot qu'une liste vide : une page qui
 * dit « aucune sentinelle » alors qu'il y en a est pire que pas de page.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$racine = dirname(__DIR__, 2);
$probes = $racine . DIRECTORY_SEPARATOR . 'apps' . DIRECTORY_SEPARATOR . 'backend-pode'
        . DIRECTORY_SEPARATOR . 'probes';

if (!is_dir($probes)) {
    http_response_code(500);
    echo json_encode(['erreur' => "Dossier des sondes introuvable : $probes"], JSON_UNESCAPED_UNICODE);
    exit;
}

$sentinelles = [];
foreach (glob($probes . DIRECTORY_SEPARATOR . '*' . DIRECTORY_SEPARATOR . 'module.psd1') as $psd1) {
    $module = basename(dirname($psd1));
    $texte  = @file_get_contents($psd1);
    if ($texte === false) { continue; }

    // On isole le bloc « Sentinels = @( ... ) », puis chaque @{ ... } qu'il contient.
    if (!preg_match('/Sentinels\s*=\s*@\((.*?)
\s*\)/s', $texte, $bloc)) { continue; }
    if (!preg_match_all('/@\{(.*?)\}/s', $bloc[1], $entrees)) { continue; }

    foreach ($entrees[1] as $entree) {
        $lire = static function (string $cle) use ($entree): ?string {
            if (preg_match('/' . $cle . "\s*=\s*'([^']*)'/", $entree, $m)) { return $m[1]; }
            if (preg_match('/' . $cle . '\s*=\s*(\d+)/', $entree, $m)) { return $m[1]; }
            return null;
        };
        $cartes = [];
        if (preg_match('/Cards\s*=\s*@\(([^)]*)\)/', $entree, $m)) {
            preg_match_all("/'([^']+)'/", $m[1], $c);
            $cartes = $c[1];
        }
        $cle = $lire('Key');
        if ($cle === null) { continue; }
        $script = dirname($psd1) . DIRECTORY_SEPARATOR . $cle . '.watch.ps1';
        $sentinelles[] = [
            'module'   => $module,
            'cle'      => $cle,
            'libelle'  => $lire('Label') ?? $cle,
            'secondes' => (int) ($lire('Seconds') ?? 900),
            'cartes'   => $cartes,
            'script'   => 'apps/backend-pode/probes/' . $module . '/' . $cle . '.watch.ps1',
            'presente' => is_file($script),
        ];
    }
}

echo json_encode(['sentinelles' => $sentinelles], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
