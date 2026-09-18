# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    tcp-ports.ps1 - WHO LISTENS ON A PORT, ASKED OF WINDOWS DIRECTLY. Loadable alone (no dependency on Pode or common.ps1).

    Why it exists. Get-NetTCPConnection enumerates EVERY TCP connection of the computer through WMI, then filters. On
    14/09 the computer held 10 775 of them, 10 426 kept by the WSL device host: each call took 26 seconds, whether
    something listened or not, and the update of Vigie went from 98 to 225 seconds. Measured the same day:
    GetExtendedTcpTable asked for listeners only answers in under 2 ms, with the owning process
    (notes/evidence/2026-09-14-port-lookup-26-seconds.md).

    The rule it applies: the optimised call that gives the information needed, never the convenient one
    (doc/en/agent-working/disciplines.md, section "Wrapping system calls"). scripts/check-probes.ps1 refuses the slow
    cmdlets anywhere else.
#>

if (-not ('VigieTcpPorts' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigieTcpPorts {
    [DllImport("iphlpapi.dll", SetLastError = true)]
    static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool sort, int family, int tableClass, uint reserved);
    [DllImport("iphlpapi.dll", SetLastError = true)]
    static extern uint GetExtendedUdpTable(IntPtr table, ref int size, bool sort, int family, int tableClass, uint reserved);

    const int AfInet = 2;
    const int AfInet6 = 23;
    const int TcpTableOwnerPidListener = 3;
    const int UdpTableOwnerPid = 1;

    // Ports are stored in network byte order in the low two bytes.
    static int PortOf(uint raw) { return (int)(((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF)); }

    // Rows of the four tables: the port and the process id sit at fixed offsets.
    static List<int> Owners(bool tcp, int family, int port) {
        int tableClass = tcp ? TcpTableOwnerPidListener : UdpTableOwnerPid;
        int rowSize, portOffset, pidOffset;
        if (tcp && family == AfInet)       { rowSize = 24; portOffset = 8;  pidOffset = 20; }
        else if (tcp)                      { rowSize = 56; portOffset = 20; pidOffset = 52; }
        else if (family == AfInet)         { rowSize = 12; portOffset = 4;  pidOffset = 8; }
        else                               { rowSize = 28; portOffset = 20; pidOffset = 24; }
        var owners = new List<int>();
        int size = 0;
        if (tcp) { GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, tableClass, 0); }
        else     { GetExtendedUdpTable(IntPtr.Zero, ref size, false, family, tableClass, 0); }
        if (size <= 0) { return owners; }
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try {
            uint code = tcp ? GetExtendedTcpTable(buffer, ref size, false, family, tableClass, 0)
                            : GetExtendedUdpTable(buffer, ref size, false, family, tableClass, 0);
            if (code != 0) { return owners; }
            int count = Marshal.ReadInt32(buffer);
            for (int i = 0; i < count; i++) {
                IntPtr row = IntPtr.Add(buffer, 4 + i * rowSize);
                if (PortOf((uint)Marshal.ReadInt32(row, portOffset)) == port) { owners.Add(Marshal.ReadInt32(row, pidOffset)); }
            }
        } finally { Marshal.FreeHGlobal(buffer); }
        return owners;
    }

    public static int[] TcpListenerOwners(int port) {
        var all = Owners(true, AfInet, port);
        all.AddRange(Owners(true, AfInet6, port));
        return all.ToArray();
    }

    public static int[] UdpEndpointOwners(int port) {
        var all = Owners(false, AfInet, port);
        all.AddRange(Owners(false, AfInet6, port));
        return all.ToArray();
    }
}
'@
}

