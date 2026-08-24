<#
.SYNOPSIS
    Execute TOUTES les sondes et verifie les invariants du contrat.

.DESCRIPTION
    POURQUOI CE SCRIPT EXISTE
    Le parseur PowerShell valide la SYNTAXE, pas l'execution. Un parametre passe deux fois
    (« parameter 'FixAction' is specified more than once ») franchit le parseur sans un
    mot, puis fait echouer la sonde a l'execution : la carte disparait du tableau de bord
    sans que rien ne le signale. C'est arrive le 2026-08-24 sur la sonde reseau, livree et
    annoncee comme faite.

    Ce script execute donc chaque sonde pour de vrai, et verifie les regles que le projet
    s'est donnees (D49) -- celles qui, jusqu'ici, ne tenaient que par la vigilance :

      1. la sonde rend au moins un module ;
      2. le statut d'un module ne depasse jamais celui de son pire champ ;
      3. tout champ en avertissement ou en erreur propose une resolution OU un guide ;
      4. tout champ porte une aide ;
      5. toute action citee par un champ (FixAction) existe vraiment ;
      6. aucun libelle au repos ne porte de points de suspension (reserves a l'execution).

    LECTURE SEULE : aucune action n'est declenchee, rien n'est ecrit hors du cache des
    sondes elles-memes.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1

.NOTES
    Codes de retour : 0 = tout est conforme ; 1 = au moins un manquement.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

$probesDir = Join-Path $repoRoot 'apps/backend-pode/probes'
$actionsDir = Join-Path $repoRoot 'apps/backend-pode/actions'
$actionsConnues = @(Get-ChildItem -Path $actionsDir -Filter '*.action.ps1' -File |
                    ForEach-Object { $_.Name -replace '\.action\.ps1$', '' })

$rang = @{ ok = 0; neutral = 0; warn = 1; error = 2 }
$manquements = @()
$modules = 0

foreach ($f in (Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -File | Sort-Object FullName)) {
    $rendus = $null
    try { $rendus = & $f.FullName }
    catch {
        $manquements += "{0} : la sonde LEVE une erreur -- {1}" -f $f.Name, $_.Exception.Message
        continue
    }
    if (-not $rendus) { $manquements += "$($f.Name) : la sonde ne rend AUCUN module"; continue }

    foreach ($m in @($rendus)) {
        $modules++
        $pire = 0
        foreach ($champ in @($m.fields)) {
            $st = "$($champ.status)"
            if ($rang.ContainsKey($st) -and $rang[$st] -gt $pire) { $pire = $rang[$st] }

            if (-not $champ.help) {
                $manquements += "{0} / {1} : le champ n'a pas d'aide" -f $m.id, $champ.key
            }
            if (($st -eq 'warn' -or $st -eq 'error') -and -not $champ.fixAction -and -not $champ.guide) {
                $manquements += "{0} / {1} : en '{2}' sans resolution ni guide (D49)" -f $m.id, $champ.key, $st
            }
            if ($champ.fixAction -and $actionsConnues -notcontains "$($champ.fixAction)") {
                $manquements += "{0} / {1} : renvoie a l'action inconnue '{2}'" -f $m.id, $champ.key, $champ.fixAction
            }
        }
        $stMod = "$($m.status)"
        if ($rang.ContainsKey($stMod) -and $rang[$stMod] -gt $pire) {
            $manquements += "{0} : statut '{1}' alors que le pire champ est plus bas (D49)" -f $m.id, $stMod
        }
        foreach ($a in @($m.actions)) {
            if ("$($a.label)" -match '…\s*$') {
                $manquements += "{0} / {1} : libelle au repos avec points de suspension (D50)" -f $m.id, $a.id
            }
        }
    }
}

Write-Host ("Sondes executees : {0} module(s)" -f $modules)
if ($manquements.Count -eq 0) {
    Write-Host "Tous les invariants sont respectes." -ForegroundColor Green
    exit 0
}
Write-Host ("{0} manquement(s) :" -f $manquements.Count) -ForegroundColor Red
$manquements | ForEach-Object { Write-Host "  - $_" }
exit 1
