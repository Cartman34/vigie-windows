# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- marque une version du produit : ce n'est pas un geste anodin (D65)
# @execution: session   -- le tag s'ecrit dans le depot du DEMANDEUR, sous SON compte
<# An action: it lays the version tag down, inside the repository of the person who asks.

   Intent: give the tag an author. WHY INSIDE THE SESSION. Marking a version also pushes it. But the server app
   runs under a service account: a tag laid by it would have no author, its push would have no credentials, and
   git refuses to write inside a repository that belongs to somebody else (D112).
   Usage: it is called from the Deployment card. The requester's client app, for its part, runs under their
   account, in their repository. It lays the tag and pushes it; the service then only has to build from its
   clone, where the tag

   It returns the number that was laid, so that the archive carries exactly the same one. #>



param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$repo = Get-LocalRepoPath -Backend $backend
if (-not $repo) {
    return @{ message = (Get-Label 'tag-version.aucun-depot'); result = @{ ok = $false } }
}

# NOTHING TO MARK IF THERE IS NOTHING NEW. One tag per deployment only means something if it designates a state
# different from the previous one.
$head = Get-GitCommit -Path $repo
$last = @(Invoke-Git -Path $repo -Arguments @('rev-list', '-1', '--tags') | Select-Object -First 1)[0]
if ($head -and $last -and $head -eq $last) {
    $known = Get-GitVersion -Path $repo
    return @{ message = (Get-Label 'tag-version.deja-marque' $known)
              result   = @{ ok = $true; tag = $known; posed = $false } }
}

$pose = New-DeploymentTag -RepoPath $repo -Push
if (-not $pose.posed) {
    return @{ message = (Get-Label 'tag-version.echec' "$($pose.error)"); result = @{ ok = $false } }
}

# THE LOG SAYS WHETHER IT IS PUBLISHED. It wrote "Version v0.1.67 marked by fhaza" and
# stopped there: five versions stayed local without a word, and the question "is it
# published?" had no written answer anywhere (03/09).
$sort = if ($pose.pushed) { Get-Label 'tag-version.publiee' } else { Get-Label 'tag-version.locale' }
Write-Log -Backend $backend -Name 'app' -Level $(if ($pose.pushed) { 'INFO' } else { 'WARN' }) `
          -Message (Get-Label 'tag-version.journal' $pose.tag (Get-ProcessAccount) $sort)
@{
    message = (Get-Label 'tag-version.pose' $pose.tag $(if ($pose.pushed) { (Get-Label 'tag-version.et-pousse') } else { (Get-Label 'tag-version.local-seulement') }))
    result  = @{ ok = $true; tag = $pose.tag; posed = $true; pushed = $pose.pushed }
}
