using MonitorLite;
using System.Text.Json;
using System.Diagnostics;

if (args.Length == 2 && args[0] == "--contract")
{
    File.WriteAllText(args[1], JsonSerializer.Serialize(Features.All, new JsonSerializerOptions { WriteIndented = true }));
    return;
}

int count = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception("FAIL: " + name); Console.WriteLine("PASS: " + name); count++; }
Check(GameTimer.Encode(99, 59) == 25403 && GameTimer.Valid(25403) && !GameTimer.Valid(60) && !GameTimer.Valid(100u << 8), "计时器按字节编码，拒绝秒数进位和超过99分钟");
Check(GameTimer.StartTime(1, 99, 59) == 0 && GameTimer.StartTime(2, 0, 0) == 1280, "正计时从零开始，零倒计时按原厂规则设为五分钟");
Check(GameTimer.StartSteps(2, 1280).Select(p => (p.Key, p.Value)).SequenceEqual(new[] { ("timerRunning", 0u), ("timerDuration", 1280u), ("gameTimer", 2u), ("timerRunning", 1u) }) && GameTimer.StartSteps(0, 0).Length == 1, "启动依次暂停、时长、模式、继续，关闭仅写模式");
Check(Features.Get("assistPosition").Choices!.Select(c => c.Value).SequenceEqual(new uint[] {0,1,2,256,257,258}) && !Features.Get("assistPosition").Accepts(3), "辅助位置保留稀疏原始值，不写UI下标");
Check(new[] {"gameTimer", "timerRunning", "timerDuration", "assistPosition"}.All(id => Features.Get(id) is {Automatic:false, DeviceSetting:true}), "第三批控制独立于应用配置和画面撤销");
async Task Twice(AutoController c, params string[] paths) { await c.TickAsync(paths, paths.FirstOrDefault()); await c.TickAsync(paths, paths.FirstOrDefault()); }
Check(Features.Get("gamma").Choices!.Select(c => c.Name).SequenceEqual(new[] { "关闭", "1.8", "2.0", "2.2", "2.4", "2.6" }) && Features.Get("gamma").Choices!.Select(c => c.Value).SequenceEqual(new uint[] { 0, 1, 2, 3, 4, 5 }), "Gamma 物理值按 OSD 顺序显示，保留原协议值与旧配置兼容");
Check(Features.BlockReason("brightness", 9, true) is null && Features.BlockReason("gamma", 7, true) is null, "HDR 原始 E7 值不套用 SDR 的 ECO/sRGB 锁定");
Check(Features.BlockReason("pictureMode", 0, true) is not null && Features.BlockReason("brightness", 9, false) is not null, "HDR 拒绝 SDR 预设，同时保留 SDR 已确认锁定");
var p = new Profile { Id = "game", Name = "游戏", MonitorId = "go", Values = new() { ["brightness"] = 80 }, HdrValues = new() { ["brightness"] = 70 }, HdrPolicy = 1 };
var b = new Profile { Id = "work", Name = "工作", MonitorId = "go", Values = new() { ["contrast"] = 30 }, HdrPolicy = 0 };
var s = new Settings { Profiles = [p, b], Rules = [new() { ExecutablePath = @"C:\Games\game.exe", ProfileId = "game", Priority = 10 }, new() { ExecutablePath = @"C:\Work\work.exe", ProfileId = "work", Priority = 20 }] };
Check(RuleResolver.Resolve(s, "go", [@"C:\Other\game.exe"], null) is null, "完整路径匹配，避免同名应用误切换");
Check(RuleResolver.Resolve(s, "other", [@"C:\Games\game.exe"], null) is null, "显示器配置隔离");
Check(RuleResolver.Resolve(s, "go", [@"c:\games\GAME.exe"], null) == p, "Windows 路径忽略大小写");
Check(RuleResolver.Resolve(s, "go", [@"C:\Games\game.exe", @"C:\Work\work.exe"], @"C:\Games\game.exe") == b, "高优先级优先于前台");
s.Rules[1].Priority = 10;
Check(RuleResolver.Resolve(s, "go", [@"C:\Games\game.exe", @"C:\Work\work.exe"], @"C:\Work\work.exe") == p, "同优先级按规则列表顺序选择，不随前台焦点跳变");
s.Rules[1].Priority = 20;
var fake = new FakeTarget(); var engine = new AutoController(fake, s);
await engine.StartAsync(); await Twice(engine);
Check(fake.Writes == 0 && !fake.Hdr, "启用自动切换时只读取，不改变设置");
var recoveringTarget = new FakeTarget(); var recovering = new AutoController(recoveringTarget, s);
await recovering.StartAsync(); await Twice(recovering, @"C:\Games\game.exe");
int beforeDisconnect = recoveringTarget.Writes;
await recovering.TickAsync([], null, false); await recovering.TickAsync([], null, false);
Check(recovering.Running && recoveringTarget.Writes == beforeDisconnect && recovering.CurrentProfileId == "game", "显示路径暂时不可用时保留自动化和原始基线，不写显示器");
await Twice(recovering);
Check(!recoveringTarget.Hdr && recoveringTarget.Values["brightness"] == 50 && recoveringTarget.Values["contrast"] == 60, "路径恢复后重新稳定检测并恢复最初基线，而非重采临时画面");
await engine.TickAsync([@"C:\Games\game.exe"], null);
Check(fake.Writes == 0, "进程稳定两轮才切换");
await engine.TickAsync([@"C:\Games\game.exe"], null);
Check(fake.Hdr && fake.Values["brightness"] == 70, "开启 HDR 后使用 HDR 参数");
int writes = fake.Writes; await Twice(engine, @"C:\Games\game.exe");
Check(fake.Writes == writes, "同一应用不重复写入");
await Twice(engine, @"C:\Games\game.exe", @"C:\Work\work.exe");
Check(!fake.Hdr && fake.Values["brightness"] == 50 && fake.Values["contrast"] == 30, "高优先级覆盖，恢复上一配置未指定参数");
Check(fake.Banks[true]["brightness"] == 20, "离开 HDR 时恢复 HDR 原始参数");
await Twice(engine, @"C:\Games\game.exe");
Check(fake.Hdr && fake.Values["brightness"] == 70, "高优先级应用退出后回退到仍运行的应用");
await Twice(engine);
Check(!fake.Hdr && fake.Values["brightness"] == 50 && fake.Values["contrast"] == 60, "最后一个应用退出恢复原始 HDR 和 SDR 参数");
await Twice(engine, @"C:\Games\game.exe"); await engine.StopAsync();
Check(!fake.Hdr && fake.Values["brightness"] == 50 && !engine.Running, "手动暂停或退出恢复原设置");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); fake.FailNext = true;
try { await Twice(engine, @"C:\Games\game.exe"); } catch (IOException) { }
Check(!engine.Running && !fake.Hdr && fake.Values["brightness"] == 50, "部分写入失败后停止自动切换并尝试恢复");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); fake.FailHdrProfile = true;
try { await Twice(engine, @"C:\Games\game.exe"); } catch (IOException) { }
Check(!engine.Running && !fake.Hdr && fake.Banks[true]["brightness"] == 20 && fake.Values["brightness"] == 50, "HDR 已切换且参数写入中途失败时恢复两个分组和 HDR 开关");
var srgb = new Profile { Id = "srgb", MonitorId = "go", HdrPolicy = 0, Values = new() { ["pictureMode"] = 7, ["brightness"] = 40 } };
var modeSettings = new Settings { Profiles = [srgb], Rules = [new() { ExecutablePath = @"C:\color.exe", ProfileId = "srgb" }] };
fake = new FakeTarget(); fake.Values["pictureMode"] = 0; engine = new AutoController(fake, modeSettings); await engine.StartAsync();
await Twice(engine, @"C:\color.exe");
Check(fake.Values["pictureMode"] == 7 && fake.Values["brightness"] == 40 && !fake.LastApplied.ContainsKey("contrast"), "切换 sRGB 不把标准模式的锁定参数混入请求");
await Twice(engine);
Check(fake.Values["pictureMode"] == 0 && fake.Values["brightness"] == 50 && fake.Values["contrast"] == 60, "从 sRGB 恢复原模式及可写参数");
Check(Features.BlockReason("brightness", 7) is null && Features.BlockReason("contrast", 7) is not null, "与原厂相同：sRGB 保留亮度并锁定对比度");
Check(Features.BlockReason("brightness", 9) is not null && Features.BlockReason("contrast", 9) is null, "GO27Q32 实际分支：ECO 仅锁亮度，对比度走 sRGB_Not");
var fallbackSettings = s.Clone();
var desktop = new Profile { Id = "desktop", Name = "日常", MonitorId = "go", HdrPolicy = 0, Values = new() { ["brightness"] = 42 } };
fallbackSettings.Profiles.Add(desktop); fallbackSettings.DefaultProfiles["go"] = desktop.Id;
fake = new FakeTarget(); engine = new AutoController(fake, fallbackSettings); await engine.StartAsync(); await Twice(engine);
Check(!fake.Hdr && fake.Values["brightness"] == 42, "没有匹配应用时使用显式桌面默认配置");
await Twice(engine, @"C:\Games\game.exe"); await Twice(engine);
Check(!fake.Hdr && fake.Values["brightness"] == 42, "游戏退出回到默认桌面配置，而非遗留游戏 HDR");
await Twice(engine, @"C:\Games\game.exe"); writes = fake.Writes; engine.Pause(); await engine.StopAsync();
Check(!engine.Running && fake.Hdr && fake.Values["brightness"] == 70 && fake.Writes == writes, "手动暂停保留当前画面，之后退出不会撤销用户已接管的状态");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); await Twice(engine, @"C:\Games\game.exe");
var edited = s.Clone(); edited.Profiles.First(p => p.Id == "game").HdrValues["brightness"] = 55; edited.Rules[1].Priority = 0;
engine.StageSettings(edited); writes = fake.Writes; await Twice(engine, @"C:\Games\game.exe");
Check(fake.Values["brightness"] == 70 && fake.Writes == writes, "自动管理期间保存配置不会立即调节画面");
edited.Profiles.First(p => p.Id == "game").HdrValues["brightness"] = 99;
await Twice(engine, @"C:\Games\game.exe", @"C:\Work\work.exe");
Check(fake.Values["brightness"] == 55 && engine.CurrentProfileId == "game", "下一次应用变化采用保存时的独立快照，同一配置ID也能更新");
var invalidHdr = s.Clone(); invalidHdr.Profiles[0].HdrValues["pictureMode"] = 1;
fake = new FakeTarget(); engine = new AutoController(fake, invalidHdr); await engine.StartAsync();
try { await Twice(engine, @"C:\Games\game.exe"); } catch (InvalidDataException) { }
Check(!engine.Running && !fake.Hdr && fake.HdrSwitches == 0, "拒绝将 SDR 画面预设表用于 HDR 专用预设，切换前即报错");
var legacy = JsonSerializer.Deserialize<Settings>("{\"Version\":1,\"Profiles\":[],\"Rules\":[],\"Automatic\":false}")!;
SettingsStore.Validate(legacy);
Check(legacy.DefaultProfiles.Count == 0 && legacy.MinimizeToTray && legacy.Theme == "system", "旧版配置自动使用兼容的新增偏好默认值");
Check(legacy.LiveSync, "旧版配置默认开启实时同步，新字段不破坏兼容");
Check(Settings.InitialLanguage("zh-CN") == "zh" && Settings.InitialLanguage("zh-TW") == "zh" && Settings.InitialLanguage("en-US") == "en" && Settings.InitialLanguage("ja-JP") == "en", "首次语言：中文系统用中文，其余语言用英文");
var path = Path.Combine(Path.GetTempPath(), "go27q32-tests-" + Guid.NewGuid() + ".json");
try
{
    var store = new SettingsStore(path); store.Save(s); var loaded = store.Load();
    loaded.Language = "en"; store.Save(loaded);
    Check(store.Load().Language == "en", "软件语言偏好保存后不再跟随系统默认值");
    Check(loaded.Profiles[0].HdrValues["brightness"] == 70 && loaded.Profiles[0].HdrPolicy == 1, "SDR/HDR 分组与策略保存往返");
    store.Save(s); Check(File.Exists(path + ".bak"), "原子保存保留备份");
    loaded.Profiles[0].Values["brightness"] = 999;
    bool rejected = false; try { store.Save(loaded); } catch (InvalidDataException) { rejected = true; }
    Check(rejected && store.Load().Profiles[0].Values["brightness"] == 80, "拒绝越界配置且保留原文件");
    var hdrOnly = new Settings { Profiles = [new Profile { MonitorId = "go", HdrPolicy = 1 }] };
    SettingsStore.Validate(hdrOnly); Check(true, "支持只设置 HDR 开关的配置");
    hdrOnly.Profiles[0].Values["input"] = 1; rejected = false;
    try { SettingsStore.Validate(hdrOnly); } catch (InvalidDataException) { rejected = true; }
    Check(rejected, "禁止配置自动切换输入源");
}
finally { foreach (string file in new[] { path, path + ".bak", path + ".tmp" }) if (File.Exists(file)) File.Delete(file); }
if (OperatingSystem.IsWindows())
{
    Check(ProcessSnapshot.ImagePath(Environment.ProcessId).Equals(Environment.ProcessPath, StringComparison.OrdinalIgnoreCase), "有限进程权限查询实际运行路径，不枚举模块");
    string watcher = Path.Combine(Path.GetTempPath(), "go-watch-" + Guid.NewGuid().ToString("N") + ".exe");
    File.Copy(Path.Combine(Environment.SystemDirectory, "cmd.exe"), watcher);
    Process? child = null;
    try
    {
        var profile = new Profile { Id = "watch", MonitorId = "go", HdrPolicy = 0, Values = new() { ["brightness"] = 81 } };
        var config = new Settings { Profiles = [profile], Rules = [new() { ExecutablePath = watcher, ProfileId = profile.Id }] };
        var target = new FakeTarget(); var control = new AutoController(target, config); await control.StartAsync();
        child = Process.Start(new ProcessStartInfo(watcher, "/d /c ping -n 30 127.0.0.1 >nul") { UseShellExecute = false, CreateNoWindow = true })!;
        var snapshot = ProcessSnapshot.Capture(config.Rules);
        Check(snapshot.Reliable && snapshot.Paths.Any(p => p.Equals(watcher, StringComparison.OrdinalIgnoreCase)), "读取真实启动的测试进程并精确匹配路径");
        await control.TickAsync(snapshot.Paths, null); await control.TickAsync(snapshot.Paths, null);
        Check(target.Values["brightness"] == 81 && control.CurrentProfileId == "watch", "真实进程启动通过检测器触发配置，使用模拟显示器");
        var denied = ProcessSnapshot.Capture(config.Rules, _ => throw new System.ComponentModel.Win32Exception(5));
        Check(!denied.Reliable && denied.Unreadable.Contains(Path.GetFileName(watcher)) && denied.Paths.Count == 0, "受限进程显式报告未知状态，不冒充退出或按名称猜测匹配");
        child.Kill(true); await child.WaitForExitAsync();
        snapshot = ProcessSnapshot.Capture(config.Rules);
        await control.TickAsync(snapshot.Paths, null); await control.TickAsync(snapshot.Paths, null);
        Check(snapshot.Reliable && target.Values["brightness"] == 50 && control.CurrentProfileId is null, "真实测试进程退出后恢复模拟显示器的原始配置");
    }
    finally
    {
        if (child is not null) { if (!child.HasExited) { child.Kill(true); await child.WaitForExitAsync(); } child.Dispose(); }
        File.Delete(watcher);
    }
}
Console.WriteLine($"{count} checks passed. No hardware writes.");

