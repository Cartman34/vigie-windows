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

# THE PARENT OF A PROCESS, from the same snapshot: its id, or 0. Win32_Process took 0.47 s for this one number (18/09).
function Get-ParentProcessId {
    param([Parameter(Mandatory)][int]$ProcessId)
    $rows = $null
    try { $rows = [VigieProcessTree]::Snapshot() } catch { }
    foreach ($row in @($rows)) {
        $parts = "$row".Split('|')
        if ([int]$parts[0] -eq $ProcessId) { return [int]$parts[1] }
    }
    return 0
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

# WHEN WINDOWS STARTED, in UTC, from the milliseconds elapsed since (sleep included, like Win32_OperatingSystem's
# LastBootUpTime). Measured 18/09: the same instant within a second, in no time instead of 0.57 s through WMI.
function Get-BootTime {
    return [datetime]::UtcNow.AddMilliseconds(-[double][Environment]::TickCount64)
}

# THE BYTES READ AND WRITTEN BY EVERY PROCESS, from one call to the kernel (SystemProcessInformation). Win32_Process
# gives the same counters in 0.55 s; this call needs no right on the processes it describes, protected ones included.
# The offsets are those of SYSTEM_PROCESS_INFORMATION on 64-bit Windows, checked against Win32_Process on 18/09.
if (-not ('VigieProcessIo' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigieProcessIo {
    [DllImport("ntdll.dll")]
    static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returned);

    // pid -> bytes read plus bytes written since the process started; null when the kernel refuses.
    public static Dictionary<int, double> Transfers() {
        if (IntPtr.Size != 8) { return null; }
        const int SystemProcessInformation = 5;
        int length = 1 << 20;
        for (int attempt = 0; attempt < 6; attempt++) {
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                int returned;
                int status = NtQuerySystemInformation(SystemProcessInformation, buffer, length, out returned);
                if (status == unchecked((int)0xC0000004)) { length = Math.Max(length * 2, returned + 65536); continue; }
                if (status != 0) { return null; }
                var result = new Dictionary<int, double>();
                int offset = 0;
                while (true) {
                    IntPtr entry = IntPtr.Add(buffer, offset);
                    int pid = (int)Marshal.ReadInt64(entry, 80);
                    double read = Marshal.ReadInt64(entry, 232);
                    double written = Marshal.ReadInt64(entry, 240);
                    result[pid] = read + written;
                    int next = Marshal.ReadInt32(entry, 0);
                    if (next == 0) { break; }
                    offset += next;
                }
                return result;
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        return null;
    }
}
'@
}

# BYTES READ AND WRITTEN PER PROCESS: a hashtable pid -> bytes, empty when the kernel refuses. Never throws.
function Get-ProcessTransferBytes {
    $table = @{}
    try {
        $raw = [VigieProcessIo]::Transfers()
        if ($raw) { foreach ($key in $raw.Keys) { $table[[int]$key] = [double]$raw[$key] } }
    } catch { }
    return $table
}

# PERFORMANCE COUNTERS, ASKED OF PDH DIRECTLY. Get-Counter took 6.3 s for '\GPU Engine(*)\Utilization Percentage' (867
# instances) and 1 s for each GPU memory counter on 18/09, a second of it an interval it waits on its own. Here the
# caller chooses when the two readings a rate needs are taken -- the gaming card already waits 900 ms between its
# two snapshots -- and each reading costs milliseconds. English counter paths: they do not depend on the language.
if (-not ('VigiePdh' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class VigiePdh : IDisposable {
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhOpenQueryW(string dataSource, IntPtr userData, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhAddEnglishCounterW(IntPtr query, string path, IntPtr userData, out IntPtr counter);
    [DllImport("pdh.dll")]
    static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhGetFormattedCounterArrayW(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr buffer);
    [DllImport("pdh.dll")]
    static extern uint PdhCloseQuery(IntPtr query);

    const uint FormatDouble = 0x00000200;
    const uint FormatNoCap100 = 0x00008000;
    const uint MoreData = 0x800007D2;

    IntPtr query;
    readonly List<IntPtr> counters = new List<IntPtr>();

    public VigiePdh() {
        if (PdhOpenQueryW(null, IntPtr.Zero, out query) != 0) { query = IntPtr.Zero; }
    }

    // The index of the counter, or -1 when this computer does not have it.
    public int Add(string path) {
        if (query == IntPtr.Zero) { return -1; }
        IntPtr counter;
        if (PdhAddEnglishCounterW(query, path, IntPtr.Zero, out counter) != 0) { return -1; }
        counters.Add(counter);
        return counters.Count - 1;
    }

    public bool Collect() { return query != IntPtr.Zero && PdhCollectQueryData(query) == 0; }

    // Instance names and values of one counter at the last reading; an instance whose value is not valid is left out.
    public KeyValuePair<string, double>[] Read(int index) {
        var result = new List<KeyValuePair<string, double>>();
        if (index < 0 || index >= counters.Count) { return result.ToArray(); }
        uint size = 0, count;
        uint status = PdhGetFormattedCounterArrayW(counters[index], FormatDouble | FormatNoCap100, ref size, out count, IntPtr.Zero);
        if (status != MoreData || size == 0) { return result.ToArray(); }
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try {
            if (PdhGetFormattedCounterArrayW(counters[index], FormatDouble | FormatNoCap100, ref size, out count, buffer) != 0) { return result.ToArray(); }
            int itemSize = IntPtr.Size + 16;
            for (int i = 0; i < count; i++) {
                IntPtr item = IntPtr.Add(buffer, i * itemSize);
                string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(item));
                uint valueStatus = (uint)Marshal.ReadInt32(item, IntPtr.Size);
                if (valueStatus != 0 && valueStatus != 1) { continue; }
                double value = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item, IntPtr.Size + 8));
                result.Add(new KeyValuePair<string, double>(name, value));
            }
        } finally { Marshal.FreeHGlobal(buffer); }
        return result.ToArray();
    }

    public void Dispose() {
        if (query != IntPtr.Zero) { PdhCloseQuery(query); query = IntPtr.Zero; }
    }
}
'@
}

# THE PAGE FILES: their size and what is in use, from one call to the kernel (SystemPageFileInformation), in pages.
# Win32_PageFileUsage gives the same in megabytes, through WMI. The committed memory is bounded by the physical memory
# PLUS these files: showing it alone let a 32 GB computer read "49 GB", and nobody could tell RAM from page file (18/09).
if (-not ('VigiePageFiles' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class VigiePageFiles {
    [DllImport("ntdll.dll")]
    static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returned);

    // [ total pages, pages in use, peak pages ], summed over every page file; null when the kernel refuses.
    public static long[] Usage() {
        const int SystemPageFileInformation = 18;
        int length = 4096;
        for (int attempt = 0; attempt < 5; attempt++) {
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                int returned;
                int status = NtQuerySystemInformation(SystemPageFileInformation, buffer, length, out returned);
                if (status == unchecked((int)0xC0000004)) { length *= 4; continue; }
                if (status != 0) { return null; }
                long total = 0, used = 0, peak = 0;
                if (returned == 0) { return new long[] { 0, 0, 0 }; }
                int offset = 0;
                while (true) {
                    IntPtr entry = IntPtr.Add(buffer, offset);
                    total += (uint)Marshal.ReadInt32(entry, 4);
                    used  += (uint)Marshal.ReadInt32(entry, 8);
                    peak  += (uint)Marshal.ReadInt32(entry, 12);
                    int next = Marshal.ReadInt32(entry, 0);
                    if (next == 0) { break; }
                    offset += next;
                }
                return new long[] { total, used, peak };
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        return null;
    }
}
'@
}

# THE PAGE FILES, in bytes: Total, Used, Peak. $null when the kernel refuses. Never throws.
function Get-PageFileStatus {
    $raw = $null
    try { $raw = [VigiePageFiles]::Usage() } catch { }
    if (-not $raw) { return $null }
    $page = [double][Environment]::SystemPageSize
    return [pscustomobject]@{ Total = $raw[0] * $page; Used = $raw[1] * $page; Peak = $raw[2] * $page }
}

# WHAT EACH PROCESS REALLY HOLDS IN RAM, apart from what it has committed. PrivateMemorySize64 is the COMMITTED memory:
# on 18/09 it gave 14.4 GB for the WSL virtual machine while 12.4 GB of it was in RAM, and the owner's rule is that
# the figures say what is really in RAM. The private working set -- the "Memory" column of the Task Manager -- comes
# from the same kernel call as the I/O counters (SYSTEM_PROCESS_INFORMATION, WorkingSetPrivateSize at offset 8,
# PrivatePageCount at offset 200 on 64-bit Windows), checked against the performance counters on 18/09.
if (-not ('VigieProcessMemory' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigieProcessMemory {
    [DllImport("ntdll.dll")]
    static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returned);

    // pid -> [ bytes in RAM (private working set), bytes committed ]; null when the kernel refuses.
    public static Dictionary<int, long[]> Read() {
        if (IntPtr.Size != 8) { return null; }
        int length = 1 << 20;
        for (int attempt = 0; attempt < 6; attempt++) {
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                int returned;
                int status = NtQuerySystemInformation(5, buffer, length, out returned);
                if (status == unchecked((int)0xC0000004)) { length = Math.Max(length * 2, returned + 65536); continue; }
                if (status != 0) { return null; }
                var result = new Dictionary<int, long[]>();
                int offset = 0;
                while (true) {
                    IntPtr entry = IntPtr.Add(buffer, offset);
                    int pid = (int)Marshal.ReadInt64(entry, 80);
                    result[pid] = new long[] { Marshal.ReadInt64(entry, 8), Marshal.ReadInt64(entry, 200) };
                    int next = Marshal.ReadInt32(entry, 0);
                    if (next == 0) { break; }
                    offset += next;
                }
                return result;
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        return null;
    }
}
'@
}

# RAM AND COMMITTED MEMORY PER PROCESS: a hashtable pid -> @{ Ram; Committed }, in bytes. Empty when the kernel refuses.
function Get-ProcessMemoryUse {
    $table = @{}
    try {
        $raw = [VigieProcessMemory]::Read()
        if ($raw) { foreach ($key in $raw.Keys) { $table[[int]$key] = [pscustomobject]@{ Ram = [double]$raw[$key][0]; Committed = [double]$raw[$key][1] } } }
    } catch { }
    return $table
}