# THE EPHEMERAL PORTS IN USE, per process. A separate type, so that a session which loaded the first one keeps working.
# On 17/09 the TCP and UDP port spaces ran out (Tcpip 4231 and 4266): every connection of every application failed,
# Vigie's included. The tables below are the ones the check needs -- every TCP connection in any state, TIME_WAIT
# included, and every UDP endpoint -- read in one call each instead of through WMI.
if (-not ('VigiePortUsage' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VigiePortUsage {
    [DllImport("iphlpapi.dll", SetLastError = true)]
    static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool sort, int family, int tableClass, uint reserved);
    [DllImport("iphlpapi.dll", SetLastError = true)]
    static extern uint GetExtendedUdpTable(IntPtr table, ref int size, bool sort, int family, int tableClass, uint reserved);

    const int AfInet = 2;
    const int AfInet6 = 23;
    const int TcpTableOwnerPidAll = 5;
    const int UdpTableOwnerPid = 1;

    static int PortOf(uint raw) { return (int)(((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF)); }

    // Adds, for each row whose local port lies in [low, high], the pair (process, port). Returns false when Windows
    // refused the table, so that a failed reading is never mistaken for "no port in use".
    static bool Collect(bool tcp, int family, int low, int high, HashSet<long> pairs, HashSet<int> ports) {
        int tableClass = tcp ? TcpTableOwnerPidAll : UdpTableOwnerPid;
        int rowSize, portOffset, pidOffset;
        if (tcp && family == AfInet)       { rowSize = 24; portOffset = 8;  pidOffset = 20; }
        else if (tcp)                      { rowSize = 56; portOffset = 20; pidOffset = 52; }
        else if (family == AfInet)         { rowSize = 12; portOffset = 4;  pidOffset = 8; }
        else                               { rowSize = 28; portOffset = 20; pidOffset = 24; }
        for (int attempt = 0; attempt < 3; attempt++) {
            int size = 0;
            if (tcp) { GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, tableClass, 0); }
            else     { GetExtendedUdpTable(IntPtr.Zero, ref size, false, family, tableClass, 0); }
            if (size <= 0) { return false; }
            // The table can grow between the two calls: some room, and a retry when it still does not fit.
            size += 4096;
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try {
                uint code = tcp ? GetExtendedTcpTable(buffer, ref size, false, family, tableClass, 0)
                                : GetExtendedUdpTable(buffer, ref size, false, family, tableClass, 0);
                if (code == 122) { continue; }
                if (code != 0) { return false; }
                int count = Marshal.ReadInt32(buffer);
                for (int i = 0; i < count; i++) {
                    IntPtr row = IntPtr.Add(buffer, 4 + i * rowSize);
                    int port = PortOf((uint)Marshal.ReadInt32(row, portOffset));
                    if (port < low || port > high) { continue; }
                    int pid = Marshal.ReadInt32(row, pidOffset);
                    ports.Add(port);
                    pairs.Add(((long)pid << 16) | (long)port);
                }
                return true;
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        return false;
    }

    // [ distinct ports in use, pid, ports held, pid, ports held, ... ], or null when Windows refused both tables.
    public static int[] Usage(bool tcp, int low, int high) {
        var pairs = new HashSet<long>();
        var ports = new HashSet<int>();
        bool ok4 = Collect(tcp, AfInet, low, high, pairs, ports);
        bool ok6 = Collect(tcp, AfInet6, low, high, pairs, ports);
        if (!ok4 && !ok6) { return null; }
        var perPid = new Dictionary<int, int>();
        foreach (long pair in pairs) {
            int pid = (int)(pair >> 16);
            int held;
            perPid.TryGetValue(pid, out held);
            perPid[pid] = held + 1;
        }
        var result = new List<int> { ports.Count };
        foreach (var entry in perPid) { result.Add(entry.Key); result.Add(entry.Value); }
        return result.ToArray();
    }
}
'@
}

if (-not ('VigieServiceProcesses' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class VigieServiceProcesses {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr OpenSCManager(string machine, string database, uint access);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool EnumServicesStatusEx(IntPtr manager, int infoLevel, uint serviceType, uint serviceState,
        IntPtr buffer, int bufferSize, out int bytesNeeded, out int servicesReturned, ref int resumeHandle, string group);
    [DllImport("advapi32.dll")]
    static extern bool CloseServiceHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct EnumServiceStatusProcess {
        public IntPtr ServiceName; public IntPtr DisplayName;
        public uint ServiceType; public uint CurrentState; public uint ControlsAccepted; public uint Win32ExitCode;
        public uint ServiceSpecificExitCode; public uint CheckPoint; public uint WaitHint; public uint ProcessId; public uint ServiceFlags;
    }

    // The first active Win32 service running in this process: { name, display name }, or null.
    public static string[] ByProcessId(int processId) {
        const uint EnumerateService = 0x0004;
        const uint Win32Services = 0x30;
        const uint Active = 0x1;
        IntPtr manager = OpenSCManager(null, null, EnumerateService);
        if (manager == IntPtr.Zero) { return null; }
        try {
            int needed, returned, resume = 0;
            EnumServicesStatusEx(manager, 0, Win32Services, Active, IntPtr.Zero, 0, out needed, out returned, ref resume, null);
            if (needed <= 0) { return null; }
            IntPtr buffer = Marshal.AllocHGlobal(needed);
            try {
                resume = 0;
                if (!EnumServicesStatusEx(manager, 0, Win32Services, Active, buffer, needed, out needed, out returned, ref resume, null)) { return null; }
                int size = Marshal.SizeOf(typeof(EnumServiceStatusProcess));
                for (int i = 0; i < returned; i++) {
                    var entry = (EnumServiceStatusProcess)Marshal.PtrToStructure(IntPtr.Add(buffer, i * size), typeof(EnumServiceStatusProcess));
                    if (entry.ProcessId == (uint)processId) {
                        return new[] { Marshal.PtrToStringUni(entry.ServiceName), Marshal.PtrToStringUni(entry.DisplayName) };
                    }
                }
            } finally { Marshal.FreeHGlobal(buffer); }
        } finally { CloseServiceHandle(manager); }
        return null;
    }
}
'@
}

# WHICH SERVICE RUNS IN THIS PROCESS? { Name, DisplayName }, or $null. Never throws. One call to the service manager
# for every active service, instead of a WMI query taking about a second (14/09).
function Get-ServiceByProcessId {
    param([Parameter(Mandatory)][int]$ProcessId)
    $found = $null
    try { $found = [VigieServiceProcesses]::ByProcessId($ProcessId) } catch { }
    if (-not $found) { return $null }
    return [pscustomobject]@{ Name = $found[0]; DisplayName = $found[1] }
}

# WHO LISTENS ON THIS TCP PORT? The listener -- LocalPort and OwningProcess, the two facts callers use -- or $null.
# Never throws: "nobody listens" is an ordinary answer, the one hoped for after stopping the server app.
function Get-PortListener {
    param([Parameter(Mandatory)][int]$Port)
    $owners = @()
    try { $owners = @([VigieTcpPorts]::TcpListenerOwners($Port)) } catch { }
    if (-not $owners.Count) { return $null }
    return [pscustomobject]@{ LocalPort = $Port; OwningProcess = $owners[0] }
}

# WHICH PROCESS HOLDS THIS UDP PORT? Its process id, or $null. Never throws.
function Get-UdpEndpointOwner {
    param([Parameter(Mandatory)][int]$Port)
    $owners = @()
    try { $owners = @([VigieTcpPorts]::UdpEndpointOwners($Port)) } catch { }
    if (-not $owners.Count) { return $null }
    return $owners[0]
}

# THE DYNAMIC PORT RANGE OF A PROTOCOL, as Windows applies it: @{ Start; Count }, or $null. netsh is the only reader
# Windows offers (0.2 s, measured 18/09) and its words are translated, so only its two numbers are read.
function Get-EphemeralPortRange {
    param([Parameter(Mandatory)][ValidateSet('tcp','udp')][string]$Protocol)
    $text = ''
    try { $text = (& netsh.exe int ipv4 show dynamicport $Protocol 2>$null) -join ' ' } catch { }
    $numbers = @([regex]::Matches($text, '\d+') | ForEach-Object { [int]$_.Value })
    if ($numbers.Count -lt 2 -or $numbers[1] -le 0) { return $null }
    return @{ Start = $numbers[0]; Count = $numbers[1] }
}

# THE EPHEMERAL PORTS OF A PROTOCOL IN USE: Used (distinct ports), Limit, and ByProcess -- ProcessId and Count, most
# first. Process 0 holds the TCP connections waiting to close (TIME_WAIT): they still occupy their port. $null when
# Windows refused the reading. Never throws.
function Get-EphemeralPortUsage {
    param(
        [Parameter(Mandatory)][ValidateSet('tcp','udp')][string]$Protocol,
        [Parameter(Mandatory)][int]$Start,
        [Parameter(Mandatory)][int]$Count
    )
    $raw = $null
    try { $raw = [VigiePortUsage]::Usage(($Protocol -eq 'tcp'), $Start, $Start + $Count - 1) } catch { }
    if ($null -eq $raw) { return $null }
    $owners = @(for ($i = 1; $i + 1 -lt $raw.Count; $i += 2) { [pscustomobject]@{ ProcessId = $raw[$i]; Count = $raw[$i + 1] } })
    return [pscustomobject]@{ Used = $raw[0]; Limit = $Count; ByProcess = @($owners | Sort-Object Count -Descending) }
}
