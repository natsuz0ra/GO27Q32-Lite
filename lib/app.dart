import 'desktop_select.dart';
import 'l10n.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/control.dart';
import 'desktop.dart';
import 'editors.dart';
import 'game_timer.dart';
import 'ui_parts.dart';
import 'update_card.dart';
import 'version.dart';

const pageNames = ['显示器', 'HDR 状态', '应用规则', '配置库', '设置'];
const pageIcons = [
  Icons.desktop_windows_outlined,
  Icons.hdr_on_outlined,
  Icons.rule_outlined,
  Icons.bookmarks_outlined,
  Icons.settings_outlined,
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.model,
    this.onQuit,
    this.trayReady = false,
    this.initialPage = 0,
    this.onPageChanged,
  });
  final ControlModel model;
  final VoidCallback? onQuit;
  final bool trayReady;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int page = 0;
  bool startup = false;
  String? desktopError;
  String? acknowledgedHdrError;
  ControlModel get m => widget.model;
  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
    _loadStartup();
  }

  Future<void> _loadStartup() async {
    try {
      final v = await Desktop.call<bool>('startupGet');
      if (mounted) setState(() => startup = v == true);
    } catch (_) {}
  }

  ColorScheme get colors => Theme.of(context).colorScheme;
  TextTheme get type => Theme.of(context).textTheme;
  void go(int v) {
    setState(() => page = v);
    widget.onPageChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: m,
    builder: (context, _) => Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 236,
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 16, 22),
                    child: Row(
                      children: [
                        const AppMark(size: 48),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LText(
                                'GO27Q32 Lite',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3),
                              LText('显示器控制中心', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.monitor,
                              color: colors.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const LText(
                                    'GO27Q32',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  LText(
                                    m.demo
                                        ? '演示设备 · 不访问硬件'
                                        : m.connected
                                        ? 'DDC/CI 已连接'
                                        : '等待显示器连接',
                                    style: type.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              m.connected ? Icons.check_circle : Icons.link_off,
                              size: 17,
                              color: m.connected
                                  ? colors.tertiary
                                  : colors.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: NavigationDrawer(
                      selectedIndex: page,
                      onDestinationSelected: go,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 16, 12),
                          child: LText(
                            '控制',
                            style: type.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (int i = 0; i < 4; i++) ...[
                          NavigationDrawerDestination(
                            icon: i == 1
                                ? const HdrLabelIcon()
                                : Icon(pageIcons[i], size: 24),
                            selectedIcon: i == 1
                                ? const HdrLabelIcon()
                                : Icon(pageIcons[i], size: 24),
                            label: LText(pageNames[i]),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Divider(),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
                          child: LText(
                            '应用',
                            style: type.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const NavigationDrawerDestination(
                          icon: Icon(Icons.settings_outlined, size: 21),
                          label: LText('设置'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.brightness_6_outlined,
                        size: 20,
                      ),
                      title: const LText('切换主题'),
                      onTap: () => m.preference(
                        'Theme',
                        Theme.of(context).brightness == Brightness.dark
                            ? 'light'
                            : 'dark',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: OperationFeedback(
              model: m,
              extraError:
                  desktopError ??
                  (page == 1 && m.state['hdrError'] != acknowledgedHdrError
                      ? m.state['hdrError'] as String?
                      : null),
              errorTop: 72,
              onDismiss: () {
                m.dismissError();
                setState(() {
                  desktopError = null;
                  acknowledgedHdrError = m.state['hdrError'] as String?;
                });
              },
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: OverlayScrollView(
                      key: PageStorageKey(page),
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _heading(),
                          if (m.demo) ...[
                            const InfoBanner('演示模式：以下为示例数据，不连接硬件、不保存用户设置。'),
                            const SizedBox(height: 16),
                          ],
                          if (!m.ready)
                            const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            switch (page) {
                              0 => _display(),
                              1 => _hdr(),
                              2 => _rules(),
                              3 => _profiles(),
                              _ => _settings(),
                            },
                        ],
                      ),
                    ),
                  ),
                  _footer(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _topBar() => SizedBox(
    height: 60,
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: _maximize,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  Icon(pageIcons[page], size: 18, color: colors.primary),
                  const SizedBox(width: 12),
                  LText(pageNames[page], style: type.labelLarge),
                  const SizedBox(width: 16),
                  Flexible(
                    child: LText(
                      m.connected ? 'GO27Q32 已连接' : '设备未连接',
                      overflow: TextOverflow.ellipsis,
                      style: type.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        StatusPill(
          !m.connected
              ? '离线'
              : m.stableHdr
              ? (m.activeHdr ? 'HDR 输出' : 'SDR 输出')
              : '输出状态待确认',
          good: m.connected,
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: tr(context, '最小化'),
          onPressed: () => windowManager.minimize(),
          icon: const Icon(Icons.remove, size: 18),
        ),
        IconButton(
          tooltip: tr(context, '最大化 / 还原'),
          onPressed: _maximize,
          icon: const Icon(Icons.crop_square, size: 17),
        ),
        IconButton(
          tooltip: tr(context, '关闭窗口'),
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close, size: 18),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
  Future<void> _maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _heading() {
    final subtitles = [
      '直接调节显示器；临时改动可另存为配置。',
      '查看系统 HDR 请求与实际输出，分别保存 SDR / HDR 参数。',
      '应用启动后自动套用配置，退出后恢复桌面画面。',
      '管理画面参数，为应用规则提供可复用的配置。',
      '启动行为、状态同步与界面外观。',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        spacing: 20,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                page == 0
                    ? '你的画面，随心调节'
                    : ['', '动态范围', '自动化', '画面配置', '应用偏好'][page],
                style: type.labelMedium?.copyWith(color: colors.primary),
              ),
              const SizedBox(height: 7),
              LText(
                pageNames[page],
                style: type.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              LText(
                subtitles[page],
                style: type.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          if (page == 0)
            FilledButton.icon(
              onPressed: !m.connected || m.busy
                  ? null
                  : () => editProfile(context, m),
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const LText('存为配置'),
            ),
          if (page == 1)
            OutlinedButton.icon(
              onPressed: m.busy ? null : () => m.command('state'),
              icon: const Icon(Icons.refresh, size: 18),
              label: const LText('重新读取'),
            ),
          if (page == 2)
            FilledButton.icon(
              onPressed: m.deviceProfiles.isEmpty || m.busy
                  ? null
                  : () => editRule(context, m),
              icon: const Icon(Icons.add, size: 18),
              label: const LText('新增规则'),
            ),
          if (page == 3)
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: m.busy ? null : _import,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const LText('导入'),
                ),
                FilledButton.icon(
                  onPressed: !m.connected || m.busy
                      ? null
                      : () => editProfile(context, m),
                  icon: const Icon(Icons.add, size: 18),
                  label: const LText('新建配置'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _footer() => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
    child: Row(
      children: [
        Icon(
          m.busy ? Icons.sync : Icons.circle,
          size: m.busy ? 15 : 7,
          color: colors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LText(
            m.status,
            style: type.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        LText(
          'v$appVersion',
          style: type.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    ),
  );
  Widget _columns(
    Widget left,
    Widget right, {
    double rightWidth = 290,
    bool equalHeight = false,
  }) => LayoutBuilder(
    builder: (_, box) => box.maxWidth < 790
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 18), right],
          )
        : _equalColumns(left, right, rightWidth, equalHeight),
  );
  Widget _equalColumns(
    Widget left,
    Widget right,
    double rightWidth,
    bool equalHeight,
  ) {
    final row = Row(
      crossAxisAlignment: equalHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 20),
        SizedBox(width: rightWidth, child: right),
      ],
    );
    return equalHeight ? IntrinsicHeight(child: row) : row;
  }

  Widget _display() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _stat('连接状态', m.connected ? '已连接 · DDC/CI' : '未连接'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _stat(
                  '当前配置',
                  '${m.activeProfile?['Name'] ?? tr(context, '临时画面')}${m.state['dirty'] == true ? tr(context, ' · 已调整') : ''}',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _stat('管理方式', m.automatic ? '应用自动管理' : '手动调节')),
              const SizedBox(width: 16),
              Expanded(
                child: _stat(
                  '状态同步',
                  m.settings['LiveSync'] == true ? '自动同步已开启' : '手动读取',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      if (!m.connected) ...[
        InfoBanner(
          '请将 GO27Q32 设为活动的扩展显示并保持唤醒，再重新检测。',
          action: TextButton(
            onPressed: m.busy ? null : () => m.command('scan'),
            child: const LText('检测'),
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (m.automatic) ...[
        InfoBanner(
          '应用规则正在管理画面。暂停后即可手动调节。',
          action: TextButton(
            onPressed: m.busy
                ? null
                : () => m.command('automatic', {'enabled': false}),
            child: const LText('暂停'),
          ),
        ),
        const SizedBox(height: 18),
      ],
      _columns(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: '亮度',
              subtitle: '修改后写入显示器，并读回确认',
              icon: Icons.light_mode_outlined,
              tint: true,
              trailing: StatusPill(m.activeHdr ? 'HDR 参数' : 'SDR 参数'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FeatureControl(model: m, id: 'brightness', large: true),
                    const SizedBox(height: 8),
                    LText('快捷配置', style: type.labelLarge),
                    const SizedBox(height: 10),
                    m.deviceProfiles.isEmpty
                        ? LText('将当前画面存为配置后，会显示在这里。', style: type.bodySmall)
                        : QuickProfiles(model: m),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _featureSection('常用设置', Icons.tune, [
              'pictureMode',
              'contrast',
              'gamma',
              'colorTemperature',
            ]),
            const SizedBox(height: 18),
            _featureSection('游戏辅助', Icons.sports_esports_outlined, [
              'crosshair',
              'blackEqualizer',
              'overdrive',
              'freeSync',
              'refreshOverlay',
            ]),
            const SizedBox(height: 18),
            GameTimerCard(model: m),
            const SizedBox(height: 18),
            _featureSection('更多参数', Icons.display_settings_outlined, [
              'sharpness',
              'colorVibrance',
              'lowBlueLight',
              'superResolution',
              'volume',
              'input',
            ]),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: '当前会话',
              icon: Icons.bookmark_outline,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LText(
                      m.activeProfile?['Name'] as String? ?? '临时画面',
                      translate: m.activeProfile == null,
                      style: type.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    LText(
                      m.state['dirty'] == true
                          ? '画面已调整，命名配置保持原值。'
                          : '当前确认的显示器读数。',
                      style: type.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    DetailLine(
                      '亮度 / 对比度',
                      '${m.label('brightness')} / ${m.label('contrast')}',
                    ),
                    const Divider(),
                    DetailLine('Gamma', m.label('gamma')),
                    const Divider(),
                    DetailLine(
                      '画面模式',
                      m.activeHdr ? 'HDR · 机身菜单' : m.label('pictureMode'),
                    ),
                    const Divider(),
                    DetailLine(
                      '实际输出',
                      m.stableHdr ? (m.activeHdr ? 'HDR' : 'SDR') : '待确认',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          m.state['canUndo'] != true || m.busy || m.automatic
                          ? null
                          : () => m.command('undo'),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const LText('撤销临时调节'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Windows HDR',
              icon: Icons.hdr_on_outlined,
              trailing: HdrSwitch(model: m),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: LText(
                        key: const ValueKey('hdr-card-description'),
                        '仅控制当前 GO27Q32 的系统 HDR 开关。',
                        style: type.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey('hdr-card-link'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 40),
                        visualDensity: VisualDensity.standard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => go(1),
                      label: const LText(
                        '查看 HDR 状态',
                        key: ValueKey('hdr-card-link-label'),
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      iconAlignment: IconAlignment.end,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _syncCard(),
          ],
        ),
      ),
    ],
  );
  Widget _stat(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(
          title,
          style: type.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 7),
        Tooltip(
          message: title == '当前配置' ? value : tr(context, value),
          child: LText(
            value,
            translate: title != '当前配置',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.labelLarge,
          ),
        ),
      ],
    ),
  );
  Widget _featureSection(String title, IconData icon, List<String> ids) =>
      SectionCard(
        title: title,
        icon: icon,
        child: Column(
          children: [
            for (int i = 0; i < ids.length; i++) ...[
              FeatureControl(model: m, id: ids[i]),
              if (i < ids.length - 1) const Divider(indent: 20, endIndent: 20),
            ],
          ],
        ),
      );
  Widget _syncCard() => SectionCard(
    title: '外部状态同步',
    icon: Icons.sync,
    trailing: Switch(
      value: m.settings['LiveSync'] == true,
      onChanged: m.busy ? null : (v) => m.preference('LiveSync', v),
    ),
    child: const Padding(
      padding: EdgeInsets.all(18),
      child: LText(
        '自动读取机身 OSD 与 Windows HDR 改动。HDR 约 1.5 秒检测一次，DDC 参数分批轮询。',
        style: TextStyle(fontSize: 12),
      ),
    ),
  );
  Widget _hdr() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InfoBanner('Windows HDR 仅作用于当前 GO27Q32。请求开关与显示器实际输出可能短暂不同。'),
      const SizedBox(height: 20),
      _columns(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Windows HDR',
              subtitle: 'Windows「使用 HDR」开关',
              icon: Icons.hdr_on,
              tint: true,
              trailing: HdrSwitch(model: m),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _hdrState(
                            '系统请求',
                            m.state['hdr'] == null
                                ? '未知'
                                : m.hdrEnabled
                                ? '已开启'
                                : '已关闭',
                            Icons.toggle_on_outlined,
                          ),
                        ),
                        const SizedBox(
                          width: 48,
                          child: Icon(
                            Icons.arrow_forward,
                            key: ValueKey('hdr-flow-arrow'),
                            size: 20,
                          ),
                        ),
                        Expanded(
                          child: _hdrState(
                            '实际输出',
                            m.state['hdr'] == null
                                ? '待确认'
                                : m.activeHdr
                                ? 'HDR'
                                : 'SDR',
                            Icons.monitor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              key: const ValueKey('hdr-parameters-card'),
              title: 'SDR 与 HDR 参数',
              icon: Icons.layers_outlined,
              subtitle: '分组独立保存 · 当前调节 ${m.activeHdr ? 'HDR' : 'SDR'} 参数',
              trailing: TextButton(
                onPressed: m.connected && !m.busy
                    ? () => editProfile(context, m)
                    : null,
                child: const LText('编辑配置'),
              ),
              child: Column(
                children: [
                  FeatureControl(
                    key: const ValueKey('hdr-brightness-control'),
                    model: m,
                    id: 'brightness',
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  FeatureControl(model: m, id: 'contrast'),
                  const Divider(indent: 20, endIndent: 20),
                  FeatureControl(model: m, id: 'gamma'),
                ],
              ),
            ),
          ],
        ),
        _syncCard(),
      ),
    ],
  );
  Widget _hdrState(String title, String value, IconData icon) => Column(
    key: ValueKey('hdr-state-$title'),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(
        icon,
        color: colors.primary,
        size: 30,
        key: ValueKey('hdr-flow-$title'),
      ),
      const SizedBox(height: 10),
      LText(title, style: type.bodySmall),
      const SizedBox(height: 6),
      LText(value, style: type.headlineSmall),
    ],
  );
  Widget _rules() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _columns(
        SectionCard(
          title: '自动应用配置',
          subtitle: '两轮稳定检测后切换，避免启动瞬间误切换',
          icon: Icons.auto_mode,
          trailing: Switch(
            value: m.automatic,
            onChanged:
                !m.connected ||
                    m.busy ||
                    m.rules.where((r) => r['Enabled'] == true).isEmpty
                ? null
                : (v) => m.command('automatic', {'enabled': v}),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  '${m.rules.where((r) => r['Enabled'] == true).length} 条启用  /  ${m.rules.length} 条规则',
                  style: type.titleMedium,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 42,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LTooltip(
                        message:
                            m.state['automationWarning'] as String? ?? m.status,
                        child: LText(
                          m.automatic
                              ? m.state['automationWarning'] as String? ??
                                    m.status
                              : '暂停时保留当前画面，手动调节恢复可用。',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodySmall?.copyWith(
                            color:
                                m.automatic &&
                                    m.state['automationWarning'] != null
                                ? colors.error
                                : null,
                          ),
                        ),
                      ),
                      if (m.automatic &&
                          m.state['processCheckedAt'] != null) ...[
                        const SizedBox(height: 4),
                        LText(
                          (m.state['matchedPaths'] as List? ?? []).isEmpty
                              ? '未检测到规则应用，正在使用桌面配置。'
                              : '已检测到规则应用。',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: '当前配置',
          icon: Icons.bookmark_outline,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LText(
              m.activeProfile?['Name'] as String? ?? '未套用命名配置',
              translate: m.activeProfile == null,
              style: type.headlineSmall,
            ),
          ),
        ),
        equalHeight: true,
      ),
      const SizedBox(height: 20),
      if (m.deviceProfiles.isEmpty) ...[
        InfoBanner(
          '先创建一份画面配置，再将它关联到应用。',
          action: TextButton(onPressed: () => go(3), child: const LText('配置库')),
        ),
        const SizedBox(height: 18),
      ],
      SectionCard(
        title: '规则列表',
        subtitle: '优先级数字越大越优先；同优先级按列表顺序',
        icon: Icons.rule,
        child: m.rules.isEmpty
            ? _empty(
                Icons.rule_folder_outlined,
                '还没有应用规则',
                '选择应用完整路径，关联一份画面配置。',
              )
            : Column(
                children: [
                  for (int i = 0; i < m.rules.length; i++) _ruleRow(i),
                ],
              ),
      ),
      const SizedBox(height: 18),
      SectionCard(
        title: '全部应用退出后',
        icon: Icons.restore,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopSelect<String>(
                borderRadius: BorderRadius.circular(12),
                initialValue:
                    (m.settings['DefaultProfiles'] as Json)[m.monitorId]
                        as String? ??
                    '',
                isExpanded: true,
                decoration: InputDecoration(labelText: tr(context, '桌面配置')),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: LText('恢复自动化启动前的设置'),
                  ),
                  for (final p in m.deviceProfiles)
                    DropdownMenuItem(
                      value: p['Id'] as String,
                      child: Text(p['Name'] as String),
                    ),
                ],
                onChanged: m.busy
                    ? null
                    : (v) async {
                        final s = copyJson(m.settings);
                        if (v == '') {
                          (s['DefaultProfiles'] as Json).remove(m.monitorId);
                        } else {
                          (s['DefaultProfiles'] as Json)[m.monitorId] = v;
                        }
                        await m.saveSettings(s);
                      },
              ),
              const SizedBox(height: 12),
              LText(
                '规则编辑在下一次应用启动或退出时生效。退出工具时会尝试恢复自动化启动前的画面。',
                style: type.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _ruleRow(int i) {
    final r = m.rules[i],
        profile = m.profiles
            .where((p) => p['Id'] == r['ProfileId'])
            .firstOrNull;
    final path = r['ExecutablePath'] as String;
    return Column(
      children: [
        if (i > 0) const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: LText('${r['Priority']}', style: type.labelMedium),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      path.split(RegExp(r'[\\/]')).last,
                      style: type.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    LText(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    LText(
                      '配置：${profile?['Name'] ?? '未找到'}',
                      style: type.bodySmall?.copyWith(color: colors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: r['Enabled'] == true,
                onChanged: m.busy
                    ? null
                    : (v) {
                        final s = copyJson(m.settings);
                        (s['Rules'] as List)[i]['Enabled'] = v;
                        m.saveSettings(s);
                      },
              ),
              PopupMenuButton<String>(
                clipBehavior: Clip.antiAlias,
                tooltip: tr(context, '规则操作'),
                enabled: !m.busy,
                onSelected: (v) async {
                  if (v == 'edit') {
                    await editRule(context, m, i);
                    return;
                  }
                  final s = copyJson(m.settings),
                      list = copyJson(m.settings)['Rules'] as List;
                  if (v == 'delete') {
                    if (!await _confirm('删除规则？', '该应用将不再自动切换配置。')) return;
                    list.removeAt(i);
                  }
                  if (v == 'up' && i > 0) {
                    final item = list.removeAt(i);
                    list.insert(i - 1, item);
                  }
                  if (v == 'down' && i < list.length - 1) {
                    final item = list.removeAt(i);
                    list.insert(i + 1, item);
                  }
                  s['Rules'] = list;
                  await m.saveSettings(s);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: LText('编辑')),
                  PopupMenuItem(
                    value: 'up',
                    enabled: i > 0,
                    child: const LText('上移'),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: i < m.rules.length - 1,
                    child: const LText('下移'),
                  ),
                  const PopupMenuItem(value: 'delete', child: LText('删除')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profiles() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (m.activeProfile != null) ...[
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            leading: Icon(Icons.check_circle_outline, color: colors.primary),
            title: Text(m.activeProfile!['Name'] as String),
            subtitle: LText(
              m.state['dirty'] == true ? '当前画面已临时调整，保存的配置保持原值' : '当前使用的配置',
            ),
            trailing: TextButton(
              onPressed: () => go(0),
              child: const LText('回到显示器'),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (m.profiles.isEmpty)
        _empty(Icons.bookmarks_outlined, '保存你的第一份画面配置', '连接显示器后，将当前参数存为配置。')
      else
        LayoutBuilder(
          builder: (_, box) {
            final width = box.maxWidth > 680
                ? (box.maxWidth - 18) / 2
                : box.maxWidth;
            return Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                for (int i = 0; i < m.profiles.length; i++)
                  SizedBox(width: width, child: _profileCard(m.profiles[i], i)),
              ],
            );
          },
        ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: m.profiles.isEmpty || m.busy ? null : () => _export(),
        icon: const Icon(Icons.file_download_outlined, size: 18),
        label: const LText('导出全部配置与规则'),
      ),
    ],
  );
  Widget _profileCard(Json p, int index) {
    final active = p['Id'] == m.state['activeProfile'];
    final bank = p[m.activeHdr ? 'HdrValues' : 'Values'] as Json;
    final accents = [
      colors.primaryContainer,
      colors.tertiaryContainer,
      colors.secondaryContainer,
    ];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: accents[index % accents.length],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  index % 3 == 0
                      ? Icons.light_mode_outlined
                      : index % 3 == 1
                      ? Icons.sports_esports_outlined
                      : Icons.movie_outlined,
                  color: colors.onSurface,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          p['Name'] as String,
                          key: ValueKey('profile-name-${p['Id']}'),
                          style: type.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 10),
                        StatusPill(
                          '使用中',
                          key: ValueKey('profile-in-use-${p['Id']}'),
                          good: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.desktop_windows_outlined,
                  color: colors.onSurface.withValues(alpha: .2),
                  size: 58,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      'HDR · ${p['HdrPolicy'] == 1
                          ? '开启'
                          : p['HdrPolicy'] == 0
                          ? '关闭'
                          : '保持'}',
                    ),
                    StatusPill(
                      'SDR ${(p['Values'] as Json).length} 项 / HDR ${(p['HdrValues'] as Json).length} 项',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LText(
                  bank.isEmpty
                      ? '当前输出分组未记录参数'
                      : bank.entries
                            .take(3)
                            .map(
                              (e) =>
                                  '${tr(context, m.feature(e.key)?['Name'] as String? ?? e.key)} ${m.label(e.key, e.value as int)}',
                            )
                            .join(' · '),
                  style: type.bodySmall,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                if (p['MonitorId'] != m.monitorId)
                  LText('属于其他显示器，当前不可套用', style: type.bodySmall),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed:
                          !m.connected ||
                              m.busy ||
                              m.automatic ||
                              p['MonitorId'] != m.monitorId
                          ? null
                          : () => m.command('apply', {'id': p['Id']}),
                      icon: const Icon(Icons.play_arrow, size: 17),
                      label: const LText('套用'),
                    ),
                    TextButton.icon(
                      onPressed: m.busy
                          ? null
                          : () => editProfile(context, m, p),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const LText('编辑'),
                    ),
                    PopupMenuButton<String>(
                      clipBehavior: Clip.antiAlias,
                      tooltip: tr(context, '配置操作'),
                      enabled: !m.busy,
                      onSelected: (action) => _profileAction(action, p),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'duplicate', child: LText('复制配置')),
                        PopupMenuItem(value: 'export', child: LText('导出配置')),
                        PopupMenuItem(value: 'delete', child: LText('删除配置')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _profileAction(String action, Json p) async {
    if (action == 'export') {
      await _export(p);
      return;
    }
    if (action == 'duplicate') {
      final duplicate = copyJson(p);
      duplicate['Id'] = DateTime.now().microsecondsSinceEpoch.toString();
      duplicate['Name'] = tr(context, '${p['Name']} 副本');
      final s = copyJson(m.settings);
      (s['Profiles'] as List).add(duplicate);
      await m.saveSettings(s);
      return;
    }
    if (!await _confirm('删除「${p['Name']}」？', '引用该配置的应用规则及桌面默认项也会移除。')) return;
    final s = copyJson(m.settings);
    (s['Profiles'] as List).removeWhere((item) => item['Id'] == p['Id']);
    (s['Rules'] as List).removeWhere((item) => item['ProfileId'] == p['Id']);
    (s['DefaultProfiles'] as Json).removeWhere((_, id) => id == p['Id']);
    await m.saveSettings(s);
  }

  Widget _settings() => _columns(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '启动与托盘',
          icon: Icons.rocket_launch_outlined,
          child: Column(
            children: [
              SwitchListTile(
                title: const LText('开机自启'),
                subtitle: const LText('Windows 登录后在托盘后台运行'),
                value: startup,
                onChanged: m.demo || m.busy
                    ? null
                    : (v) async {
                        try {
                          await Desktop.call('startupSet', v);
                          await _loadStartup();
                        } catch (e) {
                          setState(() => desktopError = '$e');
                        }
                      },
              ),
              const Divider(indent: 20, endIndent: 20),
              SwitchListTile(
                title: const LText('启动时最小化'),
                subtitle: const LText('手动启动时仅显示托盘图标'),
                value: m.settings['StartMinimized'] == true,
                onChanged: m.busy
                    ? null
                    : (v) => m.preference('StartMinimized', v),
              ),
              const Divider(indent: 20, endIndent: 20),
              SwitchListTile(
                title: const LText('关闭后驻留托盘'),
                subtitle: LText(
                  widget.trayReady ? '关闭窗口继续运行；右键托盘图标可退出' : '系统托盘尚未就绪，关闭时将退出程序',
                ),
                value: m.settings['MinimizeToTray'] == true,
                onChanged: m.busy
                    ? null
                    : (v) => m.preference('MinimizeToTray', v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _syncCard(),
        const SizedBox(height: 18),
        _featureSection('显示器 OSD', Icons.menu_open_outlined, [
          'osdTimeout',
          'osdTransparency',
          'ledIndicator',
        ]),
        const SizedBox(height: 18),
        SectionCard(
          title: '摇杆快捷功能',
          icon: Icons.gamepad_outlined,
          subtitle: '机身摇杆的四向快捷操作；设备设置不随应用配置切换',
          child: Column(
            children: [
              for (final id in [
                'joystickUp',
                'joystickDown',
                'joystickLeft',
                'joystickRight',
              ]) ...[
                if (id != 'joystickUp')
                  const Divider(indent: 20, endIndent: 20),
                FeatureControl(model: m, id: id),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '外观',
          icon: Icons.palette_outlined,
          subtitle: '主题与显示偏好',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  icon: Icon(Icons.brightness_auto, size: 18),
                  label: LText('系统'),
                ),
                ButtonSegment(
                  value: 'light',
                  icon: Icon(Icons.light_mode_outlined, size: 18),
                  label: LText('浅色'),
                ),
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(Icons.dark_mode_outlined, size: 18),
                  label: LText('深色'),
                ),
              ],
              selected: {m.settings['Theme'] as String? ?? 'system'},
              onSelectionChanged: m.busy
                  ? null
                  : (v) => m.preference('Theme', v.first),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '语言',
          icon: Icons.translate,
          subtitle: '首次按系统语言选择，之后记住这里的设置',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: DesktopSelect<String>(
              key: const ValueKey('app-language'),
              initialValue:
                  m.settings['Language'] as String? ??
                  initialLanguage(Platform.localeName),
              decoration: InputDecoration(labelText: tr(context, '界面语言')),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: m.busy
                  ? null
                  : (value) {
                      if (value != null) m.preference('Language', value);
                    },
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '数据与配置',
          icon: Icons.folder_outlined,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: m.busy ? null : _import,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const LText('导入配置'),
                ),
                OutlinedButton.icon(
                  onPressed: m.busy ? null : () => _export(),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const LText('导出配置'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '设备诊断',
          icon: Icons.monitor_heart_outlined,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 78,
                  color: colors.primary,
                ),
                const SizedBox(height: 18),
                LText(
                  'GO27Q32',
                  textAlign: TextAlign.center,
                  style: type.titleLarge,
                ),
                const SizedBox(height: 8),
                LText(
                  m.connected ? 'DDC/CI 控制通道已枚举' : '未找到活动的目标显示器',
                  textAlign: TextAlign.center,
                  style: type.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: m.busy || m.automatic
                      ? null
                      : () => m.command('scan'),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const LText('重新检测显示器'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: m.busy ? null : _diagnose,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const LText('导出诊断信息'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: 'GO27Q32 Lite',
          leading: const AppMark(size: 28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DetailLine('版本', appVersion),
                const Divider(),
                const DetailLine('控制接口', 'Windows DDC/CI'),
                const SizedBox(height: 12),
                const LText(
                  'macOS 硬件控制尚未实现。HDR 专用预设仍需通过机身菜单切换。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                const UpdateControls(),
                const SizedBox(height: 16),
                const LText(
                  '使用 HarmonyOS Sans 字体',
                  style: TextStyle(fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'GO27Q32 Lite',
                    applicationVersion: appVersion,
                  ),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const LText('开源许可'),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: widget.onQuit,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const LText('退出程序'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _empty(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      children: [
        Icon(icon, size: 42, color: colors.primary),
        const SizedBox(height: 14),
        LText(title, style: type.titleMedium),
        const SizedBox(height: 8),
        LText(subtitle, textAlign: TextAlign.center, style: type.bodySmall),
      ],
    ),
  );
  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: LText(title),
          content: LText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const LText('确定'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _import() async {
    try {
      final path = await Desktop.call<String>('openJson');
      if (path == null) return;
      final s = jsonDecode(await File(path).readAsString()) as Json;
      if (mounted &&
          await _confirm('导入配置与规则？', '将替换此版本保存的配置和规则。不会立即修改显示器参数。')) {
        await m.saveSettings(s);
      }
    } catch (e) {
      if (mounted) setState(() => desktopError = '导入失败：$e');
    }
  }

  Future<void> _export([Json? profile]) async {
    try {
      final path = await Desktop.call<String>('saveJson');
      if (path == null) return;
      final data = copyJson(m.settings);
      if (profile != null) {
        data['Profiles'] = [profile];
        data['Rules'] = [];
        data['DefaultProfiles'] = <String, dynamic>{};
        data['Automatic'] = false;
      }
      await File(
        path,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('配置已导出')));
      }
    } catch (e) {
      if (mounted) setState(() => desktopError = '导出失败：$e');
    }
  }

  Future<void> _diagnose() async {
    try {
      final path = await Desktop.call<String>('saveReport');
      if (path == null) return;
      final report = await m.transport.call('diagnose') as String;
      await File(path).writeAsString(report);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('诊断报告已导出')));
      }
    } catch (e) {
      if (mounted) setState(() => desktopError = '诊断失败：$e');
    }
  }
}

class TrayPanel extends StatelessWidget {
  const TrayPanel({
    super.key,
    required this.model,
    required this.onOpen,
    required this.onClose,
    this.onContentSize,
  });
  final ControlModel model;
  final VoidCallback onOpen, onClose;
  final ValueChanged<Size>? onContentSize;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final c = Theme.of(context).colorScheme;
      return Material(
        color: c.surfaceContainerLow,
        child: OperationFeedback(
          model: model,
          child: OverlayScrollView(
            onContentSize: onContentSize,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const AppMark(size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: LText(
                        'GO27Q32',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StatusPill(
                      model.stableHdr
                          ? (model.activeHdr ? 'HDR' : 'SDR')
                          : '未知',
                    ),
                    IconButton(
                      tooltip: tr(context, '收起'),
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LText(
                  model.demo
                      ? '演示模式 · 不访问显示器'
                      : model.connected
                      ? '${model.activeProfile?['Name'] ?? tr(context, '临时画面')}${model.state['dirty'] == true ? tr(context, ' · 已调整') : ''}'
                      : '显示器未连接',
                  translate: model.demo || !model.connected,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                const LText(
                  '亮度',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                FeatureControl(
                  model: model,
                  id: 'brightness',
                  large: true,
                  compact: true,
                ),
                const Divider(),
                const SizedBox(height: 16),
                const LText(
                  '快捷配置',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                model.deviceProfiles.isEmpty
                    ? const LText('还没有配置', style: TextStyle(fontSize: 12))
                    : QuickProfiles(model: model),
                const SizedBox(height: 16),
                const LText(
                  '准星',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                LTooltip(
                  message: model.blocked('crosshair') ?? '选择显示器准星',
                  child: SegmentedButton<int>(
                    key: const ValueKey('tray-crosshair'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: WidgetStatePropertyAll(Size.fromHeight(40)),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(value: 0, label: LText('关闭')),
                      ButtonSegment(value: 1, label: LText('1')),
                      ButtonSegment(value: 2, label: LText('2')),
                      ButtonSegment(value: 3, label: LText('3')),
                      ButtonSegment(value: 4, label: LText('4')),
                    ],
                    selected: {model.value('crosshair') ?? 0},
                    onSelectionChanged: model.blocked('crosshair') != null
                        ? null
                        : (v) => model.stage('crosshair', v.first),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(key: ValueKey('tray-game-divider')),
                // Switch has a 48 px hit target around a 32 px visible track.
                // 8 px outside + 8 px inside = the same 16 px optical gap above.
                const SizedBox(height: 8),
                Row(
                  key: const ValueKey('tray-hdr-row'),
                  children: [
                    const Expanded(child: LText('Windows HDR')),
                    HdrSwitch(model: model),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(child: LText('应用自动切换')),
                    Switch(
                      value: model.automatic,
                      onChanged:
                          !model.connected ||
                              model.busy ||
                              model.rules
                                  .where((r) => r['Enabled'] == true)
                                  .isEmpty
                          ? null
                          : (v) => model.command('automatic', {'enabled': v}),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const ValueKey('tray-open-main'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const LText('打开控制中心'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
