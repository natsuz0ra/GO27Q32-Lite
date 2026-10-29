import 'desktop_select.dart';
import 'l10n.dart';
import 'package:flutter/material.dart';
import 'core/control.dart';
import 'desktop.dart';
import 'ui_parts.dart';

Future<void> editProfile(
  BuildContext context,
  ControlModel model, [
  Json? existing,
]) async {
  final profile = await showDialog<Json>(
    context: context,
    builder: (_) => ProfileEditor(model: model, existing: existing),
  );
  if (profile == null) return;
  final settings = copyJson(model.settings),
      profiles = (copyJson(model.settings)['Profiles'] as List);
  final index = profiles.indexWhere((p) => p['Id'] == profile['Id']);
  if (index < 0) {
    profiles.add(profile);
  } else {
    profiles[index] = profile;
  }
  settings['Profiles'] = profiles;
  await model.saveSettings(settings);
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.model, this.existing});
  final ControlModel model;
  final Json? existing;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late Json draft;
  late TextEditingController name;
  bool hdr = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final m = widget.model;
    draft = widget.existing == null
        ? <String, dynamic>{
            'Id': DateTime.now().microsecondsSinceEpoch.toString(),
            'Name': AppLocalizations(
              m.settings['Language'] as String? ?? 'zh',
            ).text('新配置'),
            'MonitorId': m.monitorId,
            'Values': <String, dynamic>{},
            'HdrValues': <String, dynamic>{},
            'HdrPolicy': -1,
          }
        : copyJson(widget.existing!);
    if (widget.existing == null) {
      final current = <String, dynamic>{};
      for (final f in m.features) {
        final id = f['Id'] as String;
        if (f['Automatic'] == true &&
            m.confirmed(id) != null &&
            m.blocked(id, ignoreManagement: true) == null) {
          current[id] = m.confirmed(id);
        }
      }
      draft[m.activeHdr ? 'HdrValues' : 'Values'] = current;
      hdr = m.activeHdr;
    }
    name = TextEditingController(text: draft['Name'] as String);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bank = draft[hdr ? 'HdrValues' : 'Values'] as Json;
    return AlertDialog(
      title: LText(widget.existing == null ? '保存当前画面为配置' : '编辑配置'),
      content: SizedBox(
        width: 620,
        height: 580,
        child: Column(
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr(context, '配置名称')),
              maxLength: 48,
            ),
            const SizedBox(height: 12),
            DesktopSelect<int>(
              borderRadius: BorderRadius.circular(12),
              initialValue: draft['HdrPolicy'] as int,
              decoration: InputDecoration(
                labelText: tr(context, '套用时的 Windows HDR 策略'),
              ),
              items: const [
                DropdownMenuItem(value: -1, child: LText('保持当前状态')),
                DropdownMenuItem(value: 0, child: LText('关闭 HDR')),
                DropdownMenuItem(value: 1, child: LText('开启 HDR')),
              ],
              onChanged: (v) => setState(() => draft['HdrPolicy'] = v),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: LText('SDR 参数')),
                ButtonSegment(value: true, label: LText('HDR 参数')),
              ],
              selected: {hdr},
              onSelectionChanged: (v) => setState(() => hdr = v.first),
            ),
            const SizedBox(height: 10),
            const LText(
              '勾选的参数才会套用。两组独立保存；编辑配置不会立即写入显示器。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final f in widget.model.features.where(
                    (f) =>
                        f['Automatic'] == true &&
                        (!hdr || f['Id'] != 'pictureMode'),
                  ))
                    _field(f, bank),
                ],
              ),
            ),
            if (error != null)
              LText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) {
              setState(() => error = '请输入配置名称');
              return;
            }
            if ((draft['Values'] as Json).isEmpty &&
                (draft['HdrValues'] as Json).isEmpty &&
                draft['HdrPolicy'] == -1) {
              setState(() => error = '请至少选择一个参数或指定 HDR 策略');
              return;
            }
            draft['Name'] = name.text.trim();
            Navigator.pop(context, draft);
          },
          child: const LText('保存配置'),
        ),
      ],
    );
  }

  Widget _field(Json f, Json bank) {
    final id = f['Id'] as String, included = bank.containsKey(f['Id']);
    final choices = f['Choices'] as List?;
    final max = f['Max'] as int;
    final value = bank[id] as int? ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Checkbox(
            value: included,
            onChanged: (v) => setState(() {
              if (v == true) {
                bank[id] = hdr == widget.model.activeHdr
                    ? widget.model.confirmed(id) ?? 0
                    : 0;
              } else {
                bank.remove(id);
              }
            }),
          ),
          SizedBox(width: 112, child: LText(f['Name'] as String)),
          Expanded(
            child: choices != null
                ? DesktopSelect<int>(
                    borderRadius: BorderRadius.circular(12),
                    initialValue: choices.any((c) => c['Value'] == value)
                        ? value
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: choices
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c['Value'] as int,
                            child: LText(c['Name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: included
                        ? (v) => setState(() => bank[id] = v)
                        : null,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: value.clamp(0, max).toDouble(),
                          max: max.toDouble(),
                          divisions: max,
                          label: '$value',
                          onChanged: included
                              ? (v) => setState(() => bank[id] = v.round())
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: LText('$value', textAlign: TextAlign.end),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> editRule(
  BuildContext context,
  ControlModel model, [
  int? index,
]) async {
  final rule = await showDialog<Json>(
    context: context,
    builder: (_) => RuleEditor(
      model: model,
      existing: index == null ? null : model.rules[index],
    ),
  );
  if (rule == null) return;
  final edited = copyJson(model.settings),
      list = copyJson(model.settings)['Rules'] as List;
  if (index == null) {
    list.add(rule);
  } else {
    list[index] = rule;
  }
  edited['Rules'] = list;
  await model.saveSettings(edited);
}

class RuleEditor extends StatefulWidget {
  const RuleEditor({super.key, required this.model, this.existing});
  final ControlModel model;
  final Json? existing;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late TextEditingController path, priority;
  String? profile, error;
  bool enabled = true, loading = false;
  List<Json> processes = [];
  @override
  void initState() {
    super.initState();
    path = TextEditingController(
      text: widget.existing?['ExecutablePath'] as String? ?? '',
    );
    priority = TextEditingController(
      text: '${widget.existing?['Priority'] ?? 10}',
    );
    profile =
        widget.existing?['ProfileId'] as String? ??
        widget.model.deviceProfiles.firstOrNull?['Id'] as String?;
    enabled = widget.existing?['Enabled'] != false;
  }

  @override
  void dispose() {
    path.dispose();
    priority.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LText(widget.existing == null ? '添加应用规则' : '编辑应用规则'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InfoBanner('按完整 EXE 路径匹配应用。优先级数字越大越优先；相同时按列表顺序。'),
            const SizedBox(height: 18),
            TextField(
              controller: path,
              decoration: InputDecoration(
                labelText: tr(context, '应用完整路径'),
                suffixIcon: IconButton(
                  tooltip: tr(context, '选择 EXE 文件'),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    final selected = await Desktop.call<String>(
                      'pickExecutable',
                    );
                    if (selected != null && mounted) {
                      setState(() => path.text = selected);
                    }
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        try {
                          final list =
                              await widget.model.transport.call('processes')
                                  as List;
                          if (mounted) {
                            setState(() => processes = list.cast<Json>());
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => loading = false);
                        }
                      },
                icon: const Icon(Icons.apps, size: 18),
                label: LText(loading ? '读取中…' : '从正在运行的应用选择'),
              ),
            ),
            if (processes.isNotEmpty)
              SizedBox(
                height: 170,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    children: [
                      for (final p in processes)
                        ListTile(
                          dense: true,
                          title: Text(p['name'] as String),
                          subtitle: LText(
                            p['path'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => setState(() {
                            path.text = p['path'] as String;
                            processes.clear();
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            DesktopSelect<String>(
              borderRadius: BorderRadius.circular(12),
              initialValue: profile,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, '关联配置')),
              items: widget.model.deviceProfiles
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['Id'] as String,
                      child: Text(p['Name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => profile = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priority,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(context, '优先级'),
                helperText: tr(context, '例如 10、20、30；数值越大越优先'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LText('启用这条规则'),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            if (error != null)
              LText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const LText('取消'),
      ),
      FilledButton(
        onPressed: () {
          final full = path.text.trim();
          final number = int.tryParse(priority.text);
          if (!RegExp(
                r'^[a-zA-Z]:[\\/].+\.exe$',
                caseSensitive: false,
              ).hasMatch(full) &&
              !full.startsWith('\\\\')) {
            setState(() => error = '请选择完整的 Windows EXE 路径');
            return;
          }
          if (profile == null || number == null) {
            setState(() => error = '请选择配置并填写整数优先级');
            return;
          }
          Navigator.pop(context, {
            'ExecutablePath': full,
            'ProfileId': profile,
            'Priority': number,
            'Enabled': enabled,
          });
        },
        child: const LText('保存规则'),
      ),
    ],
  );
}
