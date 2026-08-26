# @droits: admin   -- lit dans le profil des autres comptes : Windows exige l'elevation (D65)
# @libelle: Details des comptes | immediate | info   -- affiche quand un champ cite cette action (D66)
<# Action : le detail des comptes de la machine.

   La carte dit l'essentiel d'un coup d'oeil (qui, Vigie ou non, quel type) ; ce detail
   repond aux questions suivantes : quand chacun s'est-il connecte pour la derniere fois,
   lesquels dorment, et quel poids font leurs donnees Vigie.

   LECTURE SEULE. Reserve a un administrateur, comme toute lecture dans le profil d'autrui. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

# Seuil de « compte dormant » : une constante, pas un reglage -- personne n'a demande
# a le regler, et 90 jours sans session est un repere universel.
$dormant = 90

$lignes = @()
$dormants = 0
foreach ($c in (Get-VigieAccounts | Sort-Object name)) {
    $depuis = 'jamais connecté'
    if ($c.lastLogon) {
        try {
            $j = [int]((Get-Date) - [datetime]$c.lastLogon).TotalDays
            $depuis = if ($j -le 0) { "connecté aujourd'hui" } else { "dernière session il y a $j jour(s)" }
            if ($j -ge $dormant) { $dormants++; $depuis += " — dormant" }
        } catch { }
    }

    $donnees = 'aucune donnée Vigie'
    try {
        $var = Join-Path (Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local\Sowapps\Vigie') 'var'
        if (Test-Path -LiteralPath $var) {
            $f = @(Get-ChildItem -LiteralPath $var -File -Recurse -ErrorAction SilentlyContinue)
            $taille = ($f | Measure-Object Length -Sum).Sum
            $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            $donnees = "{0} de données Vigie, dernière activité {1}" -f (Format-ByteSize ([long]$taille)),
                       $(if ($recent) { $recent.ToString('dd/MM/yyyy HH:mm') } else { 'inconnue' })
        }
    } catch { $donnees = 'données illisibles' }

    $qualites = @()
    $qualites += $(if ($c.admin) { 'administrateur' } else { 'standard' })
    $qualites += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    if ($c.technical) { $qualites += 'compte technique (pas de profil humain)' }
    if ($c.current)   { $qualites += 'compte en cours' }

    $lignes += ("{0}`n   {1}`n   {2}`n   {3}" -f $c.name, ($qualites -join ' · '), $depuis, $donnees)
}

$entete = "Comptes de cet ordinateur"
if ($dormants -gt 0) { $entete += " ($dormants dormant(s) depuis plus de $dormant jours)" }

$detail = ($entete, '') + $lignes + ('',
    "Pour relire les journaux de l'un d'eux : scripts/vigie-diag-compte.ps1 -Compte <nom>",
    "Pour choisir qui a Vigie : Paramètres > Utilisateurs.")

@{
    message = ("Détail de " + (@(Get-VigieAccounts).Count) + " compte(s).")
    result  = @{ ok = $true; detail = ($detail -join [Environment]::NewLine) }
}
