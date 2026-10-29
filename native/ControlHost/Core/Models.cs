using System.Text.Json;

namespace MonitorLite;

public sealed record Choice(uint Value, string Name)
{
    public override string ToString() => Name;
}

/// <summary>Confirmed VCP reading: current value and the maximum the display reports.</summary>
public sealed record VcpValue(uint Value, uint Maximum);

public sealed record Feature(string Id, string Name, byte Code, uint Max, Choice[]? Choices = null, bool Automatic = true, bool DeviceSetting = false, bool PackedTime = false)
{
    public bool Accepts(uint value) => PackedTime ? GameTimer.Valid(value) : Choices is null ? value <= Max : Choices.Any(x => x.Value == value);
}

public static class GameTimer
{
    public static bool Valid(uint packed) => (packed >> 8) <= 99 && (packed & 255) <= 59;
    public static uint Encode(int minutes, int seconds)
    {
        if (minutes is < 0 or > 99 || seconds is < 0 or > 59) throw new InvalidDataException("计时器时长须为 00:00–99:59。");
        return (uint)((minutes << 8) | seconds);
    }
    public static uint StartTime(uint mode, int minutes, int seconds)
    {
        if (mode > 2) throw new InvalidDataException("未知的计时模式。");
        uint packed = Encode(minutes, seconds);
        return mode != 2 ? 0 : packed == 0 ? Encode(5, 0) : packed;
    }
    public static KeyValuePair<string, uint>[] StartSteps(uint mode, uint duration)
    {
        if (mode > 2 || !Valid(duration)) throw new InvalidDataException("计时器参数无效。");
        return mode == 0 ? [new("gameTimer", 0)] : [new("timerRunning", 0), new("timerDuration", mode == 1 ? 0 : duration), new("gameTimer", mode), new("timerRunning", 1)];
    }
}

