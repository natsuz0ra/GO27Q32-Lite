using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace MonitorLite;

/// <summary>Enabled 是 Windows 的用户 HDR 开关；不将 ACM/WCG 当作 HDR。</summary>
public sealed record HdrState(bool Supported, bool Enabled, string TargetPath, bool ActiveHdr);

public sealed class HdrService
{
    private const uint AllPaths = 1, ActivePaths = 2;
    private const int InsufficientBuffer = 122;
    private static bool Modern => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 26100);
    private static bool LegacyHdrOnly => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 16299)
        && !OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000);

    static HdrService()
    {
        Check<Header>(20); Check<SourceName>(84); Check<TargetName>(420);
        Check<ColorInfo>(36); Check<LegacyColorInfo>(32); Check<ColorState>(24);
        Check<PathSource>(20); Check<PathTarget>(48); Check<DisplayPath>(72);
    }
    private static void Check<T>(int size) where T : struct
    {
        if (Marshal.SizeOf<T>() != size) throw new TypeLoadException($"DisplayConfig ABI: {typeof(T).Name} 应为 {size} 字节，实际 {Marshal.SizeOf<T>()}。");
    }

    public HdrState Read(string desktop)
    {
        var target = Resolve(desktop);
        return ReadTarget(target).State;
    }

    public void Set(string desktop, bool enabled)
    {
        var target = Resolve(desktop);
        var before = ReadTarget(target);
        if (!before.State.Supported) throw new NotSupportedException("此显示目标没有报告 HDR 支持。");
        if (enabled && before.Limited) throw new InvalidOperationException("Windows 策略当前限制 HDR，未写入开关。");
        if (before.State.Enabled == enabled && (!Modern || (before.ActiveMode == 2) == enabled)) return;
        var request = new ColorState { Header = MakeHeader(Modern ? 16u : 10u, target.Path.Target, 24), Value = enabled ? 1u : 0u };
        Fail(SetColor(ref request), "设置指定显示器的 Windows HDR");
        Exception? last = null;
        // HDR 切换会重建显示拓扑；每次重新解析，但必须是同一 target device path。
        for (var attempt = 0; attempt < 25; attempt++)
        {
            Thread.Sleep(200);
            try
            {
                var currentTarget = Resolve(desktop);
                if (!string.Equals(currentTarget.DevicePath, target.DevicePath, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("显示拓扑改变：桌面名已对应另一台显示器，停止 HDR 验证。");
                var current = ReadTarget(currentTarget);
                if (current.State.Enabled == enabled && (!Modern || (current.ActiveMode == 2) == enabled)) return;
                last = new IOException($"HDR 用户开关={current.State.Enabled}，活动色彩模式={current.ActiveMode}。");
            }
            catch (Exception ex) when (ex is Win32Exception or IOException or InvalidOperationException) { last = ex; }
        }
        throw new IOException("Windows 已接受 HDR 请求，但未能在 5 秒内确认指定显示器生效。" + last?.Message, last);
    }

    /// <summary>只读诊断全部可能的显示路径，包括未激活/不可用目标；不切换拓扑。</summary>
    public string Diagnose()
    {
        var rows = Query(AllPaths).Select(path =>
        {
            var target = Describe(path);
            object? color = null;
            string? error = null;
            if ((path.Flags & 1) != 0 && IsGo(target.DevicePath))
            {
                try { var c = ReadTarget(target); color = new { c.State.Supported, c.State.Enabled, c.State.ActiveHdr, c.ActiveMode, c.Limited }; }
                catch (Exception ex) { error = ex.Message; }
            }
            return new { Desktop = target.Desktop, TargetPath = target.DevicePath, target.FriendlyName,
                Active = (path.Flags & 1) != 0, Available = path.Target.Available != 0,
                AdapterLow = path.Target.Adapter.Low, AdapterHigh = path.Target.Adapter.High,
                TargetId = path.Target.Id, SourceId = path.Source.Id, path.Target.OutputTechnology,
                target.SourceError, target.TargetError, IsGo27Q32 = IsGo(target.DevicePath), Color = color, ColorError = error };
        }).ToArray();
        return JsonSerializer.Serialize(new { OS = Environment.OSVersion.Version.ToString(), ModernHdrApi = Modern, LegacyHdrOnly,
            Note = "Active=false 的路径不属于当前活动桌面；Available=false 表示该路径目标当前不可用。WMI Active 不能替代活动 DisplayConfig 路径。",
            Paths = rows }, new JsonSerializerOptions { WriteIndented = true });
    }

    private static Target Resolve(string desktop)
    {
        if (string.IsNullOrWhiteSpace(desktop)) throw new ArgumentException("必须指定显示器桌面名，例如 \\\\.\\DISPLAY1。", nameof(desktop));
        var matches = Query(ActivePaths).Select(Describe).Where(t =>
            string.Equals(t.Desktop, desktop, StringComparison.OrdinalIgnoreCase) && IsGo(t.DevicePath))
            .GroupBy(t => t.DevicePath, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).ToArray();
        return matches.Length switch
        {
            1 => matches[0],
            0 => throw new InvalidOperationException($"未找到桌面 {desktop} 对应的活动 GO27Q32 路径（GBT275C/GBT2761）。请检查扩展/复制显示状态与显示器连接；不能依据 WMI Active 修改其他显示器。"),
            _ => throw new InvalidOperationException("同一桌面名对应多个 GO27Q32 目标，无法唯一选择 HDR 目标。")
        };
    }
    private static bool IsGo(string path) => path.Contains("#GBT275C#", StringComparison.OrdinalIgnoreCase)
        || path.Contains("#GBT2761#", StringComparison.OrdinalIgnoreCase);

    private static (HdrState State, uint ActiveMode, bool Limited) ReadTarget(Target target)
    {
        if (Modern)
        {
            var info = new ColorInfo { Header = MakeHeader(15, target.Path.Target, 36) };
            Fail(GetColor(ref info), "读取明确区分 HDR/WCG 的 Windows 色彩信息");
            return (new HdrState((info.Value & 16) != 0, (info.Value & 32) != 0, target.DevicePath, info.ActiveMode == 2),
                info.ActiveMode, (info.Value & 8) != 0);
        }
        if (!LegacyHdrOnly)
            throw new NotSupportedException("当前 Windows 版本不在本程序的 HDR 支持范围。为避免将 ACM/WCG 当成 HDR，此版本暂不操作；本程序启用 Windows 11 build 26100 及以后的独立接口，或 Windows 10 1709–22H2 的旧接口。");
        var legacy = new LegacyColorInfo { Header = MakeHeader(9, target.Path.Target, 32) };
        Fail(GetLegacyColor(ref legacy), "读取 Windows 10 HDR 信息");
        // Win10 的 Advanced Color 仅用于 HDR；Win11 已扩展至 SDR ACM，禁止走此分支。
        if ((legacy.Value & 4) != 0) throw new NotSupportedException("此目标报告 wideColorEnforced，不能明确判定旧接口的 HDR 语义。");
        var enabled = (legacy.Value & 2) != 0;
        return (new HdrState((legacy.Value & 1) != 0, enabled, target.DevicePath, enabled), enabled ? 2u : 0u, (legacy.Value & 8) != 0);
    }

    private sealed record Target(DisplayPath Path, string Desktop, string DevicePath, string FriendlyName, int SourceError, int TargetError);
    private static Target Describe(DisplayPath path)
    {
        var source = new SourceName { Header = new Header { Type = 1, Size = 84, Adapter = path.Source.Adapter, Id = path.Source.Id }, Name = "" };
        var target = new TargetName { Header = MakeHeader(2, path.Target, 420), FriendlyName = "", DevicePath = "" };
        var se = GetSource(ref source); var te = GetTarget(ref target);
        return new Target(path, se == 0 ? source.Name : "", te == 0 ? target.DevicePath : "", te == 0 ? target.FriendlyName : "", se, te);
    }
    private static Header MakeHeader(uint type, PathTarget target, uint size) => new() { Type = type, Size = size, Adapter = target.Adapter, Id = target.Id };
    private static DisplayPath[] Query(uint flags)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            Fail(GetDisplayConfigBufferSizes(flags, out var pathCount, out var modeCount), "获取显示路径缓冲区");
            if (pathCount > 16384 || modeCount > 65536) throw new IOException("显示路径数量异常。");
            var paths = new DisplayPath[pathCount];
            // DISPLAYCONFIG_MODE_INFO 是 16 字节头 + 48 字节 union，天然按8字节对齐；不解析模式内容。
            var modes = Marshal.AllocHGlobal(checked((int)Math.Max(1u, modeCount) * 64));
            try
            {
                var result = QueryDisplayConfig(flags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
                if (result == InsufficientBuffer) continue;
                Fail(result, "查询显示路径");
                return paths.Take((int)pathCount).ToArray();
            }
            finally { Marshal.FreeHGlobal(modes); }
        }
        throw new IOException("显示拓扑持续改变，无法获取稳定路径。");
    }
    private static void Fail(int error, string operation) { if (error != 0) throw new Win32Exception(error, operation + $"失败（{error}）。"); }

    [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] private struct Header { public uint Type, Size; public Luid Adapter; public uint Id; }
    [StructLayout(LayoutKind.Sequential)] private struct PathSource { public Luid Adapter; public uint Id, ModeIndex, Status; }
    [StructLayout(LayoutKind.Sequential)] private struct PathTarget
    {
        public Luid Adapter;
        public uint Id, ModeIndex, OutputTechnology, Rotation, Scaling, RefreshNumerator, RefreshDenominator, Scanline;
        public int Available;
        public uint Status;
    }
    [StructLayout(LayoutKind.Sequential)] private struct DisplayPath { public PathSource Source; public PathTarget Target; public uint Flags; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct SourceName
    {
        public Header Header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct TargetName
    {
        public Header Header;
        public uint Flags, OutputTechnology;
        public ushort EdidManufactureId, EdidProductCode;
        public uint ConnectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string FriendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DevicePath;
    }
    [StructLayout(LayoutKind.Sequential)] private struct ColorInfo { public Header Header; public uint Value, Encoding, BitsPerChannel, ActiveMode; }
    [StructLayout(LayoutKind.Sequential)] private struct LegacyColorInfo { public Header Header; public uint Value, Encoding, BitsPerChannel; }
    [StructLayout(LayoutKind.Sequential)] private struct ColorState { public Header Header; public uint Value; }

    [DllImport("user32.dll")] private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] private static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] DisplayPath[] pathArray, ref uint modes, IntPtr modeArray, IntPtr topology);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo", CharSet = CharSet.Unicode)] private static extern int GetSource(ref SourceName packet);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo", CharSet = CharSet.Unicode)] private static extern int GetTarget(ref TargetName packet);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")] private static extern int GetColor(ref ColorInfo packet);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")] private static extern int GetLegacyColor(ref LegacyColorInfo packet);
    [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")] private static extern int SetColor(ref ColorState packet);
}
