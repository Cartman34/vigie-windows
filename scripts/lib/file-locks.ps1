# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    file-locks.ps1 - WHO HOLDS THIS FILE, ASKED OF WINDOWS DIRECTLY. Loadable alone (no dependency on Pode or common.ps1).

    Why it exists. "The file is in use" is the answer nobody can act on: it names no one. Windows knows the answer and
    has an API for it -- the Restart Manager, the very one installers use to tell you what to close. It gives the
    processes holding a file BY NAME, with their identifier and their start time, without stopping anything and
    without any external tool.

    The rule it applies: name what blocks, and name it clearly (D127). A card that prints a code teaches nothing; a
    card that says "held by PhoneExperienceHost" can be acted on.

    READ ONLY. RmStartSession opens a session, we register the files, we ASK the list, and we close. Nothing is
    restarted, nothing is stopped: the Restart Manager only acts when it is told to, and it never is here.
#>

if (-not ('VigieFileLocks' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigieFileLocks {
    [StructLayout(LayoutKind.Sequential)]
    struct UniqueProcess { public int ProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ProcessInfo {
        public UniqueProcess Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string AppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]  public string ServiceShortName;
        public int ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint handle, int flags, string key);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint handle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint handle, uint fileCount, string[] files, uint appCount,
                                          IntPtr applications, uint serviceCount, string[] services);
    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint handle, out uint needed, ref uint count, [In, Out] ProcessInfo[] info, ref uint reason);

    // [ "pid|name", ... ], or null when Windows refused -- a refusal is not "nobody holds it".
    public static string[] Holders(string[] files) {
        uint handle;
        // The session key is ours and must be unique; a new one per call, since nothing is kept between calls.
        if (RmStartSession(out handle, 0, Guid.NewGuid().ToString("N")) != 0) { return null; }
        try {
            if (RmRegisterResources(handle, (uint)files.Length, files, 0, IntPtr.Zero, 0, null) != 0) { return null; }
            uint needed = 0, count = 0, reason = 0;
            // First call sizes the answer, second fills it -- and the list can grow in between, hence the retry.
            int code = RmGetList(handle, out needed, ref count, null, ref reason);
            for (int attempt = 0; attempt < 3; attempt++) {
                if (code == 0 && needed == 0) { return new string[0]; }
                if (code != 234 && code != 0) { return null; }   // 234 = ERROR_MORE_DATA
                var info = new ProcessInfo[needed];
                count = needed;
                code = RmGetList(handle, out needed, ref count, info, ref reason);
                if (code == 0) {
                    var found = new List<string>();
                    for (int i = 0; i < count; i++) {
                        found.Add(info[i].Process.ProcessId.ToString() + "|" + (info[i].AppName ?? ""));
                    }
                    return found.ToArray();
                }
            }
            return null;
        } finally { RmEndSession(handle); }
    }
}
'@ -ErrorAction SilentlyContinue
}

<#
    IS THIS FILE HELD? Asked the simple way, and it is unambiguous: opening it for exclusive use succeeds, or it does
    not. The Restart Manager is asked only afterwards, to NAME the holder -- on a file nobody holds it answers
    "nothing to report" in a way hard to tell from a refusal, and a doubt is not an answer.
#>
function Test-FileHeld {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'None')
        $stream.Close()
        return $false
    } catch [IO.IOException] { return $true } catch { return $null }
}

<#
    THE PROCESSES HOLDING THESE FILES, named. Returns one entry per holder, or $null when Windows refused to answer --
    which is NOT the same as "nobody holds them", and the caller must keep the difference.
#>
function Get-FileHolders {
    param([Parameter(Mandatory)][string[]]$Path)
    $files = @($Path | Where-Object { $_ })
    # AN EMPTY ARRAY MUST SURVIVE THE RETURN: PowerShell unrolls it into $null, and the caller would then read
    # "Windows refused" where the truth is "nobody holds it". The comma keeps the array whole.
    if (-not $files.Count) { return ,@() }
    # Nothing locked, nothing to name -- and we avoid asking the Restart Manager a question it answers ambiguously.
    $held = @($files | Where-Object { (Test-FileHeld -Path $_) -eq $true })
    if (-not $held.Count) { return ,@() }
    $files = $held
    $raw = $null
    try { $raw = [VigieFileLocks]::Holders($files) } catch { return $null }
    if ($null -eq $raw) { return $null }
    $out = @()
    foreach ($line in $raw) {
        $bits = "$line".Split('|')
        if ($bits.Count -lt 1) { continue }
        $out += [pscustomobject]@{ ProcessId = [int]$bits[0]; Name = $(if ($bits.Count -gt 1) { $bits[1] } else { '' }) }
    }
    return ,$out
}
