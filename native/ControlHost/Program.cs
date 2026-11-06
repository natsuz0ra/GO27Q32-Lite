using System.Diagnostics;
using System.Text;
using System.Text.Json;
using MonitorLite;

Console.InputEncoding = Console.OutputEncoding = new UTF8Encoding(false);
using var host = new ControlHost(args.Contains("--demo"));
while (await Console.In.ReadLineAsync() is string line)
{
    int id = 0;
    try
    {
        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement; id = root.GetProperty("id").GetInt32();
        var result = await host.Dispatch(root.GetProperty("method").GetString()!, root.TryGetProperty("args", out var a) ? a : default);
        Console.WriteLine(JsonSerializer.Serialize(new { id, ok = true, result }));
        if (host.Exiting) break;
    }
    catch (Exception ex) { Console.WriteLine(JsonSerializer.Serialize(new { id, ok = false, error = ex.Message })); }
}
await host.Shutdown();

sealed class ControlHost(bool demo) : IDisposable
{
    readonly MonitorService service = new();
    readonly SettingsStore store = new();
    Settings settings = new();
    AutoController? automation;
    Dictionary<string, VcpValue> values = [];
    HdrState? hdr;
    HdrPresetRequest? hdrPresetRequest;
    bool hdrPresetRecovering;
    string? hdrPresetRecoveryTargetPath;
    int hdrPresetRecoveryStable;
    HdrState? hdrPresetRecoveryObservation;
    string monitorId = "", status = "等待连接", activeProfile = "";
    string? hdrError;
    string? automationWarning;
    DateTimeOffset? processCheckedAt;
    string[] matchedPaths = [];
    bool dirty;
    int tick;
    int failedPolls;
    (bool Hdr, Dictionary<string, uint> Values, bool Dirty)? undo;
    MonitorDevice Current => service.Devices.FirstOrDefault(d => d.Id == monitorId && d.IsTarget) ?? throw new IOException("GO27Q32 未连接或活动显示路径已改变，请重新检测。");
    bool Connected => demo || service.Devices.Any(d => d.Id == monitorId && d.IsTarget);
    public bool Exiting { get; private set; }
    public async Task<object> Dispatch(string method, JsonElement args)
    {
        if (hdrPresetRecovering && method is not ("tick" or "state" or "scan" or "settings" or "preferences" or "processes" or "shutdown"))
            throw new InvalidOperationException("正在等待显示器重新连接，请稍候。");
        switch (method)
        {
            case "preferences":
                if (!demo) settings = store.Load();
                return settings;
            case "init":
                if (!demo) settings = store.Load();
                await Scan();
                if (demo) SeedDemo();
                if (!demo && settings.Automatic) await StartWaitingAuto();
                return new { state = State(), settings, features = Features.All, hdrPresets = HdrPresets.Choices, demo };
            case "scan":
                if (hdrPresetRecovering) { await ObservePresetRecovery(); return State(); }
                if (automation?.Running == true) throw new InvalidOperationException("请先暂停自动切换再重新检测。");
                await Scan(); return State();
            case "state":
                if (!demo && Connected && !hdrPresetRecovering) await Read();
                return State();
            case "tick":
                if (hdrPresetRecovering) { await ObservePresetRecovery(); return State(); }
                if (!demo)
                {
                    // Validate/rebind the display before any automatic write.
                    // A disconnected display must not permanently disable the watcher.
                    if (Connected && (settings.LiveSync || settings.Automatic)) await Observe(settings.LiveSync);
                    else if (!Connected)
                    {
                        if (settings.Automatic) { if (++failedPolls >= 3) await RecoverDisplayPath(); }
                        else if (++tick % 10 == 0) await Scan();
                    }
                    if (settings.Automatic && automation?.Running != true) await StartWaitingAuto();
                    if (automation?.Running == true)
                    {
                        var snapshot = ProcessSnapshot.Capture(automation.ObservedRules);
                        processCheckedAt = DateTimeOffset.Now;
                        matchedPaths = snapshot.Paths.Where(path => automation.ObservedRules.Any(r => r.Enabled && r.ExecutablePath.Equals(path, StringComparison.OrdinalIgnoreCase))).Distinct(StringComparer.OrdinalIgnoreCase).Order().ToArray();
                        automationWarning = snapshot.Reliable ? null : "无法核实进程路径：" + string.Join(", ", snapshot.Unreadable) + "；保留当前配置，稍后重试。";
                        bool ready = snapshot.Reliable && Connected && hdr is not null && hdr.Enabled == hdr.ActiveHdr;
                        {
                            int revision = automation.Revision;
                            try { await automation.TickAsync(snapshot.Paths, snapshot.Foreground, ready); }
                            catch { settings.Automatic = false; store.Save(settings); throw; }
                            status = automation.Status;
                            if (automation.Revision != revision) { await Read(); activeProfile = automation.CurrentProfileId ?? ""; dirty = false; undo = null; if (hdr?.ActiveHdr == true && automation.LastPresetRequest is { } sent) hdrPresetRequest = sent; }
                        }
                    }
                }
                return State();
            case "set":
                var feature = Features.Get(args.GetProperty("feature").GetString()!);
                uint v = args.GetProperty("value").GetUInt32();
                if (feature.Id is "gameTimer" or "timerRunning" or "timerDuration") throw new InvalidOperationException("请使用计时器专用命令。");
                if (!feature.Accepts(v)) throw new InvalidDataException("参数超出允许范围。");
                if (feature.DeviceSetting)
                {
                    if (!Connected) throw new IOException("请先连接 GO27Q32。");
                    // Device preferences are independent of picture profiles, HDR and undo.
                    try { values[feature.Id] = demo ? new(v, feature.Max) : await service.SetAsync(Current, feature, v); }
                    catch { if (!demo) await Read(); throw; }
                    status = feature.Name + "已写入并读回确认。";
                    return State();
                }
                Manual();
                await RefreshMode();
                if (hdr?.ActiveHdr == true && feature.Id == "pictureMode") throw new InvalidOperationException("HDR 预设请使用专用切换命令。");
                if (hdr?.ActiveHdr == true && Features.SdrPicture(feature.Id)) throw new InvalidOperationException("HDR 下不支持常规画面调节，请通过机身菜单调整。");
                SaveUndo();
                dirty = true;
                try { values[feature.Id] = demo ? new(v, feature.Max) : await service.SetAsync(Current, feature, v); }
                catch { if (!demo) await Read(); throw; }
                if (!demo && feature.Id == "pictureMode") await Read();
                dirty = true; status = feature.Id == "input" ? "输入源切换请求已发送，当前电脑可能失去连接。" : feature.Name + "已写入并读回确认。"; return State();
            case "hdr":
                bool enabled = args.GetProperty("enabled").GetBoolean();
                RequireConnected(); await RefreshMode(); PauseForManualHdr(); SaveUndo(); dirty = true;
                await SetHdr(enabled); status = "Windows HDR 已切换，已读取对应参数分组。"; return State();
            case "hdrPreset":
                uint preset = args.GetProperty("value").GetUInt32();
                HdrPresets.Validate(preset);
                RequireConnected(); await RefreshMode();
                if (!StableHdr()) throw new InvalidOperationException("请先开启 Windows HDR，并等待显示器进入 HDR 输出。");
                PauseForManualHdr();
                await ApplyHdrPresetRequest(preset);
                return State();
            case "apply":
                Manual(); await RefreshMode(); var profile = settings.Profiles.Single(p => p.Id == args.GetProperty("id").GetString() && p.MonitorId == monitorId);
                bool desired = profile.HdrPolicy < 0 ? StableHdr() : profile.HdrPolicy == 1;
                dirty = true; undo = null;
                if (StableHdr() != desired) await SetHdr(desired);
                var fields = profile.ForMode(desired);
                if (desired && profile.HdrPreset is uint configuredPreset) await ApplyHdrPresetRequest(configuredPreset);
                else if (demo) foreach (var p in fields) values[p.Key] = new(p.Value, Features.Get(p.Key).Max);
                else { if (fields.Count > 0) await service.ApplyAsync(Current, fields, false); await Read(); }
                activeProfile = profile.Id; dirty = false; undo = null; if (!hdrPresetRecovering) status = "已使用「" + profile.Name + "」。"; return State();
            case "undo":
                Manual(); await RefreshMode(); if (undo is not { } previous) throw new InvalidOperationException("没有可撤销的调节。");
                if (StableHdr() != previous.Hdr) await SetHdr(previous.Hdr);
                if (demo) foreach (var p in previous.Values) values[p.Key] = new(p.Value, Features.Get(p.Key).Max);
                else { await service.ApplyAsync(Current, previous.Values, false); await Read(); }
                undo = null; dirty = previous.Dirty; status = "已恢复临时调节前的设置。"; return State();
            case "settings":
                var edited = JsonSerializer.Deserialize<Settings>(args.GetRawText()) ?? throw new InvalidDataException("配置为空。");
                SettingsStore.Validate(edited);
                // Automation is changed only through its lifecycle command.
                edited.Automatic = settings.Automatic;
                if (!demo) store.Save(edited);
                settings = edited; automation?.StageSettings(settings);
                return settings;
            case "automatic":
                automationWarning = null;
                if (args.GetProperty("enabled").GetBoolean()) { if (!Connected) throw new IOException("请先连接显示器。"); if (!demo) await StartAuto(); settings.Automatic = true; status = "等待应用启动。"; }
                else { automation?.Pause(); settings.Automatic = false; status = "已暂停自动切换，保留当前画面。"; }
                if (!demo) store.Save(settings); return State();
            case "timer":
                if (!Connected) throw new IOException("请先连接 GO27Q32。");
                uint timerMode = args.GetProperty("mode").GetUInt32();
                uint duration = GameTimer.StartTime(timerMode, args.GetProperty("minutes").GetInt32(), args.GetProperty("seconds").GetInt32());
                try {
                    if (demo) { values["gameTimer"] = new(timerMode, 2); values["timerRunning"] = new(timerMode == 0 ? 0u : 1u, 1); values["timerDuration"] = new(duration, 9960); }
                    else foreach (var item in await service.ConfigureTimerAsync(Current, timerMode, duration)) values[item.Key] = item.Value;
                } catch { if (!demo) await Read(); throw; }
                status = "计时器已设置并读回确认。"; return State();
            case "timerPause":
                if (!Connected) throw new IOException("请先连接 GO27Q32。");
                bool paused = args.GetProperty("paused").GetBoolean();
                if (demo) {
                    if (values.GetValueOrDefault("gameTimer")?.Value is null or 0) throw new InvalidOperationException("请先启动计时器。");
                    values["timerRunning"] = new(paused ? 0u : 1u, 1);
                } else {
                    try { foreach (var item in await service.PauseTimerAsync(Current, paused)) values[item.Key] = item.Value; }
                    catch { await Read(); throw; }
                }
                status = paused ? "计时器已暂停。" : "计时器已继续。"; return State();
            case "processes":
                return Process.GetProcesses().Select(p => { using (p) { try { return new { name = p.ProcessName, path = ProcessSnapshot.ImagePath(p.Id) }; } catch { return null; } } }).Where(p => p?.path?.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) == true).DistinctBy(p => p!.path).OrderBy(p => p!.name).ToArray();
            case "diagnose": return demo ? "演示模式，不读取硬件。" : await service.DiagnoseAsync() + "\n" + new HdrService().Diagnose();
            case "shutdown": Exiting = true; return new { exiting = true };
            default: throw new InvalidOperationException("未知命令：" + method);
        }
    }
    void RequireConnected() { if (!Connected) throw new IOException("请先连接 GO27Q32。"); }
    void Manual() { RequireConnected(); if (settings.Automatic || automation?.Running == true) throw new InvalidOperationException("请先暂停自动切换。"); }
    void PauseForManualHdr()
    {
        if (!settings.Automatic && automation?.Running != true) return;
        // Pause keeps the current picture; StopAsync would restore the old baseline.
        automation?.Pause(); settings.Automatic = false; automationWarning = null; undo = null;
        if (!demo) store.Save(settings);
    }
    async Task ApplyHdrPresetRequest(uint preset)
    {
        HdrPresets.Validate(preset);
        // Neither profiles nor undo may reinterpret the SDR E7 table as HDR state.
        undo = null; dirty = true; hdrPresetRequest = null;
        if (!demo)
        {
            var device = Current;
            var before = await Task.Run(() => new HdrService().Read(device.Desktop));
            await service.SetHdrPresetAsync(device, preset);
            hdrPresetRequest = new(preset, monitorId, DateTimeOffset.Now);
            hdrPresetRecoveryTargetPath = before.TargetPath;
            hdrPresetRecovering = true; hdrPresetRecoveryStable = 0; hdr = null;
            try
            {
                bool restored = await HdrPresetRecovery.WaitAsync(() => ProbePresetConnection(requireHdr: true));
                hdrPresetRecovering = !restored;
                if (!restored) { hdr = null; status = "HDR 预设请求已发送，显示器仍在重新连接，恢复后会自动更新。"; return; }
            }
            catch { hdrPresetRecovering = false; throw; }
        }
        else hdrPresetRequest = new(preset, monitorId, DateTimeOffset.Now);
        values.Remove("pictureMode");
        status = "HDR 预设切换请求已发送，请以机身菜单为准。";
    }
    async Task<bool> ProbePresetConnection(bool requireHdr)
    {
        HdrState next;
        try
        {
            // Rebuild physical handles each time, retaining the original monitor identity.
            await service.ScanAsync();
            if (!Connected) { hdr = null; return false; }
            next = await Task.Run(() => new HdrService().Read(Current.Desktop));
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { hdr = null; hdrError = null; return false; }
        if (next.TargetPath != hdrPresetRecoveryTargetPath)
            throw new InvalidDataException("HDR 预设请求后目标显示器改变，已停止等待，请检查连接。");
        bool ready = next.Enabled == next.ActiveHdr && (!requireHdr || next.ActiveHdr);
        hdr = ready ? next : null; hdrError = null;
        return ready;
    }
    async Task ObservePresetRecovery()
    {
        try
        {
            // After the initial window, also accept a sustained external switch to SDR.
            bool ready = await ProbePresetConnection(requireHdr: false);
            hdrPresetRecoveryStable = ready ? (hdr == hdrPresetRecoveryObservation ? hdrPresetRecoveryStable + 1 : 1) : 0;
            hdrPresetRecoveryObservation = hdr;
            if (hdrPresetRecoveryStable < HdrPresetRecovery.StableProbes) return;
            hdrPresetRecovering = false;
            if (hdr?.ActiveHdr != true) hdrPresetRequest = null;
            status = "显示器连接已恢复，HDR 预设请以机身菜单为准。";
        }
        catch { hdrPresetRecovering = false; throw; }
    }
    bool StableHdr() { if (hdr is null || hdr.Enabled != hdr.ActiveHdr) throw new IOException("HDR 状态未知或正在切换，请等待稳定。"); return hdr.ActiveHdr; }
    void SaveUndo() { if (undo is null) undo = (StableHdr(), values.Where(p => Features.Get(p.Key).Automatic && Features.BlockReason(p.Key, values.GetValueOrDefault("pictureMode")?.Value, StableHdr()) is null).ToDictionary(p => p.Key, p => p.Value.Value), dirty); }
    async Task RefreshMode()
    {
        if (demo) return;
        var next = await Task.Run(() => new HdrService().Read(Current.Desktop));
        if (hdr?.ActiveHdr != next.ActiveHdr || hdr.Enabled != next.Enabled) { hdr = next; hdrPresetRequest = null; undo = null; await service.ScanAsync(); await Read(); }
        else hdr = next;
        _ = StableHdr();
    }
    async Task StartAuto()
    {
        if (automation?.Running == true) return;
        automation = new AutoController(new DesktopProfileTarget(service, Current, async preset =>
        {
            await ApplyHdrPresetRequest(preset);
            if (hdrPresetRecovering) throw new IOException("HDR 预设切换尚未确认，自动切换已暂停，请等待显示器恢复。");
        }), settings);
        await automation.StartAsync();
    }
    async Task StartWaitingAuto()
    {
        if (!Connected || hdr is null || hdr.Enabled != hdr.ActiveHdr) { status = "等待显示器连接与 HDR 状态稳定"; return; }
        try { await StartAuto(); }
        catch (Exception ex) when (ex is IOException or System.ComponentModel.Win32Exception)
        { hdr = null; hdrError = ex.Message; status = "等待显示器连接与 HDR 状态稳定"; }
        catch (Exception ex) { status = ex.Message; settings.Automatic = false; store.Save(settings); }
    }
    async Task Scan()
    {
        if (demo) { monitorId = "demo-go27q32"; return; }
        await service.ScanAsync();
        if (!service.Devices.Any(d => d.Id == monitorId && d.IsTarget)) monitorId = service.Devices.FirstOrDefault(d => d.IsTarget)?.Id ?? "";
        if (Connected) { await Read(); status = values.Count > 0 ? $"已连接 GO27Q32，已读取 {values.Count} 项参数。" : "已找到 GO27Q32，但未能读取控制参数，请重新检测或检查连接。"; }
        else { values.Clear(); hdr = null; status = "未找到活动的 GO27Q32，请确认扩展显示、唤醒状态及连接。"; }
    }
    async Task Read()
    {
        var device = Current;
        try { hdr = await Task.Run(() => new HdrService().Read(device.Desktop)); hdrError = null; }
        catch (Exception e) { hdr = null; hdrError = e.Message; values.Clear(); return; }
        if (hdr.Enabled != hdr.ActiveHdr) { values.Clear(); return; }
        var snapshot = await service.ReadAllAsync(device, hdr.ActiveHdr);
        try {
            var after = await Task.Run(() => new HdrService().Read(device.Desktop));
            if (hdr is null || hdr.ActiveHdr != after.ActiveHdr || after.Enabled != after.ActiveHdr) { values.Clear(); hdr = after; status = "读取期间 HDR 模式改变，等待稳定后重新同步。"; return; }
            hdr = after;
        } catch (Exception ex) { hdr = null; hdrError = ex.Message; }
        values = snapshot; if (hdr?.ActiveHdr == true) values.Remove("pictureMode");
    }
    async Task SetHdr(bool enabled)
    {
        if (hdr?.ActiveHdr != enabled) hdrPresetRequest = null;
        if (demo) { hdr = new(true, enabled, "demo", enabled); if (enabled) { foreach (var key in values.Keys.Where(Features.SdrPicture).ToArray()) values.Remove(key); } else { foreach (var f in Features.All.Where(f => Features.SdrPicture(f.Id))) values[f.Id] = new(f.Choices is null ? Math.Min(50u, f.Max) : f.Choices[0].Value, f.Max); values["pictureMode"] = new(0, 9); values["gamma"] = new(3, 5); } return; }
        var id = monitorId; await Task.Run(() => new HdrService().Set(Current.Desktop, enabled)); await Task.Delay(1200); await service.ScanAsync(); monitorId = id; await Read();
    }
    async Task RecoverDisplayPath()
    {
        failedPolls = 0;
        if (!settings.Automatic || monitorId.Length == 0) { await Scan(); return; }
        // Preserve the original target and controller baselines across a sleep,
        // input change or topology rebuild. Never bind another monitor here.
        await service.ScanAsync();
        hdr = null; values.Clear(); undo = null;
        if (Connected) await Read();
    }
    async Task Observe(bool readParameters = true)
    {
        var device = Current; HdrState? next;
        try { next = await Task.Run(() => new HdrService().Read(device.Desktop)); hdrError = null; }
        catch (Exception e) {
            hdr = null; hdrError = e.Message; status = "显示路径暂时不可用，正在等待重新连接。";
            if (++failedPolls >= 3) await RecoverDisplayPath();
            return;
        }
        failedPolls = 0;
        if (hdr?.ActiveHdr != next.ActiveHdr || hdr.Enabled != next.Enabled)
        {
            hdrPresetRequest = null;
            hdr = next; undo = null; dirty = true; status = "检测到系统 HDR 改变，已更新参数分组。";
            if (next.Enabled == next.ActiveHdr) { await service.ScanAsync(); await Read(); } return;
        }
        hdr = next;
        if (!readParameters || next.Enabled != next.ActiveHdr) return;
        // Brightness is the most common external OSD edit: check it every tick.
        int pages = (Features.All.Length + 3) / 4;
        var subset = new[] { Features.Get("brightness") }.Concat(Features.All.Skip((tick++ % pages) * 4).Take(4)).Concat(values.GetValueOrDefault("gameTimer")?.Value > 0 ? new[] { Features.Get("gameTimer"), Features.Get("timerRunning"), Features.Get("timerDuration") } : []).DistinctBy(f => f.Id);
        var read = await service.ReadSubsetAsync(device, subset.Where(f => !next.ActiveHdr || !Features.SdrPicture(f.Id)));
        // Do not merge a batch that spans an external SDR/HDR switch.
        var after = await Task.Run(() => new HdrService().Read(device.Desktop));
        if (after.ActiveHdr != next.ActiveHdr || after.Enabled != next.Enabled) { hdr = after; values.Clear(); undo = null; return; }
        if (next.ActiveHdr) foreach (var key in values.Keys.Where(Features.SdrPicture).ToArray()) values.Remove(key);
        if (read.Any(p => !values.TryGetValue(p.Key, out var old) || old != p.Value))
        {
            bool mode = read.TryGetValue("pictureMode", out var m) && values.GetValueOrDefault("pictureMode") != m;
            bool pictureChanged = read.Any(p => !Features.Get(p.Key).DeviceSetting && values.GetValueOrDefault(p.Key) != p.Value);
            foreach (var p in read) values[p.Key] = p.Value;
            if (mode) await Read();
            if (pictureChanged) { undo = null; dirty = true; }
            status = "已同步显示器 OSD 的外部调整。";
        }
    }
    object State() => new { connected = Connected, monitorId, hdr, hdrError, hdrPresetRecovering, hdrPresetRequest = (hdrPresetRecovering || Connected && hdr?.ActiveHdr == true) && hdrPresetRequest?.MonitorId == monitorId ? hdrPresetRequest : null, values, automatic = settings.Automatic, activeProfile, dirty, canUndo = undo is not null, status, automationWarning, processCheckedAt, matchedPaths, desktop = demo ? "HDMI · 示例设备" : Connected ? Current.Desktop : "", updatedAt = DateTimeOffset.Now };
    void SeedDemo()
    {
        hdr = new(true, false, "demo", false); values = Features.All.ToDictionary(f => f.Id, f => new VcpValue(f.Choices is null ? Math.Min(50u, f.Max) : f.Choices[0].Value, f.Max)); values["gamma"] = new(3, 5); values["timerDuration"] = new(0, 9960);
        values["osdTimeout"] = new(2, 5);
        values["joystickUp"] = new(6, 13); values["joystickDown"] = new(1, 13);
        values["joystickLeft"] = new(4, 13); values["joystickRight"] = new(7, 13);
        settings.Profiles = [new() { Id = "daily", Name = "日常", MonitorId = monitorId, HdrPolicy = 0, Values = new() { ["brightness"] = 50, ["contrast"] = 50 } }, new() { Id = "game", Name = "游戏", MonitorId = monitorId, HdrPolicy = 1, HdrPreset = 1 }, new() { Id = "movie", Name = "观影", MonitorId = monitorId, Values = new() { ["brightness"] = 40 } }];
        settings.DefaultProfiles[monitorId] = "daily"; activeProfile = "daily"; status = "演示模式 · 不连接硬件，不保存用户设置。";
    }
    public async Task Shutdown() { if (automation is not null) try { await automation.StopAsync(); } catch (Exception e) { await Console.Error.WriteLineAsync("恢复设置失败：" + e.Message); } }
    public void Dispose() => service.Dispose();
}
