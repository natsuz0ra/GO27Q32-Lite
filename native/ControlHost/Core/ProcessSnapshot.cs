using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace MonitorLite;

internal sealed record ProcessSnapshot(List<string> Paths, string? Foreground, string[] Unreadable)
{
    public bool Reliable => Unreadable.Length == 0;
    public static string ImagePath(int pid)
    {
        // No module enumeration or process-memory access, including elevated apps.
        var handle = Native.OpenProcess(0x1000, false, pid);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            uint size = 32768; var buffer = new StringBuilder((int)size);
            if (!Native.QueryFullProcessImageName(handle, 0, buffer, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return buffer.ToString();
        }
        finally { Native.CloseHandle(handle); }
    }
    public static ProcessSnapshot Capture(IEnumerable<AppRule> rules, Func<int, string>? imagePath = null)
    {
        imagePath ??= ImagePath;
        var names = rules.Where(r => r.Enabled).Select(r => Path.GetFileNameWithoutExtension(r.ExecutablePath)).Distinct(StringComparer.OrdinalIgnoreCase);
        Native.GetWindowThreadProcessId(Native.GetForegroundWindow(), out uint foregroundId);
        var paths = new List<string>(); string? foreground = null; var unreadable = new HashSet<string>();
        foreach (string name in names)
        foreach (var process in Process.GetProcessesByName(name))
        {
            using (process)
            {
                try
                {
                    string path = imagePath(process.Id);
                    paths.Add(path);
                    if (process.Id == foregroundId) foreground = path;
                }
                catch (InvalidOperationException) { /* Process exited while taking the snapshot. */ }
                catch (Win32Exception)
                {
                    try { if (process.HasExited) continue; } catch { }
                    unreadable.Add(name + ".exe");
                }
            }
        }
        return new(paths, foreground, unreadable.Order().ToArray());
    }
}
