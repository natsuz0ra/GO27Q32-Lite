namespace MonitorLite;

/// <summary>Wait for the post-SET blanking interval, then require consecutive stable probes.</summary>
public static class HdrPresetRecovery
{
    public const int Attempts = 24;
    public const int StableProbes = 3;
    public static async Task<bool> WaitAsync(Func<Task<bool>> probe, Func<TimeSpan, Task>? delay = null)
    {
        delay ??= Task.Delay;
        // No DDC queries or handle discovery while the display starts changing timing.
        await delay(TimeSpan.FromSeconds(2));
        int stable = 0;
        for (int attempt = 0; attempt < Attempts; attempt++)
        {
            stable = await probe() ? stable + 1 : 0;
            if (stable >= StableProbes) return true;
            if (attempt < Attempts - 1) await delay(TimeSpan.FromMilliseconds(500));
        }
        return false; // Caller keeps observing; never resend the original SET.
    }
}
