# @droits: admin   -- lit dans le profil du compte de service : Windows exige l'elevation (D65)
<# Action : rend la FIN d'un journal de Vigie, en texte.

   POURQUOI. Les journaux de l'app serveur vivent dans le profil du compte de service :
   depuis une session ordinaire, meme la lecture est refusee. Quand une operation echoue,
   la carte dit desormais POURQUOI -- mais pour comprendre ce qui a mene la, il faut le
   journal, et il etait illisible autrement qu'en elevant une console a la main. C'est
   exactement le genre de detour que Vigie doit supprimer : elle est elevee, elle voit,
   on lui demande.

   CE QU'ELLE ACCEPTE DE LIRE. Uniquement un fichier situe sous le dossier des journaux de
   Vigie, resolu puis VERIFIE : un nom de fichier ne devient jamais un chemin quelconque.
   Elle rend les dernieres lignes, pas le fichier entier -- un journal d'installation fait
   des centaines de lignes et la reponse voyage en JSON.

   Parametres : name = nom du fichier (ou son chemin complet sous var/log) ;
                lines = combien de lignes de la fin (defaut 120, plafond 600). #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$logDir = Get-VarPath -Backend $backend -Kind 'log'
$name = if ($Params -and $Params.name) { "$($Params.name)" } else { '' }
$count = 120
if ($Params -and $Params.lines) { try { $count = [int]$Params.lines } catch { } }
if ($count -lt 1) { $count = 1 }
if ($count -gt 600) { $count = 600 }

# SANS NOM, ON REND LA LISTE : c'est la premiere question qu'on se pose.
if (-not $name) {
    $latest = @(Get-ChildItem -LiteralPath $logDir -File -Recurse -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 30 |
                 ForEach-Object { $_.FullName.Substring($logDir.Length).TrimStart([char]92) + '  (' +
                                  (Format-ByteSize -Bytes $_.Length) + ', ' + $_.LastWriteTime.ToString('s') + ')' })
    return @{ message = "$($latest.Count) journal(aux) récent(s)."
              result  = @{ ok = $true; dir = $logDir; files = $latest } }
}

# LE CHEMIN EST RESOLU PUIS CONFINE. Un nom ne doit jamais pouvoir sortir de var/log.
$wanted = if ([IO.Path]::IsPathRooted($name)) { $name } else { Join-Path $logDir $name }
$full = $null
try { $full = (Resolve-Path -LiteralPath $wanted -ErrorAction Stop).Path } catch { }
$root = (Resolve-Path -LiteralPath $logDir).Path
if (-not $full -or -not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
    return @{ message = "Journal introuvable, ou hors du dossier des journaux : $name"
              result  = @{ ok = $false } }
}

$tail = @()
try { $tail = @(Get-Content -LiteralPath $full -Encoding UTF8 -Tail $count -ErrorAction Stop) }
catch { return @{ message = "Lecture impossible : $($_.Exception.Message)"; result = @{ ok = $false } } }

@{
    message = "$($tail.Count) dernière(s) ligne(s) de $([IO.Path]::GetFileName($full))."
    result  = @{ ok = $true; path = $full; lines = $tail }
}
