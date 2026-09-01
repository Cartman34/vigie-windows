# @author Florent HAZARD <f.hazard@sowapps.com>
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

<#
    LES REGLES D'UNE ACL, PAR UN SEUL CHEMIN.

    Windows expose ces regles de deux facons, et elles ne disent pas la meme chose :
    « $acl.Access » rend parfois une collection VIDE sur un descripteur pourtant complet
    -- constate le 28/08, cote serveur, pendant que la meme lecture depuis une session
    ordinaire montrait bien les trois regles. Le controle de securite en concluait que le
    proprietaire ne pouvait plus lire son propre secret, et refusait tout.

    On enveloppe donc l'appel systeme au lieu de le repeter. GetAccessRules demande
    explicitement les regles, heritees comprises, et les rend traduites en SID. Un seul
    point d'entree, un seul comportement -- et le jour ou Windows change d'avis, un seul
    endroit a corriger.
#>
function Get-AclAccessRules {
    param([Parameter(Mandatory)]$Acl)
    return @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
}

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
    # ON N'ECRIT QUE LA SECTION DES DROITS. Un descripteur de securite en porte trois :
    # les droits, le proprietaire, et l'audit. Set-Acl les ecrit toutes -- et poser
    # l'audit exige le privilege SeSecurityPrivilege, qu'un processus non eleve n'a pas.
    # Les droits etaient bien appliques, mais Windows criait a chaque fois ; la ou
    # ErrorActionPreference vaut « Stop », ce cri devient une erreur fatale sur une
    # operation qui a pourtant reussi.
    #
    # GetAccessControl/SetAccessControl avec la section « Access » ne touchent que les
    # droits, et ne demandent donc rien de particulier.
    $item = Get-Item -LiteralPath $Path -Force
    $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl(
                $item, [System.Security.AccessControl.AccessControlSections]::Access)
    # L'HERITAGE EST COUPE, et les regles heritees ne sont PAS recopiees : c'est
    # exactement ce qui laissait passer un groupe ajoute par un outil tiers.
    $acl.SetAccessRuleProtection($true, $false)
    # On enumere par SID : « $acl.Access » rend des entrees nulles sur un descripteur
    # charge section par section, et RemoveAccessRule refuse alors de travailler.
    foreach ($rule in (Get-AclAccessRules -Acl $acl)) { [void]$acl.RemoveAccessRule($rule) }

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
    [System.IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
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

    if (-not $acl.AreAccessRulesProtected) { return "l'héritage n'est pas coupé : des droits peuvent arriver du dossier parent" }

    # ON ENUMERE PAR SID, JAMAIS PAR « $acl.Access ».
    #
    # Selon le contexte, « $acl.Access » rend une collection VIDE alors que le fichier
    # porte bien ses regles : constate le 28/08, le serveur refusait tout secret en
    # disant « le proprietaire ne peut plus lire », pendant que la meme verification
    # passait depuis une session ordinaire sur le meme fichier. Une collection vide
    # ressemble a « aucun droit » -- le pire des faux positifs pour un controle de
    # securite, puisqu'il crie a la compromission sur une installation saine.
    #
    # GetAccessRules demande explicitement les regles, heritees comprises, et les rend
    # traduites en SID : plus de collection vide, et plus de traduction a faire nous-memes.
    $rules = Get-AclAccessRules -Acl $acl

    # UNE ACL VIDE N'EST PAS UNE ACL SURE : c'est un fichier que personne ne peut lire.
    # Le premier essai a produit exactement ca, et la verification l'avait laisse passer
    # parce qu'elle ne cherchait que les intrus.
    $ownerCanRead = $false
    $allowed = @($OwnerSid) + $script:SecretAllowedSids
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -eq $OwnerSid -and
            ($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read)) {
            $ownerCanRead = $true
        }
    }
    if (-not $ownerCanRead) {
        # UN REFUS DE SECURITE DOIT DIRE CE QU'IL A VU. Sans l'ACL constatee, il faut
        # deviner -- et on ne devine pas sur un incident de securite.
        $vues = @($rules | ForEach-Object { $_.IdentityReference.Value + '=' + $_.FileSystemRights })
        return ("le compte propriétaire n'a plus le droit de lire son propre secret [attendu " +
                $OwnerSid + " ; vu " + ($vues -join ' | ') + "]")
    }

    foreach ($rule in $rules) {
        if ($allowed -notcontains $rule.IdentityReference.Value) {
            return ("un tiers y a accès : " + $rule.IdentityReference.Value)
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
