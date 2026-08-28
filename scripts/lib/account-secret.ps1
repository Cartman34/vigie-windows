<#
    account-secret.ps1 - Le SECRET DU COMPTE : le poser, le lire, et refuser de s'y fier
    quand ses droits ne tiennent plus. Chargeable seul (aucune dependance a Pode).

    POURQUOI CE FICHIER EXISTE. Un secret que tout le monde peut lire n'est pas un secret,
    et aucun emplacement n'est sur PAR HERITAGE -- mesure sur la machine du 28/08 :

      C:\ProgramData          BUILTIN\Utilisateurs a lecture ET ecriture
      %LOCALAPPDATA%          le compte, SYSTEM, Administrateurs -- ET un groupe ajoute
                              par un outil tiers, en lecture

    Le second cas est le plus instructif : ce profil est cense etre prive, et il ne
    l'etait deja plus. On ne se fie donc a aucun heritage : l'ACL est POSEE, et
    REVERIFIEE a chaque lecture. Un ecart vaut compromission, pas avertissement.

    Ce qui est autorise, et rien d'autre :
      - le compte proprietaire  : lecture et ecriture
      - SYSTEM                  : total (le service en aura besoin)
      - Administrateurs         : total (irreductible sous Windows, et sans consequence :
                                  un administrateur peut deja tout faire)

    Conception : doc/progress/targeting/multi-account-server.md, section C7.
#>

# Les identites autorisees, par leur SID -- jamais par leur nom, qui change avec la langue
# de Windows (« Administrateurs » / « Administrators »).
$script:SecretAllowedSids = @(
    'S-1-5-18',        # SYSTEM
    'S-1-5-32-544'     # Administrateurs (groupe integre)
)

function Get-AccountSecretPath {
    param(
        # Racine des donnees du compte. Par defaut : celles du compte courant.
        [string]$VarRoot = (Get-VarRoot)
    )
    Join-Path (Join-Path $VarRoot 'secrets') 'account.secret'
}

# Pose l'ACL VOULUE sur un dossier : heritage coupe, et seulement ce qu'on autorise.
function Set-SecretFolderAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        # SID du compte proprietaire du secret.
        [Parameter(Mandatory)][string]$OwnerSid
    )
    $acl = Get-Acl -LiteralPath $Path
    # L'HERITAGE EST COUPE, et les regles heritees ne sont PAS recopiees : c'est
    # exactement ce qui laissait passer un groupe ajoute par un outil tiers.
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }

    # LES DRAPEAUX D'HERITAGE N'EXISTENT QUE SUR UN DOSSIER. Les poser sur un fichier fait
    # rejeter la regle en silence : le fichier se retrouve avec une ACL protegee et VIDE,
    # que plus personne ne peut lire -- pas meme son proprietaire. Constate a l'epreuve
    # le 28/08, et c'est precisement le genre de defaut qu'une relecture ne voit pas.
    $isFile  = Test-Path -LiteralPath $Path -PathType Leaf
    $inherit = if ($isFile) { [System.Security.AccessControl.InheritanceFlags]::None }
               else { [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    $none    = [System.Security.AccessControl.PropagationFlags]::None
    $allow   = [System.Security.AccessControl.AccessControlType]::Allow

    foreach ($sid in (@($OwnerSid) + $script:SecretAllowedSids)) {
        try {
            $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $rights = if ($sid -eq $OwnerSid) {
                [System.Security.AccessControl.FileSystemRights]'Read, Write, Delete'
            } else {
                [System.Security.AccessControl.FileSystemRights]::FullControl
            }
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $id, $rights, $inherit, $none, $allow)))
        } catch { }
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Les droits sont-ils encore ceux qu'on a poses ? Rend $null si oui, sinon ce qui cloche.
#
# VERIFIER A L'ECRITURE NE SUFFIT PAS : les droits d'un fichier changent apres sa
# creation -- un outil, une strategie de groupe, une main humaine. Un secret dont on ne
# controle les droits qu'une fois est un secret dont on ignore l'etat.
function Test-SecretAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid
    )
    if (-not (Test-Path -LiteralPath $Path)) { return "le secret n'existe pas" }
    try {
        $acl = Get-Acl -LiteralPath $Path
    } catch { return ("droits illisibles : " + $_.Exception.Message) }

    if (-not $acl.AreAccessRulesProtected) { return "l'heritage n'est pas coupe : des droits peuvent arriver du dossier parent" }

    # UNE ACL VIDE N'EST PAS UNE ACL SURE : c'est un fichier que personne ne peut lire.
    # Le premier essai a produit exactement ca, et la verification l'avait laisse passer
    # parce qu'elle ne cherchait que les intrus.
    $ownerCanRead = $false
    $allowed = @($OwnerSid) + $script:SecretAllowedSids
    foreach ($rule in $acl.Access) {
        $ruleSid = try { $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
                   catch { '' }
        if ($ruleSid -eq $OwnerSid -and
            ($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read)) {
            $ownerCanRead = $true
        }
    }
    if (-not $ownerCanRead) { return "le compte propriétaire n'a plus le droit de lire son propre secret" }

    foreach ($rule in $acl.Access) {
        $sid = try { $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
               catch { "$($rule.IdentityReference)" }
        if ($allowed -notcontains $sid) {
            return ("un tiers y a acces : " + $rule.IdentityReference)
        }
    }
    return $null
}

# Ecrit un secret neuf, avec ses droits. Rend le secret en clair -- a l'appelant de ne pas
# le journaliser.
function New-AccountSecret {
    param(
        [string]$VarRoot = (Get-VarRoot),
        [string]$OwnerSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    )
    $file = Get-AccountSecretPath -VarRoot $VarRoot
    $dir  = Split-Path $file -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-SecretFolderAcl -Path $dir -OwnerSid $OwnerSid

    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    [System.IO.File]::WriteAllText($file, $secret, (New-Object System.Text.UTF8Encoding($false)))
    Set-SecretFolderAcl -Path $file -OwnerSid $OwnerSid
    return $secret
}

# Lit le secret APRES avoir verifie ses droits. Rend $null si le fichier manque ; LEVE si
# les droits ne tiennent plus -- c'est un incident, pas un cas nominal.
function Get-AccountSecret {
    param(
        [string]$VarRoot = (Get-VarRoot),
        [string]$OwnerSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value,
        # Recreer le secret s'il manque.
        [switch]$Create
    )
    $file = Get-AccountSecretPath -VarRoot $VarRoot
    if (-not (Test-Path -LiteralPath $file)) {
        if ($Create) { return (New-AccountSecret -VarRoot $VarRoot -OwnerSid $OwnerSid) }
        return $null
    }
    $wrong = Test-SecretAcl -Path $file -OwnerSid $OwnerSid
    if ($wrong) {
        # COMPROMIS : on ne s'en sert pas, on le remplace, et on le dit. Continuer avec un
        # secret qu'un tiers a pu lire reviendrait a n'avoir aucun secret du tout.
        throw ("Secret de compte compromis (" + $wrong + ") : il doit être révoqué et réémis.")
    }
    return ([System.IO.File]::ReadAllText($file)).Trim()
}

# L'empreinte, c'est tout ce que le serveur a besoin de garder : comparer une empreinte
# suffit a reconnaitre, et lire la table du serveur ne donne alors rien d'exploitable.
function Get-SecretFingerprint {
    param([Parameter(Mandatory)][string]$Secret)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Secret))
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
