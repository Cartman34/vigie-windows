# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    i18n.ps1 - LES LIBELLÉS VIVENT DANS lang/, PAS DANS LE CODE.
    Aucune dépendance : chargeable sous Windows PowerShell 5.1 comme sous PowerShell 7.

    POURQUOI CE FICHIER EXISTE. Le texte français était écrit à même les scripts. Deux
    conséquences, et la seconde est la vraie : il fallait un BOM sur chaque fichier pour
    que 5.1 ne massacre pas les accents, et surtout aucune deuxième langue n'était
    possible sans réécrire cent fichiers. Les libellés sont des DONNÉES ; ils sortent du
    code.

    LE FORMAT EST DU JSON, pour une seule raison : c'est le seul que PowerShell et le
    navigateur lisent tous les deux sans rien installer. Le front et les scripts
    partagent donc le même fichier, et un libellé ne peut plus diverger entre les deux.

    LE FICHIER EST EN UTF-8 SANS BOM : c'est ce qu'exige la norme JSON, et ce que
    `fetch()` attend côté navigateur. Le vérificateur d'encodage connaît cette règle.

    LE MODE D'ÉCHEC QU'ON REFUSE. Une clé absente qui rendrait une chaîne vide serait
    pire que tout : le message disparaîtrait sans que rien ne le signale. Ici, une clé
    absente rend « [?ma.cle] », visible à l'œil nu, ET part dans le journal. Le
    vérificateur `scripts/dev/check-labels.ps1` interdit d'en livrer une.

    USAGE

        . (Join-Path $repoRoot 'scripts/lib/i18n.ps1')
        Write-Ok (Get-Label 'service.task-registered' $taskName)

    Les trous se notent « {0} », « {1} » : c'est l'opérateur -f de PowerShell, et c'est
    aussi ce que comprend le petit remplaceur du front. Un trou numéroté, et non nommé,
    parce qu'une traduction a le droit de changer l'ORDRE des morceaux.
#>

# La langue en vigueur. Une seule pour l'instant ; le jour où il y en a deux, c'est cette
# variable qui change, et rien d'autre.
$script:LabelLanguage = 'fr'
$script:LabelTable    = $null

function Get-LabelFilePath {
    param([string]$Language = $script:LabelLanguage)
    # Le dossier lang/ est a la racine du depot : deux niveaux au-dessus de scripts/lib/.
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return (Join-Path (Join-Path $root 'lang') ($Language + '.json'))
}

# Charge la table une fois par session. Un fichier de libelles ne change pas en cours
# d'execution ; le relire a chaque appel couterait un acces disque par ligne affichee.
function Import-Labels {
    param([switch]$Force)
    if ($script:LabelTable -and -not $Force) { return $script:LabelTable }
    $file = Get-LabelFilePath
    if (-not (Test-Path -LiteralPath $file)) {
        # ON NE PLANTE PAS ICI. Un script d'installation qui meurt parce qu'il ne trouve
        # pas ses libelles serait absurde : il doit pouvoir dire ce qui ne va pas.
        $script:LabelTable = @{}
        return $script:LabelTable
    }
    $raw = [System.IO.File]::ReadAllText($file, (New-Object System.Text.UTF8Encoding($false)))
    $obj = $raw | ConvertFrom-Json
    $table = @{}
    foreach ($p in $obj.PSObject.Properties) { $table[$p.Name] = [string]$p.Value }
    $script:LabelTable = $table
    return $script:LabelTable
}

<#
    Le libelle d'une cle, ses trous remplis.

        Get-Label 'service.task-registered' 'Vigie - Serveur'

    Une cle absente rend « [?la.cle] » : visible, cherchable, et jamais vide.
#>
function Get-Label {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Position = 1, ValueFromRemainingArguments)][object[]]$Values
    )
    $table = Import-Labels
    if (-not $table.ContainsKey($Key)) {
        return ('[?' + $Key + ']')
    }
    $text = $table[$Key]
    # ZERO N'EST PAS « RIEN ». « if ($Values -and ...) » convertit un tableau d'UN seul
    # element en la valeur de cet element : @(0) vaut donc FAUX, comme @('') et @($false).
    # Consequence constatee le 29/08 : « Demarrage automatique : code {0} » -- le code de
    # retour valait 0, c'est-a-dire la reussite, et c'est exactement la ligne qu'on perdait.
    # On teste le NOMBRE d'elements, jamais leur verite.
    if ($null -ne $Values -and $Values.Count -gt 0) {
        try { return ($text -f $Values) }
        catch {
            # UN TROU MAL COMPTE NE DOIT PAS FAIRE TOMBER LE SCRIPT. On rend le libelle
            # brut, avec sa marque : le verificateur compte les trous, c'est son travail.
            return ($text + ' [!trous]')
        }
    }
    return $text
}

# Les cles reclamees pendant cette execution et introuvables. Sert au verificateur, et a
# un diagnostic quand un message sort en « [?...] ».
