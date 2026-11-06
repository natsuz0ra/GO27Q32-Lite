namespace MonitorLite;

internal sealed class DesktopProfileTarget(MonitorService service, MonitorDevice monitor, Func<uint, Task>? requestPreset = null) : IProfileTarget
{
    public string MonitorId { get; } = monitor.Id;
    private MonitorDevice Current => service.Devices.FirstOrDefault(d => d.Id == MonitorId) ?? throw new IOException("显示器已断开，请暂停自动切换后重新检测");
    public Task<bool> GetHdrAsync() => Task.Run(() =>
    {
        var state = new HdrService().Read(Current.Desktop);
        if (state.Enabled != state.ActiveHdr) throw new IOException("HDR 开关与实际输出模式尚未一致，暂不切换或保存错误的参数分组，请等待模式稳定后重试");
        return state.Enabled;
    });
    public async Task SetHdrAsync(bool enabled)
    {
        string desktop = Current.Desktop;
        await Task.Run(() => new HdrService().Set(desktop, enabled));
        await Task.Delay(1200);
        await service.ScanAsync();
        _ = Current;
    }
    public async Task<Dictionary<string, uint>> ReadAsync()
    {
        bool hdr = await GetHdrAsync();
        if (hdr) return []; // Never capture SDR-shadow readings as an HDR baseline.
        var snapshot = await service.ReadAllAsync(Current);
        if (await GetHdrAsync() != hdr) throw new IOException("读取配置期间 SDR/HDR 改变，请等待模式稳定。");
        if (!snapshot.Keys.Any(id => Features.Get(id).Automatic && id != "pictureMode"))
            throw new IOException("未能读取任何画面参数，暂不启动或切换应用配置。");
        return snapshot.Where(p => Features.Get(p.Key).Automatic && (!hdr || p.Key != "pictureMode")).ToDictionary(p => p.Key, p => p.Value.Value);
    }
    public Task ApplyAsync(Dictionary<string, uint> values) => service.ApplyAsync(Current, values, true);
    public async Task SetHdrPresetAsync(uint value)
    {
        if (requestPreset is not null) { await requestPreset(value); return; }
        var before = new HdrService().Read(Current.Desktop);
        await service.SetHdrPresetAsync(Current, value);
        bool restored = await HdrPresetRecovery.WaitAsync(async () =>
        {
            HdrState next;
            try { await service.ScanAsync(); next = new HdrService().Read(Current.Desktop); }
            catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { return false; }
            if (next.TargetPath != before.TargetPath) throw new InvalidDataException("HDR 预设请求后目标显示器改变，已停止等待，请检查连接。");
            return next.Enabled && next.ActiveHdr;
        });
        if (!restored) throw new IOException("HDR 预设切换尚未确认，自动切换已暂停，请等待显示器恢复。");
    }
}
