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
Check(HdrPresets.Choices.Select(c => c.Name).SequenceEqual(new[] { "HDR显示", "HDR游戏", "HDR电影", "HDR亮彩", "HDRPeak 1300" }), "HDR 五档顺序来自用户机身实测");
var hdrSends = new List<(byte Code, uint Value)>();
HdrPresets.Send(0, (code, value) => hdrSends.Add((code, value)));
HdrPresets.Send(0, (code, value) => hdrSends.Add((code, value)));
HdrPresets.Send(4, (code, value) => hdrSends.Add((code, value)));
Check(hdrSends.SequenceEqual(new[] { ((byte)0xE7, 0u), ((byte)0xE7, 0u), ((byte)0xE7, 4u) }), "HDR 预设仅向 E7 写入，0和相同请求也实际发送");
try { HdrPresets.Send(5, (code, value) => hdrSends.Add((code, value))); throw new Exception("invalid preset accepted"); } catch (InvalidDataException) { }
Check(hdrSends.Count == 3, "超出五档的 HDR 预设在写入前被拒绝");
var hdrRecoverySamples = new Queue<bool>([false, true, false, true, true, true]);
var hdrRecoveryDelays = new List<TimeSpan>();
int hdrRecoveryReads = 0;
bool hdrRecovered = await HdrPresetRecovery.WaitAsync(() => { hdrRecoveryReads++; return Task.FromResult(hdrRecoverySamples.Dequeue()); }, delay => { hdrRecoveryDelays.Add(delay); return Task.CompletedTask; });
Check(hdrRecovered && hdrRecoveryReads == 6 && hdrRecoveryDelays[0] == TimeSpan.FromSeconds(2), "HDR 黑屏恢复先静默，断连会重置稳定计数，连续三次可用才结束");
hdrRecoveryReads = 0;
bool hdrStillWaiting = await HdrPresetRecovery.WaitAsync(() => { hdrRecoveryReads++; return Task.FromResult(false); }, _ => Task.CompletedTask);
Check(!hdrStillWaiting && hdrRecoveryReads == HdrPresetRecovery.Attempts && hdrSends.Count == 3, "恢复等待有界，超时交还后台观察，不重发预设写入");
try { await HdrPresetRecovery.WaitAsync(() => throw new InvalidDataException("different target"), _ => Task.CompletedTask); throw new Exception("target change accepted"); } catch (InvalidDataException) { }
Check(true, "目标身份变化可终止恢复，不会吞掉异常或改绑其他显示器");
Check(GameTimer.Encode(99, 59) == 25403 && GameTimer.Valid(25403) && !GameTimer.Valid(60) && !GameTimer.Valid(100u << 8), "计时器按字节编码，拒绝秒数进位和超过99分钟");
Check(GameTimer.StartTime(1, 99, 59) == 0 && GameTimer.StartTime(2, 0, 0) == 1280, "正计时从零开始，零倒计时按原厂规则设为五分钟");
Check(GameTimer.StartSteps(2, 1280).Select(p => (p.Key, p.Value)).SequenceEqual(new[] { ("timerRunning", 0u), ("timerDuration", 1280u), ("gameTimer", 2u), ("timerRunning", 1u) }) && GameTimer.StartSteps(0, 0).Length == 1, "启动依次暂停、时长、模式、继续，关闭仅写模式");
Check(Features.Get("assistPosition").Choices!.Select(c => c.Value).SequenceEqual(new uint[] {0,1,2,256,257,258}) && !Features.Get("assistPosition").Accepts(3), "辅助位置保留稀疏原始值，不写UI下标");
Check(new[] {"gameTimer", "timerRunning", "timerDuration", "assistPosition"}.All(id => Features.Get(id) is {Automatic:false, DeviceSetting:true}), "第三批控制独立于应用配置和画面撤销");
async Task Twice(AutoController c, params string[] paths) { await c.TickAsync(paths, paths.FirstOrDefault()); await c.TickAsync(paths, paths.FirstOrDefault()); }
Check(Features.Get("gamma").Choices!.Select(c => c.Name).SequenceEqual(new[] { "关闭", "1.8", "2.0", "2.2", "2.4", "2.6" }) && Features.Get("gamma").Choices!.Select(c => c.Value).SequenceEqual(new uint[] { 0, 1, 2, 3, 4, 5 }), "Gamma 物理值按 OSD 顺序显示，保留原协议值与旧配置兼容");
Check(Features.BlockReason("brightness", 9, true) is not null && Features.BlockReason("gamma", 7, true) is not null && Features.BlockReason("crosshair", 0, true) is null, "HDR 禁止常规画面参数，准星等设备功能保留");
Check(Features.BlockReason("pictureMode", 0, true) is not null && Features.BlockReason("brightness", 9, false) is not null, "HDR 拒绝 SDR 预设，同时保留 SDR 已确认锁定");
var p = new Profile { Id = "game", Name = "游戏", MonitorId = "go", Values = new() { ["brightness"] = 80 }, HdrValues = new() { ["brightness"] = 70 }, HdrPreset = 1, HdrPolicy = 1 };
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
Check(fake.Hdr && fake.CurrentPreset == 1 && fake.Values["brightness"] == 20 && fake.RegularHdrWrites == 0, "开启 HDR 只发送预设，不读取或套用旧 HDR 常规参数");
int writes = fake.Writes; await Twice(engine, @"C:\Games\game.exe");
Check(fake.Writes == writes, "同一应用不重复写入");
await Twice(engine, @"C:\Games\game.exe", @"C:\Work\work.exe");
Check(!fake.Hdr && fake.Values["brightness"] == 50 && fake.Values["contrast"] == 30, "高优先级覆盖，恢复上一配置未指定参数");
Check(fake.Banks[true]["brightness"] == 20 && fake.RegularHdrWrites == 0, "离开 HDR 不读取或写入 HDR 常规参数");
await Twice(engine, @"C:\Games\game.exe");
Check(fake.Hdr && fake.CurrentPreset == 1 && fake.RegularHdrWrites == 0, "高优先级应用退出后回退 HDR 预设，不写常规参数");
await Twice(engine);
Check(!fake.Hdr && fake.Values["brightness"] == 50 && fake.Values["contrast"] == 60, "最后一个应用退出恢复原始 HDR 和 SDR 参数");
await Twice(engine, @"C:\Games\game.exe"); await engine.StopAsync();
Check(!fake.Hdr && fake.Values["brightness"] == 50 && !engine.Running, "手动暂停或退出恢复原设置");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); fake.FailNext = true;
try { await Twice(engine, @"C:\Games\game.exe"); } catch (IOException) { }
Check(!engine.Running && !fake.Hdr && fake.Values["brightness"] == 50, "部分写入失败后停止自动切换并尝试恢复");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); fake.FailPreset = true;
try { await Twice(engine, @"C:\Games\game.exe"); } catch (IOException) { }
Check(!engine.Running && fake.Hdr && fake.RegularHdrWrites == 0 && fake.PresetWrites.Count == 1, "HDR 预设未确认时暂停，不重发或进入旧 HDR 参数回滚");
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
Check(!engine.Running && fake.Hdr && fake.CurrentPreset == 1 && fake.Values["brightness"] == 20 && fake.Writes == writes, "手动暂停保留当前画面，之后退出不会撤销用户已接管的状态");
fake = new FakeTarget(); engine = new AutoController(fake, s); await engine.StartAsync(); await Twice(engine, @"C:\Games\game.exe");
var edited = s.Clone(); edited.Profiles.First(p => p.Id == "game").HdrPreset = 2; edited.Rules[1].Priority = 0;
engine.StageSettings(edited); writes = fake.Writes; await Twice(engine, @"C:\Games\game.exe");
Check(fake.CurrentPreset == 1 && fake.Writes == writes, "自动管理期间保存配置不会立即调节画面");
edited.Profiles.First(p => p.Id == "game").HdrPreset = 4;
await Twice(engine, @"C:\Games\game.exe", @"C:\Work\work.exe");
Check(fake.CurrentPreset == 2 && engine.CurrentProfileId == "game" && fake.RegularHdrWrites == 0, "下一次应用变化采用保存时的独立预设快照");
var invalidHdr = s.Clone(); invalidHdr.Profiles[0].HdrPreset = 5;
fake = new FakeTarget(); engine = new AutoController(fake, invalidHdr); await engine.StartAsync();
try { await Twice(engine, @"C:\Games\game.exe"); } catch (InvalidDataException) { }
Check(!engine.Running && fake.RegularHdrWrites == 0 && fake.PresetWrites.Count == 0, "无效 HDR 预设不发送，旧常规参数也不进入回滚");
var hdrStart = new FakeTarget { Hdr = true }; var hdrStartEngine = new AutoController(hdrStart, s);
bool missingFallback = false; try { await hdrStartEngine.StartAsync(); } catch (InvalidOperationException) { missingFallback = true; }
Check(missingFallback && hdrStart.Writes == 0, "HDR 启动且会切换预设时，拒绝猜测不可读的返回预设");
var explicitReturn = s.Clone(); var hdrDesktop = new Profile { Id = "hdr-desktop", MonitorId = "go", HdrPolicy = 1, HdrPreset = 0 };
explicitReturn.Profiles.Add(hdrDesktop); explicitReturn.DefaultProfiles["go"] = hdrDesktop.Id;
hdrStartEngine = new AutoController(hdrStart, explicitReturn); await hdrStartEngine.StartAsync(); await Twice(hdrStartEngine, @"C:\Games\game.exe"); await Twice(hdrStartEngine);
Check(hdrStart.CurrentPreset == 0 && hdrStart.RegularHdrWrites == 0, "应用退出发送明确的 HDR 桌面预设，0 档也发送");
await Twice(hdrStartEngine, @"C:\Games\game.exe"); await hdrStartEngine.StopAsync();
Check(hdrStart.CurrentPreset == 0 && hdrStart.RegularHdrWrites == 0, "退出自动管理恢复明确 HDR 桌面预设，不恢复虚假的亮度基线");
var sdrReturn = explicitReturn.Clone(); sdrReturn.Profiles.Last().HdrPolicy = 0; sdrReturn.Profiles.Last().HdrPreset = null; sdrReturn.Profiles.Last().Values["contrast"] = 37;
var sdrReturnTarget = new FakeTarget { Hdr = true }; var sdrReturnEngine = new AutoController(sdrReturnTarget, sdrReturn);
await sdrReturnEngine.StartAsync(); await Twice(sdrReturnEngine, @"C:\Games\game.exe"); await sdrReturnEngine.StopAsync();
Check(!sdrReturnTarget.Hdr && sdrReturnTarget.Values["contrast"] == 37 && sdrReturnTarget.RegularHdrWrites == 0, "从 HDR 启动也可明确返回 SDR 桌面，常规参数只在 SDR 后写入");
Check(p.ForMode(true).Count == 0 && p.HdrValues["brightness"] == 70, "旧 HDR 参数保留用于导出，但运行时永远不套用");
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
    Check(loaded.Profiles[0].HdrValues["brightness"] == 70 && loaded.Profiles[0].HdrPreset == 1 && loaded.Profiles[0].HdrPolicy == 1, "HDR 预设与策略保存往返，保留旧字段而不丢数据");
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
var migrationRoot = Path.Combine(Path.GetTempPath(), "go27q32-migration-" + Guid.NewGuid().ToString("N"));
try
{
    var previousPath = Path.Combine(migrationRoot, "old", "settings.json");
    var destinationPath = Path.Combine(migrationRoot, "new", "settings.json");
    var previous = new SettingsStore(previousPath); previous.Save(s); previous.Save(s);
    var original = File.ReadAllText(previousPath);
    var migrated = new SettingsStore(destinationPath, previousPath);
    Check(!File.Exists(destinationPath), "构造配置仓库不触发迁移，演示模式不写用户目录");
    Check(migrated.Load().Profiles.Count == s.Profiles.Count && File.ReadAllText(destinationPath) == original, "旧目录首次读取迁移到新目录，配置内容完整保留");
    Check(File.ReadAllText(previousPath) == original && File.Exists(destinationPath + ".bak"), "自动迁移保留原文件及备份");
    var preferred = migrated.Load(); preferred.Language = "en"; migrated.Save(preferred);
    Check(new SettingsStore(destinationPath, previousPath).Load().Language == "en", "已有新目录配置优先，升级不覆盖现有偏好");
    File.WriteAllText(previousPath, "{\"Version\":999}");
    bool rejectedLegacy = false;
    var invalidDestination = Path.Combine(migrationRoot, "invalid", "settings.json");
    try { new SettingsStore(invalidDestination, previousPath).Load(); } catch (InvalidDataException) { rejectedLegacy = true; }
    Check(rejectedLegacy && !File.Exists(invalidDestination), "旧配置未通过验证时不创建迁移目标");
}
finally { if (Directory.Exists(migrationRoot)) Directory.Delete(migrationRoot, true); }
var installRoot = Path.Combine(Path.GetTempPath(), "go27q32-install-language-" + Guid.NewGuid().ToString("N"));
try
{
    Directory.CreateDirectory(installRoot);
    string installedPath = Path.Combine(installRoot, "settings.json");
    string languagePath = installedPath + ".install-language";
    var installed = new SettingsStore(installedPath);
    File.WriteAllText(languagePath, "en");
    Check(installed.Load().Language == "en" && File.Exists(installedPath) && !File.Exists(languagePath), "首次安装采用英文选择并持久保存，只消费一次安装语言");
    var existing = s.Clone(); existing.Language = "en"; existing.Theme = "dark";
    installed.Save(existing);
    File.WriteAllText(languagePath, "zh");
    var chinese = installed.Load();
    var expected = existing.Clone(); expected.Language = "zh";
    Check(JsonSerializer.Serialize(chinese) == JsonSerializer.Serialize(expected), "升级安装改为中文，只改变语言，保留配置库、规则和其他偏好");
    Check(JsonSerializer.Deserialize<Settings>(File.ReadAllText(installedPath + ".bak"))!.Language == "en", "应用安装语言时备份原有配置");
    chinese.Language = "en"; installed.Save(chinese);
    Check(installed.Load().Language == "en", "安装语言消费后，软件内修改的语言不会被下次启动覆盖");
    File.WriteAllText(languagePath, "invalid");
    Check(installed.Load().Language == "en", "无效安装语言不覆盖用户偏好");
    File.WriteAllText(languagePath, "zh");
    File.WriteAllText(installedPath, "{broken");
    try { installed.Load(); throw new Exception("broken settings accepted"); } catch (JsonException) { }
    Check(File.ReadAllText(installedPath) == "{broken" && File.Exists(languagePath), "原配置损坏时保留原文件和待应用语言，不创建空配置覆盖数据");

    string oldPath = Path.Combine(installRoot, "old", "settings.json");
    string newPath = Path.Combine(installRoot, "new", "settings.json");
    new SettingsStore(oldPath).Save(existing);
    Directory.CreateDirectory(Path.GetDirectoryName(newPath)!);
    File.WriteAllText(newPath + ".install-language", "zh");
    var migratedInstall = new SettingsStore(newPath, oldPath).Load();
    Check(JsonSerializer.Serialize(migratedInstall) == JsonSerializer.Serialize(expected) && File.ReadAllText(oldPath).Contains("\"en\""), "安装语言在旧目录配置迁移后应用，旧文件保持原样");
}
finally { if (Directory.Exists(installRoot)) Directory.Delete(installRoot, true); }
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
    public bool FailPreset;
    public uint CurrentPreset;
    public int RegularHdrWrites;
    public List<uint> PresetWrites = [];
    public Dictionary<string, uint> LastApplied = [];
    public Dictionary<bool, Dictionary<string, uint>> Banks = new() { [false] = new() { ["brightness"] = 50, ["contrast"] = 60 }, [true] = new() { ["brightness"] = 20, ["contrast"] = 40 } };
    public Dictionary<string, uint> Values => Banks[Hdr];
    public Task<bool> GetHdrAsync() => Task.FromResult(Hdr);
    public Task SetHdrAsync(bool enabled) { Hdr = enabled; Writes++; HdrSwitches++; return Task.CompletedTask; }
    public Task<Dictionary<string, uint>> ReadAsync() => Task.FromResult(Hdr ? new Dictionary<string, uint>() : new Dictionary<string, uint>(Values));
    public Task SetHdrPresetAsync(uint value) { HdrPresets.Validate(value); PresetWrites.Add(value); Writes++; if (FailPreset) { FailPreset = false; throw new IOException("preset reconnect failed"); } CurrentPreset = value; return Task.CompletedTask; }
    public Task ApplyAsync(Dictionary<string, uint> values)
    {
        LastApplied = new(values);
        if (Hdr) RegularHdrWrites += values.Count;
        foreach (var p in values)
        {
            Values[p.Key] = p.Value; Writes++;
            if (FailNext) { FailNext = false; throw new IOException("simulated partial write"); }
        }
        return Task.CompletedTask;
    }
}