public static class Features
{
    // Source: supplied Sidekick -> HDMI_LIB/MS_HUB.cs and model-specific DDC.cs routing.
    private static Choice[] Labels(params string[] names) => names.Select((n, i) => new Choice((uint)i, n)).ToArray();
    // QuickSwitchType 23: these are command values, never dropdown indices.
    private static readonly Choice[] JoystickChoices = [
        new(13, "Ultra Clear"), new(1, "黑平衡"), new(10, "准星"),
        new(3, "音量"), new(9, "音频"), new(4, "输入源"),
        new(5, "对比度"), new(6, "亮度"), new(7, "画面模式")
    ];
    public static readonly Feature[] All = [
        new("brightness", "亮度", 0x10, 100),
        new("contrast", "对比度", 0x12, 100),
        new("pictureMode", "画面模式", 0xE7, 9, Labels("标准", "FPS", "MOBA", "RPG", "竞速", "电影", "阅读", "sRGB", "自定义", "ECO")),
        new("sharpness", "锐度", 0x87, 10),
        new("blackEqualizer", "黑平衡", 0xE3, 20),
        new("colorVibrance", "色彩鲜艳度", 0xE8, 20),
        new("gamma", "Gamma", 0xE9, 5, Labels("关闭", "1.8", "2.0", "2.2", "2.4", "2.6")),
        new("colorTemperature", "色温", 0xEA, 3, Labels("冷色", "自然", "正常", "暖色")),
        new("lowBlueLight", "低蓝光", 0xEE, 10),
        new("superResolution", "超级分辨率", 0xE4, 4),
        new("overdrive", "过驱", 0xE5, 4, Labels("关闭", "Smart OD", "画质", "均衡", "速度")),
        new("freeSync", "FreeSync", 0xED, 1, Labels("关闭", "开启")),
        new("refreshOverlay", "刷新率显示", 0xEB, 1, Labels("关闭", "开启")),
        new("crosshair", "准星", 0xEF, 4, Labels("关闭", "准星 1", "准星 2", "准星 3", "准星 4")),
        new("volume", "耳机音量", 0x62, 100),
        new("input", "输入源（会改变连接）", 0xF0, 3, Labels("HDMI 1", "HDMI 2", "DisplayPort", "USB-C"), false),
        new("osdTimeout", "OSD 显示时间", 0xF2, 5, Labels("5 秒", "10 秒", "15 秒", "20 秒", "25 秒", "30 秒"), false, true),
        new("osdTransparency", "OSD 透明度", 0xF3, 4, Labels("0%", "20%", "40%", "60%", "80%"), false, true),
        new("joystickUp", "摇杆向上", 0xF4, 13, JoystickChoices, false, true),
        new("joystickDown", "摇杆向下", 0xF5, 13, JoystickChoices, false, true),
        new("joystickLeft", "摇杆向左", 0xF6, 13, JoystickChoices, false, true),
        new("joystickRight", "摇杆向右", 0xF7, 13, JoystickChoices, false, true),
        new("ledIndicator", "电源指示灯", 0xF8, 2, Labels("开启", "关闭", "仅待机时开启"), false, true),
        new("gameTimer", "游戏计时器", 0xF9, 2, Labels("关闭", "正计时", "倒计时"), false, true),
        new("timerRunning", "计时状态", 0xFA, 1, Labels("暂停", "继续"), false, true),
        new("timerDuration", "计时器时间", 0xFB, 25403, null, false, true, true),
        new("assistPosition", "游戏辅助位置", 0xFD, 258, [new(0, "左上"), new(1, "左中"), new(2, "左下"), new(256, "右上"), new(257, "右中"), new(258, "右下")], false, true)
    ];
    public static Feature Get(string id) => All.FirstOrDefault(f => f.Id == id) ?? throw new InvalidDataException("未知控制项：" + id);
    public static string? BlockReason(string id, uint? pictureMode, bool activeHdr = false)
    {
        // Raw E7 values in HDR are not the SDR sRGB/ECO enum.
        if (activeHdr) return id == "pictureMode" ? "HDR 专用预设协议尚未核实，请通过机身菜单切换" : null;
        // GO27Q32 fun=0x67E: contrast follows sRGB_Not, not Standard_Contrast.
        // OSD.Change_Event_Switch(PictureModeType=2) + A0_6E ItemEnabled assignments.
        if (pictureMode == 7 && id is "contrast" or "sharpness" or "blackEqualizer" or "colorVibrance" or "gamma" or "colorTemperature" or "lowBlueLight" or "superResolution" or "overdrive")
            return "sRGB 模式锁定此参数";
        if (pictureMode == 9 && id == "brightness") return "ECO 模式锁定亮度";
        return null;
    }
    public static IEnumerable<KeyValuePair<string, uint>> Ordered(Dictionary<string, uint> values) =>
        values.OrderBy(x => x.Key == "pictureMode" ? 0 : x.Key == "input" ? 2 : 1);
}

public sealed class Profile
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "新配置";
    public string MonitorId { get; set; } = "";
    public Dictionary<string, uint> Values { get; set; } = [];
    public Dictionary<string, uint> HdrValues { get; set; } = [];
    public int HdrPolicy { get; set; } = -1;
    public Dictionary<string, uint> ForMode(bool hdr) => hdr ? HdrValues : Values;
    public override string ToString() => Name;
}

public sealed class AppRule
{
    public bool Enabled { get; set; } = true;
    public string ExecutablePath { get; set; } = "";
    public string ProfileId { get; set; } = "";
    public int Priority { get; set; } = 10;
}

public sealed class Settings
{
    public static string InitialLanguage(string systemLanguage) => systemLanguage.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh" : "en";
    public string Language { get; set; } = InitialLanguage(System.Globalization.CultureInfo.CurrentUICulture.Name);
    public int Version { get; set; } = 1;
    public List<Profile> Profiles { get; set; } = [];
    public List<AppRule> Rules { get; set; } = [];
    public bool Automatic { get; set; }
    public Dictionary<string, string> DefaultProfiles { get; set; } = [];
    public bool MinimizeToTray { get; set; } = true;
    public bool StartMinimized { get; set; }
    public string Theme { get; set; } = "system";
    /// <summary>Follow changes made on the monitor OSD or in Windows display settings.</summary>
    public bool LiveSync { get; set; } = true;
    public Settings Clone() => JsonSerializer.Deserialize<Settings>(JsonSerializer.Serialize(this))!;
}

