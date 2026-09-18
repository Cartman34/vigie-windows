# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    system-metrics.ps1 - MEMORY AND PROCESSOR LOAD, ASKED OF WINDOWS DIRECTLY. Loadable alone.

    Why it exists. The Resources card read them through WMI: Win32_OperatingSystem took 0.6 s and Win32_Processor 1.1 s
    on 18/09, for figures Windows hands out in microseconds. The rule: the optimised call that gives the information
    needed (doc/en/agent-working/disciplines.md, section "Wrapping system calls").
#>

if (-not ('VigieSystemMetrics' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class VigieSystemMetrics {
    [StructLayout(LayoutKind.Sequential)]
    public class MemoryStatusEx {
        public uint Length = (uint)Marshal.SizeOf(typeof(MemoryStatusEx));
        public uint MemoryLoad;
        public ulong TotalPhys; public ulong AvailPhys;
        public ulong TotalPageFile; public ulong AvailPageFile;
        public ulong TotalVirtual; public ulong AvailVirtual; public ulong AvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatusEx buffer);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    public static MemoryStatusEx Memory() {
        var status = new MemoryStatusEx();
        return GlobalMemoryStatusEx(status) ? status : null;
    }

    // Busy share of the processors between two readings, in percent; -1 when Windows refuses.
    public static int ProcessorLoad(int sampleMs) {
        long i1, k1, u1, i2, k2, u2;
        if (!GetSystemTimes(out i1, out k1, out u1)) { return -1; }
        System.Threading.Thread.Sleep(sampleMs);
        if (!GetSystemTimes(out i2, out k2, out u2)) { return -1; }
        long idle = i2 - i1;
        long total = (k2 - k1) + (u2 - u1);   // kernel time includes idle time
        if (total <= 0) { return 0; }
        return (int)Math.Round(100.0 * (total - idle) / total);
    }
}
'@
}

# PHYSICAL AND COMMITTED MEMORY, in bytes: TotalPhys, AvailPhys, CommitLimit (physical memory plus page file),
# CommitUsed. $null when Windows refuses.
function Get-MemoryStatus {
    $m = $null
    try { $m = [VigieSystemMetrics]::Memory() } catch { }
    if (-not $m) { return $null }
    return [pscustomobject]@{
        TotalPhys   = [double]$m.TotalPhys
        AvailPhys   = [double]$m.AvailPhys
        CommitLimit = [double]$m.TotalPageFile
        CommitUsed  = [double]($m.TotalPageFile - $m.AvailPageFile)
    }
}

# THE PROCESSOR LOAD, in percent, measured over a short interval; $null when Windows refuses.
function Get-ProcessorLoad {
    param([int]$SampleMs = 250)
    $load = -1
    try { $load = [VigieSystemMetrics]::ProcessorLoad($SampleMs) } catch { }
    if ($load -lt 0) { return $null }
    return $load
}

# THE PROCESS TREE, from one snapshot of Windows (Toolhelp): every process with its parent. Win32_Process gives the same
# in 0.5 to 1 s; the snapshot takes a few milliseconds, which lets the self-watch card run at every refresh.
if (-not ('VigieProcessTree' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigieProcessTree {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ProcessEntry32 {
        public uint Size; public uint Usage; public uint ProcessId; public IntPtr DefaultHeapId; public uint ModuleId;
        public uint Threads; public uint ParentProcessId; public int PriorityClassBase; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string ExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool Process32FirstW(IntPtr snapshot, ref ProcessEntry32 entry);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool Process32NextW(IntPtr snapshot, ref ProcessEntry32 entry);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    // "pid|parent pid|executable" for every process, or null when Windows refuses the snapshot.
    public static string[] Snapshot() {
        const uint SnapProcess = 0x2;
        IntPtr snapshot = CreateToolhelp32Snapshot(SnapProcess, 0);
        if (snapshot == IntPtr.Zero || snapshot == new IntPtr(-1)) { return null; }
        var rows = new List<string>();
        try {
            var entry = new ProcessEntry32();
            entry.Size = (uint)Marshal.SizeOf(typeof(ProcessEntry32));
            if (!Process32FirstW(snapshot, ref entry)) { return null; }
            do { rows.Add(entry.ProcessId + "|" + entry.ParentProcessId + "|" + entry.ExeFile); }
            while (Process32NextW(snapshot, ref entry));
        } finally { CloseHandle(snapshot); }
        return rows.ToArray();
    }
}
'@
}

# THE DESCENDANTS OF A PROCESS: ProcessId, ParentId, Name, for its children, their children, and so on. A process
# whose parent id was reused by a newer process is not taken for a child: it must have started after its parent.
# Empty when Windows refuses the snapshot. Never throws.
function Get-ProcessDescendants {
    param([Parameter(Mandatory)][int]$ProcessId)
    $rows = $null
    try { $rows = [VigieProcessTree]::Snapshot() } catch { }
    if (-not $rows) { return @() }
    $children = @{}
    foreach ($row in $rows) {
        $parts = $row.Split('|')
        $entry = [pscustomobject]@{ ProcessId = [int]$parts[0]; ParentId = [int]$parts[1]; Name = $parts[2] }
        if ($entry.ProcessId -eq $entry.ParentId) { continue }
        if (-not $children.ContainsKey($entry.ParentId)) { $children[$entry.ParentId] = [Collections.Generic.List[object]]::new() }
        $children[$entry.ParentId].Add($entry)
    }
    $started = @{}
    function Get-StartTime([int]$Id) {
        if (-not $started.ContainsKey($Id)) { $t = $null; try { $t = (Get-Process -Id $Id -ErrorAction Stop).StartTime } catch { }; $started[$Id] = $t }
        return $started[$Id]
    }
    $found = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($ProcessId)
    $seen = @{ $ProcessId = $true }
    while ($queue.Count) {
        $parent = $queue.Dequeue()
        if (-not $children.ContainsKey($parent)) { continue }
        $parentStart = Get-StartTime $parent
        foreach ($child in $children[$parent]) {
            if ($seen.ContainsKey($child.ProcessId)) { continue }
            $childStart = Get-StartTime $child.ProcessId
            if ($parentStart -and $childStart -and $childStart -lt $parentStart) { continue }
            $seen[$child.ProcessId] = $true
            $found.Add($child)
            $queue.Enqueue($child.ProcessId)
        }
    }
    return $found.ToArray()
}
