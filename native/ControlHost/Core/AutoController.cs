namespace MonitorLite;

public interface IProfileTarget
{
    string MonitorId { get; }
    Task<bool> GetHdrAsync();
    Task SetHdrAsync(bool enabled);
    Task<Dictionary<string, uint>> ReadAsync();
    Task ApplyAsync(Dictionary<string, uint> values);
    Task SetHdrPresetAsync(uint value);
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
    private bool presetTouched, applyingPreset;
    public HdrPresetRequest? LastPresetRequest { get; private set; }
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
        presetTouched = false; applyingPreset = false; LastPresetRequest = null; CheckPresetReturn();
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
            CheckPresetReturn();
            bool mode = await target.GetHdrAsync();
            bool desired = selected is null ? originalHdr : selected.HdrPolicy == -1 ? mode : selected.HdrPolicy == 1;
            if (mode != desired)
            {
                if (!mode && baselines.TryGetValue(false, out var old)) await target.ApplyAsync(old);
                await target.SetHdrAsync(desired); mode = desired;
            }
            await Capture(mode);
            if (mode)
            {
                if (selected?.HdrPreset is uint preset) await SendPreset(preset);
            }
            else
            {
                var selectedValues = selected?.Values;
                uint? finalPictureMode = selectedValues is not null && selectedValues.TryGetValue("pictureMode", out uint selectedMode)
                    ? selectedMode : baselines[mode].TryGetValue("pictureMode", out uint baseMode) ? baseMode : null;
                var values = baselines[mode].Where(p => Features.BlockReason(p.Key, finalPictureMode, mode) is null).ToDictionary();
                if (selected is not null)
                {
                    var readable = await target.ReadAsync();
                    foreach (var pair in selected.Values)
                    {
                        if (!readable.ContainsKey(pair.Key)) throw new IOException("当前模式无法读取配置参数：" + pair.Key);
                        if (Features.BlockReason(pair.Key, finalPictureMode, mode) is string blocked) throw new InvalidOperationException(blocked + "：" + Features.Get(pair.Key).Name);
                        values[pair.Key] = pair.Value;
                    }
                }
                await target.ApplyAsync(values);
            }
            current = id;
            refreshSelection = false;
            changed = selected is not null;
            Revision++;
            Status = selected is null ? "应用已关闭，已恢复启动前的 HDR 和显示器设置" : (match is null ? "桌面配置：" : "应用配置：") + selected.Name + (mode ? " · HDR" : " · SDR");
        }
        catch
        {
            Running = false;
            if (applyingPreset)
            {
                // A failed/slow preset request may already have blanked the display.
                // Never retry it or issue a rollback SET into that transition.
                applyingPreset = false; changed = false;
                Status = "HDR 预设切换尚未确认，自动切换已暂停，请等待显示器恢复。";
                throw;
            }
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
        Status = presetTouched ? "自动切换已关闭，已应用桌面返回策略；HDR 预设以机身菜单为准。" : "自动切换已关闭，原设置已恢复";
    }
    private async Task Capture(bool mode)
    {
        if (mode) { baselines[true] = []; return; }
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
        var fallback = presetTouched && originalHdr ? RuleResolver.Default(settings, target.MonitorId) : null;
        if (presetTouched && originalHdr && fallback?.HdrPolicy != 0 && fallback?.HdrPreset is null)
            throw new InvalidOperationException("当前 HDR 预设无法读取，请设置关闭 HDR 或指定 HDR 预设的桌面默认配置。");
        bool desired = fallback?.HdrPolicy == 0 ? false : originalHdr;
        if (!mode && baselines.TryGetValue(false, out var currentBank)) await target.ApplyAsync(currentBank);
        if (mode != desired) await target.SetHdrAsync(desired);
        if (desired)
        {
            if (presetTouched && fallback?.HdrPreset is uint preset) await SendPreset(preset);
        }
        else
        {
            await Capture(false);
            var restored = new Dictionary<string, uint>(baselines[false]);
            if (fallback is not null) foreach (var pair in fallback.Values) restored[pair.Key] = pair.Value;
            await target.ApplyAsync(restored);
        }
        changed = false;
    }
    private void CheckPresetReturn()
    {
        bool usesPreset = presetTouched || settings.Rules.Where(r => r.Enabled).Any(r => settings.Profiles.Any(p => p.Id == r.ProfileId && p.MonitorId == target.MonitorId && p.HdrPolicy != 0 && p.HdrPreset is not null));
        var fallback = RuleResolver.Default(settings, target.MonitorId);
        if (originalHdr && usesPreset && fallback?.HdrPolicy != 0 && fallback?.HdrPreset is null)
            throw new InvalidOperationException("当前 HDR 预设无法读取，请设置关闭 HDR 或指定 HDR 预设的桌面默认配置。");
    }
    private async Task SendPreset(uint value)
    {
        HdrPresets.Validate(value); presetTouched = true; applyingPreset = true;
        var sent = DateTimeOffset.Now;
        await target.SetHdrPresetAsync(value);
        applyingPreset = false;
        LastPresetRequest = new(value, target.MonitorId, sent);
    }
}
