# @author Florent HAZARD <f.hazard@sowapps.com>
<# TOOL: the real notification API, in this very process.

   Same API as rank 40 -- it lives in Windows, nothing to install -- but opened directly
   instead of through a borrowed host: no child process, no wait, nothing to clean up.

   WHY BY HAND. .NET no longer marshals IInspectable: `InterfaceIsIInspectable` and
   `UnmanagedType.HString` throw "not supported in the .NET runtime" (measured 10/09). So
   the method tables are walked by hand. Every WinRT interface starts with IUnknown's three
   entries plus IInspectable's three, which is why the first useful method sits at rank six
   -- that constant is the whole trick, and it is written down rather than counted again.

   The types are compiled once and kept: Add-Type costs a compilation, and a notification
   that costs a compilation would be a notification one avoids sending. #>
param($Notification, $Context)

if (-not ('VigieToastCom' -as [type])) {
    $source = @'
using System;
using System.Runtime.InteropServices;

public static class VigieToastCom
{
    [DllImport("combase.dll", CharSet = CharSet.Unicode)]
    static extern int WindowsCreateString(string src, int len, out IntPtr hstring);
    [DllImport("combase.dll")]
    static extern int WindowsDeleteString(IntPtr hstring);
    [DllImport("combase.dll")]
    static extern int RoGetActivationFactory(IntPtr classId, [In] ref Guid iid, out IntPtr factory);
    [DllImport("combase.dll")]
    static extern int RoActivateInstance(IntPtr classId, out IntPtr instance);

    const int FIRST = 6;

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int InOut(IntPtr self, IntPtr a, out IntPtr b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int In(IntPtr self, IntPtr a);

    static IntPtr Slot(IntPtr obj, int index)
    {
        IntPtr table = Marshal.ReadIntPtr(obj);
        return Marshal.ReadIntPtr(table, index * IntPtr.Size);
    }

    static IntPtr Str(string s)
    {
        IntPtr h;
        if (WindowsCreateString(s, s.Length, out h) != 0) { throw new Exception("WindowsCreateString"); }
        return h;
    }

    public static void Show(string applicationId, string xml)
    {
        IntPtr name = Str("Windows.UI.Notifications.ToastNotificationManager");
        Guid statics = new Guid("50ac103f-d235-4598-bbef-98fe4d1a3ad4");
        IntPtr manager;
        int hr = RoGetActivationFactory(name, ref statics, out manager);
        WindowsDeleteString(name);
        if (hr != 0) { throw new Exception("RoGetActivationFactory manager 0x" + hr.ToString("X8")); }

        IntPtr id = Str(applicationId);
        IntPtr notifier;
        hr = Marshal.GetDelegateForFunctionPointer<InOut>(Slot(manager, FIRST + 1))(manager, id, out notifier);
        WindowsDeleteString(id);
        if (hr != 0) { throw new Exception("CreateToastNotifierWithId 0x" + hr.ToString("X8")); }

        name = Str("Windows.Data.Xml.Dom.XmlDocument");
        IntPtr document;
        hr = RoActivateInstance(name, out document);
        WindowsDeleteString(name);
        if (hr != 0) { throw new Exception("RoActivateInstance XmlDocument 0x" + hr.ToString("X8")); }

        Guid documentIo = new Guid("6cd0e74e-ee65-4489-9ebf-ca43e87ba637");
        IntPtr loader;
        hr = Marshal.QueryInterface(document, in documentIo, out loader);
        if (hr != 0) { throw new Exception("QueryInterface IXmlDocumentIO 0x" + hr.ToString("X8")); }

        IntPtr text = Str(xml);
        hr = Marshal.GetDelegateForFunctionPointer<In>(Slot(loader, FIRST))(loader, text);
        WindowsDeleteString(text);
        if (hr != 0) { throw new Exception("LoadXml 0x" + hr.ToString("X8")); }

        name = Str("Windows.UI.Notifications.ToastNotification");
        Guid toastFactory = new Guid("04124b20-82c6-4229-b109-fd9ed4662b53");
        IntPtr factory;
        hr = RoGetActivationFactory(name, ref toastFactory, out factory);
        WindowsDeleteString(name);
        if (hr != 0) { throw new Exception("RoGetActivationFactory toast 0x" + hr.ToString("X8")); }

        IntPtr toast;
        hr = Marshal.GetDelegateForFunctionPointer<InOut>(Slot(factory, FIRST))(factory, document, out toast);
        if (hr != 0) { throw new Exception("CreateToastNotification 0x" + hr.ToString("X8")); }

        hr = Marshal.GetDelegateForFunctionPointer<In>(Slot(notifier, FIRST))(notifier, toast);
        if (hr != 0) { throw new Exception("Show 0x" + hr.ToString("X8")); }
    }
}
'@
    try { Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop } catch { return $false }
}

$xml = Get-VigieToastXml -Subject "$($Notification.Subject)" -Body "$($Notification.Body)" `
                        -Image (Get-VigieToastImage -TrayRoot $Context.TrayRoot -State "$($Notification.State)") `
                        -Long:([int]$Notification.Duration -ge 10000)
if (-not $xml) { return $false }
try {
    [VigieToastCom]::Show($Context.Aumid, $xml)
    return $true
} catch {
    return $false
}
