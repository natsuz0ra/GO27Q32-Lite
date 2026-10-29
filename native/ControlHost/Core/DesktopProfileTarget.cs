namespace MonitorLite;

internal sealed class DesktopProfileTarget(MonitorService service, MonitorDevice monitor) : IProfileTarget
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
        var snapshot = await service.ReadAllAsync(Current);
        if (await GetHdrAsync() != hdr) throw new IOException("读取配置期间 SDR/HDR 改变，请等待模式稳定。");
        if (!snapshot.Keys.Any(id => Features.Get(id).Automatic && id != "pictureMode"))
            throw new IOException("未能读取任何画面参数，暂不启动或切换应用配置。");
        return snapshot.Where(p => Features.Get(p.Key).Automatic && (!hdr || p.Key != "pictureMode")).ToDictionary(p => p.Key, p => p.Value.Value);
    }
    public Task ApplyAsync(Dictionary<string, uint> values) => service.ApplyAsync(Current, values, true);
}
