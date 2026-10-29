import 'desktop_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/control.dart';
import 'l10n.dart';
import 'ui_parts.dart';

class GameTimerCard extends StatefulWidget {
  const GameTimerCard({super.key, required this.model});
  final ControlModel model;
  @override
  State<GameTimerCard> createState() => _GameTimerCardState();
}

class _GameTimerCardState extends State<GameTimerCard> {
  final minutes = TextEditingController(text: '05');
  final seconds = TextEditingController(text: '00');
  int mode = 2;
  @override
  void dispose() {
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  Widget _timeInput(
    TextEditingController controller,
    String label,
    int max,
    bool enabled,
  ) => SizedBox(
    width: 94,
    child: TextField(
      key: ValueKey('timer-$max'),
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      decoration: InputDecoration(
        labelText: tr(context, label),
        errorText:
            controller.text.isNotEmpty &&
                (int.tryParse(controller.text) ?? 100) > max
            ? '0–$max'
            : null,
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final available = [
      'gameTimer',
      'timerRunning',
      'timerDuration',
    ].every((id) => m.blocked(id) == null);
    final currentMode = m.value('gameTimer') ?? 0;
    final running = currentMode != 0 && m.value('timerRunning') == 1;
    final packed = m.value('timerDuration');
    final time = packed == null
        ? '—:—'
        : '${(packed >> 8).toString().padLeft(2, '0')}:${(packed & 255).toString().padLeft(2, '0')}';
    final min = int.tryParse(minutes.text), sec = int.tryParse(seconds.text);
    final valid =
        mode != 2 || (min != null && min <= 99 && sec != null && sec <= 59);
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: SectionCard(
        key: const ValueKey('game-timer-card'),
        title: '游戏计时器',
        subtitle: '机身叠加显示，独立于应用画面配置',
        icon: Icons.timer_outlined,
        trailing: OutlinedButton.icon(
          key: const ValueKey('timer-stop'),
          onPressed: available && currentMode != 0
              ? () =>
                    m.command('timer', {'mode': 0, 'minutes': 0, 'seconds': 0})
              : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const LText('关闭计时器'),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          time,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        LText(
                          currentMode == 0
                              ? '计时器已关闭'
                              : '${m.label('gameTimer')} · ${tr(context, running ? '运行中' : '暂停')}',
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('timer-pause'),
                    onPressed: available && currentMode != 0
                        ? () => m.command('timerPause', {'paused': running})
                        : null,
                    icon: Icon(running ? Icons.pause : Icons.play_arrow),
                    label: LText(running ? '暂停' : '继续'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DesktopSelect<int>(
                key: const ValueKey('timer-mode'),
                initialValue: mode,
                decoration: InputDecoration(labelText: tr(context, '计时模式')),
                items: [
                  for (final entry in {1: '正计时', 2: '倒计时'}.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: LText(entry.value),
                    ),
                ],
                onChanged: available
                    ? (value) => setState(() => mode = value!)
                    : null,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _timeInput(minutes, '分钟', 99, available && mode == 2),
                  _timeInput(seconds, '秒', 59, available && mode == 2),
                  FilledButton.icon(
                    key: const ValueKey('timer-start'),
                    onPressed: available && valid
                        ? () => m.command('timer', {
                            'mode': mode,
                            'minutes': mode == 2 ? min! : 0,
                            'seconds': mode == 2 ? sec! : 0,
                          })
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const LText('开始计时'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LText(
                available
                    ? '倒计时 00:00 将按原厂规则从 05:00 开始。启动会重置当前计时。'
                    : '当前无法读取计时器，请重新检测显示器。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Divider(),
              FeatureControl(
                model: m,
                id: 'assistPosition',
                padding: const EdgeInsets.only(top: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
