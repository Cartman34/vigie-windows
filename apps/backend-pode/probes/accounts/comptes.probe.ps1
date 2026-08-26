<# Sonde : les COMPTES de cet ordinateur. LECTURE SEULE.

   Repond a une question d'administrateur : qui a un compte ici, qui a Vigie, et depuis
   quand chacun ne s'est pas connecte.

   CE QU'ELLE MONTRE DEPEND DE QUI REGARDE (D65) : le detail des autres comptes n'apparait
   que si Vigie tourne en administrateur. Un compte standard voit sa propre ligne et le
   nombre de comptes -- ce que Windows lui laisse voir de toute facon -- pas l'etat des
   donnees des autres. Vigie ne montre rien de plus que Windows.

   La GESTION (activer/retirer Vigie pour un compte) n'est pas ici : elle vit dans
   Parametres > Utilisateurs, et le bouton de la carte y mene. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$dormant = [int](Get-ModuleSetting -Unit 'accounts' -Key 'DormantDays')
if (-not $dormant) { $dormant = 90 }

$eleve   = [bool](Test-IsElevated)
$comptes = @(Get-VigieAccounts)
$moi     = @($comptes | Where-Object { $_.current })[0]
$avec    = @($comptes | Where-Object { $_.enabled })

$fields = @()

# 1) Le compte qui regarde : toujours visible, quel que soit le niveau de droits.
if ($moi) {
    $fields += New-Field -Key 'me' -Label 'Votre compte' `
        -Value ($moi.name + $(if ($moi.admin) { ' (administrateur)' } else { ' (standard)' })) `
        -Kind 'text' -Status 'neutral' `
        -Help "Le compte Windows avec lequel Vigie tourne en ce moment, et ce que Windows lui accorde."
}

$fields += New-Field -Key 'count' -Label 'Comptes sur la machine' -Value ($comptes.Count) -Kind 'number' -Status 'neutral' `
    -Help "Nombre de comptes Windows actifs sur cet ordinateur."

$fields += New-Field -Key 'withVigie' -Label 'Comptes avec Vigie' -Value ($avec.Count) -Kind 'number' -Status 'neutral' `
    -Help "Comptes pour lesquels Vigie demarre a l'ouverture de session. Reglable dans Parametres > Utilisateurs." `
    -Guide (@($comptes | ForEach-Object {
        "{0} {1}{2}" -f $(if ($_.enabled) { '[x]' } else { '[ ]' }), $_.name, $(if ($_.admin) { ' - administrateur' } else { '' })
    }) -join [Environment]::NewLine)

# 2) Le detail des AUTRES comptes : reserve a un Vigie eleve.
$autres = @($comptes | Where-Object { -not $_.current })
if (-not $eleve) {
    $fields += New-Field -Key 'others' -Label 'Autres comptes' -Value ("$($autres.Count) (detail masque)") -Kind 'text' -Status 'neutral' `
        -Help "Le detail des autres comptes demande un Vigie lance en administrateur : Windows protege les profils, et Vigie ne contourne pas cette regle."
} else {
    $lignes = @()
    $dormants = 0
    foreach ($c in $autres) {
        $depuis = '-'
        if ($c.lastLogon) {
            try {
                $j = [int]((Get-Date) - [datetime]$c.lastLogon).TotalDays
                $depuis = if ($j -le 0) { "aujourd'hui" } else { "il y a $j j" }
                if ($j -ge $dormant) { $dormants++ }
            } catch { }
        } else { $depuis = 'jamais' }

        # Etat des donnees Vigie de ce compte : present ? actif quand ?
        $etatVigie = 'pas de donnees'
        try {
            $var = Join-Path (Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local\Vigie') 'var'
            if (Test-Path -LiteralPath $var) {
                $f = @(Get-ChildItem -LiteralPath $var -File -Recurse -ErrorAction SilentlyContinue)
                $taille = ($f | Measure-Object Length -Sum).Sum
                $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                $etatVigie = "{0}, actif {1}" -f (Format-ByteSize ([long]$taille)), $(if ($recent) { $recent.ToString('dd/MM/yyyy HH:mm') } else { '-' })
            }
        } catch { $etatVigie = 'illisible' }

        $lignes += ,@($c.name,
                      $(if ($c.admin) { 'administrateur' } else { 'standard' }),
                      $(if ($c.enabled) { 'oui' } else { 'non' }),
                      $depuis,
                      $etatVigie)
    }
    $valeur = if ($autres.Count -eq 0) { 'aucun' } else { "$($autres.Count)" + $(if ($dormants -gt 0) { ", dont $dormants dormant(s)" } else { '' }) }
    $fields += New-Field -Key 'others' -Label 'Autres comptes' -Value $valeur -Kind 'text' -Status 'neutral' `
        -Help "Les autres comptes de la machine : leur type, s'ils ont Vigie, leur derniere ouverture de session et le poids de leurs donnees Vigie." `
        -Guide "Pour relire les journaux d'un de ces comptes : scripts/vigie-diag-compte.ps1 -Compte <nom> (lecture seule, elevation demandee)." `
        -Table $(if ($lignes.Count) { @{ columns = @('Compte', 'Type', 'Vigie', 'Derniere session', 'Donnees Vigie'); rows = $lignes } } else { $null })
}

New-ModuleObject -Id 'accounts' -Theme 'accounts' -Label 'Comptes' -Status 'ok' -Fields $fields -Actions @(
    New-Action -Id 'open-users-settings' -Label 'Gerer les comptes' -Kind 'dialog' -Severity 'info' `
        -Help "Ouvre Parametres > Utilisateurs : choisir les comptes avec lesquels Vigie demarre."
)