public static class RuleResolver
{
    public static Profile? Default(Settings settings, string monitorId) => settings.DefaultProfiles.TryGetValue(monitorId, out var id)
        ? settings.Profiles.FirstOrDefault(p => p.Id == id && p.MonitorId == monitorId) : null;
    // Exact executable path; highest priority wins. Stable ties follow the displayed rule order.
    public static Profile? Resolve(Settings settings, string monitorId, IEnumerable<string> running, string? foreground)
    {
        var paths = new HashSet<string>(running, StringComparer.OrdinalIgnoreCase);
        return settings.Rules.Where(r => r.Enabled && paths.Contains(r.ExecutablePath))
            .OrderByDescending(r => r.Priority)
            .Select(r => settings.Profiles.FirstOrDefault(p => p.Id == r.ProfileId && p.MonitorId == monitorId))
            .FirstOrDefault(p => p is not null);
    }
}

public sealed class SettingsStore
{
    public string Path { get; }
    private readonly string? legacyPath;
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public SettingsStore(string? path = null, string? legacyPath = null)
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Path = path ?? System.IO.Path.Combine(root, "GO27Q32Lite", "settings.json");
        this.legacyPath = legacyPath ?? (path is null ? System.IO.Path.Combine(root, "GO27Q32LiteFlutter", "settings.json") : null);
    }
    private void MigrateLegacy()
    {
        // Run only when loading real preferences, never when constructing the demo host.
        // An existing destination always wins; do not replace another installation's data.
        if (File.Exists(Path) || legacyPath is null || !File.Exists(legacyPath)) return;
        string content = File.ReadAllText(legacyPath);
        Validate(JsonSerializer.Deserialize<Settings>(content, Json) ?? throw new InvalidDataException("配置为空"));
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        string temp = Path + ".migration-" + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temp, content);
            File.Move(temp, Path); // No overwrite: preserve a destination created concurrently.
            if (File.Exists(legacyPath + ".bak") && !File.Exists(Path + ".bak"))
                File.Copy(legacyPath + ".bak", Path + ".bak");
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public Settings Load()
    {
        MigrateLegacy();
        if (!File.Exists(Path)) return new Settings();
        string content = File.ReadAllText(Path);
        using var document = JsonDocument.Parse(content);
        var result = JsonSerializer.Deserialize<Settings>(content, Json) ?? throw new InvalidDataException("配置为空");
        Validate(result);
        if (!document.RootElement.TryGetProperty("Language", out _)) Save(result);
        return result;
    }
    public void Save(Settings settings)
    {
        Validate(settings);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        var temp = Path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(settings, Json));
        if (File.Exists(Path)) File.Replace(temp, Path, Path + ".bak");
        else File.Move(temp, Path);
    }
    public static void Validate(Settings settings)
    {
        if (settings.Version != 1 || settings.Profiles is null || settings.Rules is null || settings.DefaultProfiles is null || settings.Theme is not ("system" or "light" or "dark") || settings.Language is not ("zh" or "en")) throw new InvalidDataException("配置格式或版本无效");
        if (settings.Profiles.Select(p => p.Id).Distinct().Count() != settings.Profiles.Count) throw new InvalidDataException("配置 ID 重复");
        foreach (var p in settings.Profiles)
        {
            if (string.IsNullOrWhiteSpace(p.Id) || string.IsNullOrWhiteSpace(p.Name) || string.IsNullOrWhiteSpace(p.MonitorId) || p.Values is null || p.HdrValues is null || (p.Values.Count + p.HdrValues.Count == 0 && p.HdrPolicy == -1) || p.HdrPolicy is < -1 or > 1) throw new InvalidDataException("配置名称、显示器、HDR策略或参数无效");
            foreach (var pair in p.Values.Concat(p.HdrValues))
                if (!Features.Get(pair.Key).Accepts(pair.Value) || !Features.Get(pair.Key).Automatic) throw new InvalidDataException("配置参数超出范围或不允许自动应用：" + pair.Key);
        }
        foreach (var r in settings.Rules)
            if (!System.IO.Path.IsPathFullyQualified(r.ExecutablePath) || !r.ExecutablePath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || !settings.Profiles.Any(p => p.Id == r.ProfileId)) throw new InvalidDataException("应用规则路径或配置无效");
        foreach (var pair in settings.DefaultProfiles)
            if (!settings.Profiles.Any(p => p.Id == pair.Value && p.MonitorId == pair.Key)) throw new InvalidDataException("默认桌面配置不属于对应显示器");
    }
}
