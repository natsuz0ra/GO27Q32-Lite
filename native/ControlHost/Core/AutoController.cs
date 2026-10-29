namespace MonitorLite;

public interface IProfileTarget
{
    string MonitorId { get; }
    Task<bool> GetHdrAsync();
    Task SetHdrAsync(bool enabled);
    Task<Dictionary<string, uint>> ReadAsync();
    Task ApplyAsync(Dictionary<string, uint> values);
}

public sealed class AutoController
{
    private readonly IProfileTarget target;
    private Settings settings;
    private Settings? pendingSettings;
    private HashSet<string>? previousPaths;
    private bool resetWatchSnapshot, refreshSelection;
    private readonly Dictionary<bool, Dictionary<string, uint>> baselines = [];
    private bool originalHdr;
    private string? current;
    private string? candidate;
    private int stable;
    private bool changed;
    public bool Running { get; private set; }
    public string Status { get; private set; } = "自动切换已关闭";
    public string? CurrentProfileId => current;
    public int Revision { get; private set; }
    public AutoController(IProfileTarget target, Settings settings) { this.target = target; this.settings = settings.Clone(); }
    public IEnumerable<AppRule> ObservedRules => settings.Rules.Concat(pendingSettings?.Rules ?? []).ToArray();
    public void StageSettings(Settings edited) { SettingsStore.Validate(edited); pendingSettings = edited.Clone(); resetWatchSnapshot = true; }
    public void Pause()
    {
        Running = false; changed = false; current = candidate = null;
        Status = "已暂停自动切换，保留当前画面";
    }
    public async Task StartAsync()
    {
        var profiles = settings.Rules.Where(r => r.Enabled).Select(r => settings.Profiles.FirstOrDefault(p => p.Id == r.ProfileId && p.MonitorId == target.MonitorId)).OfType<Profile>().ToList();
        if (profiles.Count == 0) throw new InvalidOperationException("请先为这台显示器添加至少一条应用规则");
        baselines.Clear(); originalHdr = await target.GetHdrAsync();
        await Capture(originalHdr);
        current = candidate = null; previousPaths = null; stable = 0; changed = false; refreshSelection = false; Running = true;
        Status = "等待应用启动";
    }
    public async Task TickAsync(IEnumerable<string> running, string? foreground, bool outputReady = true)
    {
        if (!Running) return;
        if (!outputReady)
        {
            candidate = null; stable = 0;
            Status = "等待显示器连接与 HDR 状态稳定";
            return;
        }
        var paths = new HashSet<string>(running, StringComparer.OrdinalIgnoreCase);
        if (resetWatchSnapshot) { previousPaths = paths; resetWatchSnapshot = false; }
        if (pendingSettings is not null && previousPaths is not null && !paths.SetEquals(previousPaths))
        {
            settings = pendingSettings; pendingSettings = null;
            // A saved edit takes effect at the next observed application lifecycle change.
            candidate = null; stable = 0; refreshSelection = true;
        }
        previousPaths = paths;
        var match = RuleResolver.Resolve(settings, target.MonitorId, paths, foreground);
        var selected = match ?? RuleResolver.Default(settings, target.MonitorId);
        var id = selected?.Id;
        if (id != candidate) { candidate = id; stable = 1; return; }
        if (++stable < 2 || (id == current && !refreshSelection)) return;
        changed = true; // Also restore on a partially failed multi-parameter write.
        try
        {
            bool mode = await target.GetHdrAsync();
            bool desired = selected is null ? originalHdr : selected.HdrPolicy == -1 ? mode : selected.HdrPolicy == 1;
            if (desired && selected?.HdrValues.ContainsKey("pictureMode") == true) throw new InvalidDataException("HDR 专用画面预设协议尚未确认，请编辑配置移除该字段");
            if (mode != desired)
            {
                if (baselines.TryGetValue(mode, out var old)) await target.ApplyAsync(old);
                await target.SetHdrAsync(desired); mode = desired;
            }
            await Capture(mode);
            var selectedValues = selected?.ForMode(mode);
            uint? finalPictureMode = selectedValues is not null && selectedValues.TryGetValue("pictureMode", out uint selectedMode)
                ? selectedMode : baselines[mode].TryGetValue("pictureMode", out uint baseMode) ? baseMode : null;
            var values = baselines[mode].Where(p => Features.BlockReason(p.Key, finalPictureMode, mode) is null).ToDictionary();
            if (selected is not null)
            {
                var readable = await target.ReadAsync();
                foreach (var pair in selected.ForMode(mode))
                {
                    if (!readable.ContainsKey(pair.Key)) throw new IOException("当前模式无法读取配置参数：" + pair.Key);
                    if (Features.BlockReason(pair.Key, finalPictureMode, mode) is string blocked) throw new InvalidOperationException(blocked + "：" + Features.Get(pair.Key).Name);
                    values[pair.Key] = pair.Value;
                }
            }
            await target.ApplyAsync(values);
            current = id;
            refreshSelection = false;
            changed = selected is not null;
            Revision++;
            Status = selected is null ? "应用已关闭，已恢复启动前的 HDR 和显示器设置" : (match is null ? "桌面配置：" : "应用配置：") + selected.Name + (mode ? " · HDR" : " · SDR");
        }
        catch
        {
            Running = false;
            Status = "切换失败，自动切换已暂停；正在恢复原设置";
            try { await Restore(); Status = "切换失败，自动切换已暂停；原设置已恢复"; }
            catch { Status = "切换及恢复失败，请重新连接显示器后重试恢复"; }
            throw;
        }
    }
    public async Task StopAsync()
    {
        Running = false;
        await Restore();
        current = candidate = null;
        Status = "自动切换已关闭，原设置已恢复";
    }
    private async Task Capture(bool mode)
    {
        if (!baselines.ContainsKey(mode))
        {
            var values = await target.ReadAsync();
            uint? pictureMode = values.TryGetValue("pictureMode", out uint value) ? value : null;
            baselines[mode] = values.Where(p => Features.Get(p.Key).Automatic && Features.BlockReason(p.Key, pictureMode, mode) is null).ToDictionary();
        }
    }
    private async Task Restore()
    {
        if (!changed) return;
        bool mode = await target.GetHdrAsync();
        if (baselines.TryGetValue(mode, out var currentBank)) await target.ApplyAsync(currentBank);
        if (mode != originalHdr)
        {
            await target.SetHdrAsync(originalHdr);
            await target.ApplyAsync(baselines[originalHdr]);
        }
        changed = false;
    }
}
