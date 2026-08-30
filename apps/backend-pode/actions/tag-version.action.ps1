# @droits: admin   -- marque une version du produit : ce n'est pas un geste anodin (D65)
# @execution: session   -- le tag s'ecrit dans le depot du DEMANDEUR, sous SON compte
<# Action : poser le tag de version, dans le depot de la personne qui demande.

   POURQUOI DANS LA SESSION. Le deploiement marque une version et la pousse -- c'est la
   regle, et elle ne change pas. Mais l'app serveur tourne sous un compte de service :
   un tag pose par lui n'aurait pas d'auteur, son push n'aurait pas d'identifiants, et
   git refuse d'ecrire dans un depot qui appartient a quelqu'un d'autre (D112).

   L'app cliente du demandeur, elle, tourne sous son compte, dans son depot. Elle pose
   le tag et le pousse ; le service n'a plus qu'a fabriquer depuis son clone, ou le tag
   apparaitra au prochain fetch.

   Rend le numero pose, pour que l'archive porte exactement le meme. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$repo = Get-LocalRepoPath -Backend $backend
if (-not $repo) {
    return @{ message = (Get-Label 'tag-version.aucun-depot'); result = @{ ok = $false } }
}

# RIEN A MARQUER S'IL N'Y A RIEN DE NEUF. Un tag par deploiement n'a de sens que s'il
# designe un etat different du precedent.
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

Write-Log -Backend $backend -Name 'app' -Message (Get-Label 'tag-version.journal' $pose.tag (Get-ProcessAccount))
@{
    message = (Get-Label 'tag-version.pose' $pose.tag $(if ($pose.pushed) { (Get-Label 'tag-version.et-pousse') } else { (Get-Label 'tag-version.local-seulement') }))
    result  = @{ ok = $true; tag = $pose.tag; posed = $true; pushed = $pose.pushed }
}