sealed class FakeTarget : IProfileTarget
{
    public string MonitorId => "go";
    public bool Hdr;
    public int Writes;
    public int HdrSwitches;
    public bool FailNext;
    public bool FailHdrProfile;
    public Dictionary<string, uint> LastApplied = [];
    public Dictionary<bool, Dictionary<string, uint>> Banks = new() { [false] = new() { ["brightness"] = 50, ["contrast"] = 60 }, [true] = new() { ["brightness"] = 20, ["contrast"] = 40 } };
    public Dictionary<string, uint> Values => Banks[Hdr];
    public Task<bool> GetHdrAsync() => Task.FromResult(Hdr);
    public Task SetHdrAsync(bool enabled) { Hdr = enabled; Writes++; HdrSwitches++; return Task.CompletedTask; }
    public Task<Dictionary<string, uint>> ReadAsync() => Task.FromResult(new Dictionary<string, uint>(Values));
    public Task ApplyAsync(Dictionary<string, uint> values)
    {
        LastApplied = new(values);
        foreach (var p in values)
        {
            Values[p.Key] = p.Value; Writes++;
            if (FailNext) { FailNext = false; throw new IOException("simulated partial write"); }
            if (FailHdrProfile && Hdr && p.Key == "brightness" && p.Value == 70) { FailHdrProfile = false; throw new IOException("simulated HDR profile failure"); }
        }
        return Task.CompletedTask;
    }
}
