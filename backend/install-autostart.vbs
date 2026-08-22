Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\install-autostart.ps1""", 0, False
