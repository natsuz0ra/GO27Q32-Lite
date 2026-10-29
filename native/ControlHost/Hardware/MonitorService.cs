using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace MonitorLite;

public sealed class MonitorDevice : IDisposable
{
    public string Id { get; }
    public string Name { get; }
    public string HardwareId { get; }
    public string Desktop { get; }
    private readonly bool unique;
    internal IntPtr Handle { get; private set; }
    public bool IsTarget => unique && (HardwareId.Contains("GBT2761", StringComparison.OrdinalIgnoreCase) || HardwareId.Contains("GBT275C", StringComparison.OrdinalIgnoreCase));
    internal MonitorDevice(IntPtr handle, string hardwareId, string desktop, string description, uint index, bool unique)
    {
        Handle = handle; HardwareId = hardwareId; Desktop = desktop; this.unique = unique;
        Id = hardwareId + "/" + index;
        Name = (IsTarget ? "GO27Q32" : description) + " · " + desktop;
    }
    public override string ToString() => Name;
    public void Dispose()
    {
        if (Handle != IntPtr.Zero) { Native.DestroyPhysicalMonitor(Handle); Handle = IntPtr.Zero; }
    }
}

public sealed class MonitorService : IDisposable
{
    // One serial worker: discovery, writes and reads never race over a physical handle.
    private readonly SemaphoreSlim gate = new(1, 1);
    public List<MonitorDevice> Devices { get; private set; } = [];
    public List<string> DiscoveryLog { get; } = [];
    public async Task ScanAsync() => await Run(() =>
    {
        foreach (var item in Devices) item.Dispose();
        Devices.Clear(); DiscoveryLog.Clear();
        Native.MonitorEnum visit = (IntPtr h, IntPtr dc, ref Native.Rect rect, IntPtr data) =>
        {
            var info = new Native.MonitorInfo { Size = (uint)Marshal.SizeOf<Native.MonitorInfo>() };
            if (!Native.GetMonitorInfo(h, ref info)) { DiscoveryLog.Add("GetMonitorInfo: " + Marshal.GetLastWin32Error()); return true; }
            var display = new Native.DisplayDevice { Size = (uint)Marshal.SizeOf<Native.DisplayDevice>() };
            Native.EnumDisplayDevices(info.Device, 0, ref display, 0);
            if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(h, out uint count)) { DiscoveryLog.Add(info.Device + ": 无控制句柄 " + Marshal.GetLastWin32Error()); return true; }
            DiscoveryLog.Add(info.Device + " | " + display.Id + " | physical=" + count);
            if (count == 0 || count > 64) return true;
            var physical = new Native.PhysicalMonitor[count];
            if (!Native.GetPhysicalMonitorsFromHMONITOR(h, count, physical)) { DiscoveryLog.Add("GetPhysicalMonitors: " + Marshal.GetLastWin32Error()); return true; }
            DiscoveryLog.Add($"physical[0] handle=0x{physical[0].Handle.ToInt64():X} desc={physical[0].Description}");
            if (count != 1) DiscoveryLog.Add("同一桌面存在多个物理目标，无法唯一对应型号；禁用该桌面的控制，请使用扩展显示。");
            for (uint i = 0; i < count; i++) Devices.Add(new MonitorDevice(physical[i].Handle, display.Id ?? "", info.Device, physical[i].Description, i, count == 1));
            return true;
        };
        if (!Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, visit, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return true;
    });
    private async Task<T> Run<T>(Func<T> action)
    {
        await gate.WaitAsync();
        try { return await Task.Run(action); }
        finally { gate.Release(); }
    }
    private void Require(MonitorDevice monitor)
    {
        // Some driver stacks hand back a zero physical handle that still answers DDC/CI, so the
        // handle value alone is not evidence of a disconnect; a failed read is.
        if (!Devices.Contains(monitor)) throw new IOException("显示器已断开，请重新检测");
        if (!monitor.IsTarget) throw new InvalidOperationException("仅允许控制已识别的 GO27Q32，其他显示器保持只读");
    }
    private VcpValue Read(MonitorDevice monitor, Feature feature) => Read(monitor, feature, out _);
    private VcpValue Read(MonitorDevice monitor, Feature feature, out uint type)
    {
        Require(monitor);
        type = 0;
        int error = 0;
        for (int i = 0; i < 3; i++)
        {
            if (Native.GetVCPFeatureAndVCPFeatureReply(monitor.Handle, feature.Code, out type, out uint value, out uint max)) return new(value, max);
            error = Marshal.GetLastWin32Error(); Thread.Sleep(100);
        }
        throw new Win32Exception(error, $"{feature.Name}读取失败（0x{feature.Code:X2}，错误 {error}）");
    }
    public Task<Dictionary<string, VcpValue>> ReadAllAsync(MonitorDevice monitor) => Run(() =>
    {
        var result = new Dictionary<string, VcpValue>();
        foreach (var f in Features.All)
        {
            try { var value = Read(monitor, f); if (f.Accepts(value.Value)) result[f.Id] = value; }
            catch (Win32Exception) { }
        }
        return result;
    });
    /// <summary>Single-attempt reads for live monitoring: never retry, never stall the DDC channel.</summary>
    public Task<Dictionary<string, VcpValue>> ReadSubsetAsync(MonitorDevice monitor, IEnumerable<Feature> features) => Run(() =>
    {
        var result = new Dictionary<string, VcpValue>();
        foreach (var feature in features)
        {
            try
            {
                if (!Native.GetVCPFeatureAndVCPFeatureReply(monitor.Handle, feature.Code, out _, out uint value, out uint maximum)) continue;
                var reading = new VcpValue(value, maximum);
                if (feature.Accepts(reading.Value)) result[feature.Id] = reading;
            }
            catch (Win32Exception) { }
        }
        return result;
    });
    public Task<VcpValue> SetAsync(MonitorDevice monitor, Feature feature, uint value) => Run(() =>
    {
        Write(monitor, feature, value);
        if (feature.Id == "input") return new VcpValue(value, feature.Max);
        return Read(monitor, feature);
    });
    Dictionary<string, VcpValue> TimerSnapshot(MonitorDevice monitor)
    {
        var result = new Dictionary<string, VcpValue>();
        foreach (string id in new[] { "gameTimer", "timerRunning", "timerDuration" })
        {
            var feature = Features.Get(id); var reading = Read(monitor, feature);
            if (!feature.Accepts(reading.Value)) throw new IOException("显示器计时器读数无效，已停止操作。");
            result[id] = reading;
        }
        return result;
    }
    public Task<Dictionary<string, VcpValue>> ConfigureTimerAsync(MonitorDevice monitor, uint mode, uint duration) => Run(() =>
    {
        var steps = GameTimer.StartSteps(mode, duration);
        // Check availability before the first write. Keep the complete vendor
        // pause -> time -> mode -> continue sequence under the hardware gate.
        if (mode != 0) _ = TimerSnapshot(monitor);
        try
        {
            for (int i = 0; i < steps.Length; i++)
            {
                Write(monitor, Features.Get(steps[i].Key), steps[i].Value);
                if (i < steps.Length - 1) Thread.Sleep(200);
            }
            return TimerSnapshot(monitor); // FB is current elapsed/remaining time.
        }
        catch
        {
            if (mode != 0) try { Write(monitor, Features.Get("timerRunning"), 0); } catch { }
            throw;
        }
    });
    public Task<Dictionary<string, VcpValue>> PauseTimerAsync(MonitorDevice monitor, bool paused) => Run(() =>
    {
        var current = TimerSnapshot(monitor);
        if (current["gameTimer"].Value == 0) throw new InvalidOperationException("请先启动计时器。");
        Write(monitor, Features.Get("timerRunning"), paused ? 0u : 1u);
        return TimerSnapshot(monitor);
    });
    private HdrState StableOutput(MonitorDevice monitor)
    {
        var state = new HdrService().Read(monitor.Desktop);
        if (state.Enabled != state.ActiveHdr) throw new IOException("HDR 请求与实际输出尚未一致，请等待切换完成。");
        return state;
    }
    private void CheckOutput(MonitorDevice monitor, HdrState? expected)
    {
        if (expected is null) return;
        var actual = StableOutput(monitor);
        if (actual.ActiveHdr != expected.ActiveHdr || actual.TargetPath != expected.TargetPath)
            throw new IOException("操作期间显示器或 SDR/HDR 模式改变，已停止应用参数，请重新读取。");
    }
    private void Write(MonitorDevice monitor, Feature feature, uint value, HdrState? expected = null)
    {
        Require(monitor);
        if (!feature.Accepts(value)) throw new ArgumentOutOfRangeException(nameof(value));
        expected ??= feature.DeviceSetting ? null : StableOutput(monitor);
        CheckOutput(monitor, expected);
        if (Features.BlockReason(feature.Id, null, expected?.ActiveHdr == true) is string unsupported)
            throw new InvalidOperationException(unsupported);
        var before = Read(monitor, feature); // Reject unavailable controls, never guess their values.
        if (!feature.PackedTime && feature.Choices is null && before.Maximum > 0 && value > before.Maximum) throw new InvalidDataException(feature.Name + "超出显示器报告的范围");
        if (before.Value == value) { CheckOutput(monitor, expected); return; }
        if (!feature.DeviceSetting && expected?.ActiveHdr != true && feature.Id != "pictureMode")
        {
            // Apply the same known mode locks as the vendor UI, before sending a write.
            uint? mode = null;
            try { mode = Read(monitor, Features.Get("pictureMode")).Value; }
            catch (Win32Exception) { }
            if (Features.BlockReason(feature.Id, mode) is string reason) throw new InvalidOperationException(reason);
        }
        CheckOutput(monitor, expected);
        if (!Native.SetVCPFeature(monitor.Handle, feature.Code, value)) throw new Win32Exception(Marshal.GetLastWin32Error(), feature.Name + "写入失败");
        Thread.Sleep(feature.Id == "pictureMode" ? 200 : 120);
        if (feature.Id == "input") return; // The monitor may immediately leave this source.
        VcpValue? after = null; Exception? last = null;
        for (int attempt = 0; attempt < (feature.Id == "pictureMode" ? 15 : 3); attempt++)
        {
            CheckOutput(monitor, expected);
            try { after = Read(monitor, feature); if (after.Value == value) { CheckOutput(monitor, expected); return; } }
            catch (Win32Exception ex) { last = ex; }
            Thread.Sleep(200);
        }
        throw new IOException($"{feature.Name}未生效：请求 {value}，读回 {(after is null ? "失败" : after.Value.ToString())}。当前画面模式或 HDR 可能锁定该项。", last);
    }
    public Task ApplyAsync(MonitorDevice monitor, Dictionary<string, uint> values, bool automatic) => Run(() =>
    {
        Require(monitor);
        var output = StableOutput(monitor);
        uint? targetMode = values.TryGetValue("pictureMode", out uint requestedMode) ? requestedMode : null;
        if (!output.ActiveHdr && targetMode is null)
            try { targetMode = Read(monitor, Features.Get("pictureMode")).Value; }
            catch (Win32Exception) { }
        // Validate the whole profile before the first write.
        foreach (var pair in values)
        {
            var f = Features.Get(pair.Key);
            if (!f.Accepts(pair.Value) || !f.Automatic) throw new InvalidDataException("配置包含不允许的参数：" + f.Name);
            if (Features.BlockReason(pair.Key, targetMode, output.ActiveHdr) is string reason) throw new InvalidDataException(reason + "：" + f.Name);
        }
        foreach (var pair in Features.Ordered(values)) Write(monitor, Features.Get(pair.Key), pair.Value, output);
        return true;
    });
    public Task<string> DiagnoseAsync() => Run(() =>
    {
        var report = new StringBuilder("GO27Q32 Lite 0.3.0 — 只读诊断\r\n" + DateTimeOffset.Now + "\r\n");
        foreach (var line in DiscoveryLog) report.AppendLine(line);
        if (Devices.Count == 0) report.AppendLine("未枚举到任何物理显示器。");
        foreach (var monitor in Devices)
        {
            report.AppendLine($"\r\n{monitor.Name} | {monitor.HardwareId} | handle=0x{monitor.Handle.ToInt64():X} | target={monitor.IsTarget}");
            if (!monitor.IsTarget) continue;
            try
            {
                if (Native.GetCapabilitiesStringLength(monitor.Handle, out uint length) && length > 0 && length < 65536)
                {
                    byte[] buffer = new byte[length];
                    if (Native.CapabilitiesRequestAndCapabilitiesReply(monitor.Handle, buffer, length)) report.AppendLine(Encoding.ASCII.GetString(buffer).TrimEnd('\0'));
                }
            }
            catch (Exception ex) { report.AppendLine("能力表读取失败：" + ex.Message); }
            foreach (var f in Features.All)
                try { var v = Read(monitor, f); report.AppendLine($"{f.Id} 0x{f.Code:X2}: {v.Value}/{v.Maximum}"); }
                catch (Exception ex) { report.AppendLine($"{f.Id} 0x{f.Code:X2}: {ex.Message}"); }
        }
        return report.ToString();
    });
    public void Dispose() { foreach (var item in Devices) item.Dispose(); gate.Dispose(); }
}
