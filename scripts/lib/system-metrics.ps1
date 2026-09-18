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
