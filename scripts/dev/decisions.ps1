# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    CHERCHER DANS LES DECISIONS AVANT DE CONCEVOIR.

    doc/progress/decisions.md est la source de verite du projet -- « a ne JAMAIS perdre ».
    Elle fait plus de deux mille lignes : personne ne la relit en entier avant chaque
    modification, et c'est exactement comme ca qu'on refait ce qui est deja decide.

    Le 29/08, j'ai reinvente « d'ou vient le code qu'on deploie » alors que D99 et le
    reglage UpdateSource y repondaient depuis longtemps ; j'ai range un reglage de
    l'ordinateur dans chaque copie alors que D33 decrit les couches de configuration ;
    j'ai redefini une fonction qui existait deja. Trois fois le meme defaut : ne pas
    avoir cherche.

    Chercher doit donc couter DIX SECONDES.

        pwsh -File scripts/dev/decisions.ps1 -About "mise a jour deploiement"
        pwsh -File scripts/dev/decisions.ps1 -Number D99
        pwsh -File scripts/dev/decisions.ps1              # tous les titres

    La recherche ignore accents et casse : « deploiement » trouve « déploiement ».
#>
[CmdletBinding()]
param(
    # Un ou plusieurs mots. Une decision ressort si son TITRE ou son TEXTE les contient.
    [string] $About,

    # Le numero d'une decision : affiche son texte entier.
    [string] $Number,

    # Chercher dans le texte, pas seulement dans les titres (plus large, plus bruyant).
    [switch] $Full
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$file = Join-Path $repoRoot 'doc/progress/decisions.md'
if (-not (Test-Path -LiteralPath $file)) {
    Write-Fail (Get-Label 'decisions.fichier-introuvable' $file)
    exit 2
}

# Les accents ne doivent pas faire rater une correspondance : « deploiement » doit
# trouver « déploiement ». On compare des formes sans diacritiques, des deux cotes.
function ConvertTo-Plain {
    param([string]$Text)
    $d = "$Text".Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) }
    }
    return $sb.ToString().ToLowerInvariant()
}

$lines = Get-Content -LiteralPath $file -Encoding UTF8
# Une decision commence par « ## Dnn — titre » et court jusqu'a la suivante.
$entries = @()
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^#{2,3}\s+(D\d+[a-z]*)\s*(?:\(revu\))?\s*[—-]\s*(.+)$') {
        if ($current) { $entries += $current }
        $current = [pscustomobject]@{
            Id = $Matches[1]; Title = $Matches[2].Trim(); Line = $i + 1
            Body = New-Object Collections.Generic.List[string]
        }
    } elseif ($current) {
        $current.Body.Add($lines[$i])
    }
}
if ($current) { $entries += $current }

if ($Number) {
    $cible = @($entries | Where-Object { $_.Id -ieq $Number.Trim() })
    if (-not $cible.Count) {
        Write-Fail (Get-Label 'decisions.numero-inconnu' $Number)
        exit 2
    }
    foreach ($e in $cible) {
        Write-Title ($e.Id + ' — ' + $e.Title)
        Write-Detail (Get-Label 'decisions.ligne' $e.Line)
        $e.Body | ForEach-Object { Write-Host $_ }
    }
    exit 0
}

$retenues = $entries
if ($About) {
    $mots = @(ConvertTo-Plain $About) -split '\s+' | Where-Object { $_ }
    $retenues = @($entries | Where-Object {
        $titre = ConvertTo-Plain $_.Title
        $texte = if ($Full) { ConvertTo-Plain ($_.Body -join ' ') } else { '' }
        $tous = $true
        foreach ($m in $mots) { if (($titre -notlike ('*' + $m + '*')) -and ($texte -notlike ('*' + $m + '*'))) { $tous = $false; break } }
        $tous
    })
}

Write-Title (Get-Label 'decisions.titre')
foreach ($e in $retenues) {
    Write-Host ('{0,-6} {1}' -f $e.Id, $e.Title)
}
Write-Info (Get-Label 'decisions.sur-total' $retenues.Count $entries.Count)
if ($About -and -not $retenues.Count) {
    Write-Detail (Get-Label 'decisions.rien-trouve-full')
}
exit 0
