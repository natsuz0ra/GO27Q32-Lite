import 'package:flutter/material.dart';
import 'core/control.dart';
import 'desktop_select.dart';
import 'l10n.dart';
import 'ui_parts.dart';

/// A command picker, deliberately separate from confirmed monitor readings.
class HdrPresetCard extends StatefulWidget {
  const HdrPresetCard({super.key, required this.model});
  final ControlModel model;
  @override
  State<HdrPresetCard> createState() => _HdrPresetCardState();
}

class _HdrPresetCardState extends State<HdrPresetCard> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final reason = m.hdrPresetBlocked;
    final last = m.hdrPresetRequest?['Value'];
    final lastName =
        m.hdrPresets.where((p) => p['Value'] == last).firstOrNull?['Name']
            as String?;
    return SectionCard(
      key: const ValueKey('hdr-preset-card'),
      title: 'HDR 专用预设',
      icon: Icons.hdr_auto_outlined,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LText(
              '仅发送预设切换，不调整其他画面参数。当前模式无法读回，请以机身菜单为准。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            DesktopSelect<int>(
              key: const ValueKey('hdr-preset-picker'),
              initialValue: selected,
              decoration: const InputDecoration(),
              hint: const LText('选择要切换的预设'),
              items: [
                for (final p in m.hdrPresets)
                  DropdownMenuItem(
                    value: p['Value'] as int,
                    child: LText(p['Name'] as String),
                  ),
              ],
              onChanged: reason == null
                  ? (v) => setState(() => selected = v)
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('hdr-preset-send'),
              onPressed: reason == null && selected != null
                  ? () => m.command('hdrPreset', {'value': selected})
                  : null,
              icon: m.hdrPresetSwitching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz, size: 20),
              label: LText(m.hdrPresetSwitching ? '正在切换…' : '切换预设'),
            ),
            const SizedBox(height: 12),
            LText(
              reason ?? m.hdrManualHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            const LText('上次请求（非当前模式）', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            LText(
              lastName ?? '本次运行尚未发送',
              key: const ValueKey('hdr-preset-last-request'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
