# @author Florent HAZARD <f.hazard@sowapps.com>
<# TOOL: the real notification API, reached through a Windows PowerShell host.

   The API lives in Windows -- nothing to install -- but its projection was removed from
   .NET 5 onwards, so PowerShell 7 cannot see it while Windows PowerShell still can. This
   rank borrows that host for the length of one call.

   THE TEXT NEVER TRAVELS ON THE COMMAND LINE. It goes through an XML file, and the file's
   path through the environment, so nothing the user's machine names -- an apostrophe in a
   title, an ampersand in an application name -- can break the command being run.

   The machine's execution policy is not this rank's business either: a policy applies to
   script FILES, and what is passed here is a command, never a file.

   Rank 20 does the same thing in-process. This one stays because it depends on nothing but
   Windows PowerShell, which every Windows carries. #>
param($Notification, $Context)

$xml = Get-VigieToastXml -Subject "$($Notification.Subject)" -Body "$($Notification.Body)" `
                        -Image (Get-VigieToastImage -TrayRoot $Context.TrayRoot -State "$($Notification.State)") `
                        -Long:([int]$Notification.Duration -ge 10000)
if (-not $xml) { return $false }

$file = Get-VarPath -Backend $Context.TrayRoot -Kind 'run' -File 'toast.xml'
try { [IO.File]::WriteAllText($file, $xml, (New-Object Text.UTF8Encoding $false)) } catch { return $false }

$env:VIGIE_TOAST_XML = $file
$env:VIGIE_TOAST_AUMID = $Context.Aumid
$command = '[void][Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime];' +
           '[void][Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,ContentType=WindowsRuntime];' +
           'try{$d=New-Object Windows.Data.Xml.Dom.XmlDocument;' +
           '$d.LoadXml([IO.File]::ReadAllText($env:VIGIE_TOAST_XML));' +
           '[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($env:VIGIE_TOAST_AUMID).Show(' +
           '(New-Object Windows.UI.Notifications.ToastNotification $d));exit 0}catch{exit 1}'
try {
    $host2 = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
                           -ArgumentList @('-NoProfile', '-STA', '-Command', $command)
    # WE WAIT, briefly. Without it a failure inside the child would look like a success and
    # the notification would be lost with no rank left to try.
    if (-not $host2.WaitForExit(5000)) { return $false }
    return ($host2.ExitCode -eq 0)
} catch {
    return $false
}
