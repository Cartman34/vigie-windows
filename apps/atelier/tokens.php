<?php
/**
 * Jetons de design du front — lus dans apps/frontend-web/index.html, jamais recopiés.
 *
 * La page « Design système » de l'Atelier affiche la palette RÉELLE : si une couleur
 * change dans le front, la maquette change avec elle. Une copie aurait fini par mentir —
 * même principe que palette.php pour le menu du tray (D15, D24).
 *
 * Rend { dark: {"--bg": "#0d1117", ...}, light: {...} } d'après :
 *   - le bloc :root{...} (thème sombre, défaut) ;
 *   - le bloc [data-theme="light"]{...} ou :root[data-theme="light"]{...}.
 */

header('Content-Type: application/json; charset=utf-8');

$front = dirname(__DIR__) . '/frontend-web/index.html';
$html = @file_get_contents($front);
if ($html === false) {
    http_response_code(500);
    echo json_encode(['error' => "Lecture impossible : apps/frontend-web/index.html"]);
    return;
}

function extraireVars(string $bloc): array {
    $vars = [];
    if (preg_match_all('/(--[a-z0-9-]+)\s*:\s*([^;}]+)[;}]/i', $bloc, $m, PREG_SET_ORDER)) {
        foreach ($m as $x) { $vars[$x[1]] = trim($x[2]); }
    }
    return $vars;
}

$out = ['dark' => [], 'light' => []];
if (preg_match('/:root\s*\{([^}]*)\}/s', $html, $m)) {
    $out['dark'] = extraireVars($m[1]);
}
if (preg_match('/\[data-theme="light"\]\s*\{([^}]*)\}/s', $html, $m)) {
    $out['light'] = extraireVars($m[1]);
}

if (!$out['dark']) {
    http_response_code(500);
    echo json_encode(['error' => "Aucun bloc :root trouvé dans le front — le format a changé, adapter tokens.php."]);
    return;
}

echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
