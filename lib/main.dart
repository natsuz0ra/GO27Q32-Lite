import 'l10n.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'core/control.dart';
import 'desktop.dart';
import 'app.dart';
import 'theme.dart';
import 'tray_layout.dart';
import 'tray_popover.dart';
import 'desktop_select.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'HarmonyOS Sans',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
  });
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1320, 880),
        minimumSize: Size(1040, 700),
        center: true,
        title: 'GO27Q32 Lite',
        titleBarStyle: TitleBarStyle.hidden,
      ),
    );
  }
  ControlModel? model;
  String? failure;
  try {
    model = ControlModel(
      await HostTransport.start(
        demo: args.contains('--demo') || args.contains('--self-check'),
      ),
    );
    model.settings = await model.transport.call('preferences') as Json;
  } catch (e) {
    failure = '$e';
  }
  runApp(
    GoApp(
      model: model,
      failure: failure,
      trayStart: args.contains('--tray'),
      forceShow: args.contains('--show'),
      selfCheck: args.contains('--self-check'),
    ),
  );
}

class GoApp extends StatefulWidget {
  const GoApp({
    super.key,
    this.model,
    this.failure,
    this.trayStart = false,
    this.forceShow = false,
    this.selfCheck = false,
  });
  final ControlModel? model;
  final String? failure;
  final bool trayStart;
  final bool forceShow;
  final bool selfCheck;
  @override
  State<GoApp> createState() => _GoAppState();
}

class _GoAppState extends State<GoApp>
    with WindowListener, SingleTickerProviderStateMixin {
  bool tray = false, trayReady = false, exiting = false, changingWindow = false;
  Rect? mainBounds;
  bool wasMaximized = false;
  bool showMainPending = false;
  Route<void>? mainTrayRoute;
  int mainPage = 0;
  final navigator = GlobalKey<NavigatorState>();
  late final AnimationController trayMotion;
  late final CurvedAnimation trayCurve;
  Future<void> opacityWrites = Future<void>.value();
  double latestOpacity = 1;
  bool opacityBusy = false;
  int trayAnimationFrames = 0;
  Size? trayContentSize;
  Rect? trayWorkArea;
  Timer? trayResizeTimer;
  bool trayFitInProgress = false;
  int trayLayoutEpoch = 0;
  String? desktopLanguage;
  String? desktopTheme;
  String get language =>
      model?.settings['Language'] as String? ??
      initialLanguage(Platform.localeName);
  ControlModel? get model => widget.model;
  @override
  void initState() {
    super.initState();
    trayMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 100),
    );
    trayCurve = CurvedAnimation(
      parent: trayMotion,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    trayCurve.addListener(() {
      if (tray) {
        if (trayCurve.value > 0 && trayCurve.value < 1) trayAnimationFrames++;
        unawaited(_setOpacity(trayCurve.value));
      }
    });
    windowManager.addListener(this);
    model?.addListener(_refresh);
    Desktop.channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'trayLeftClick':
          await openTray();
        case 'showWindow':
          await showMain();
        case 'pauseAutomation':
          await model?.command('automatic', {'enabled': false});
        case 'exitRequested':
          await quit();
      }
    });
    _initialize();
  }

  Future<void> _setOpacity(double value) {
    // Coalesce animation frames if the native compositor is slower than Flutter.
    // A queue of obsolete opacity writes can delay the next open/close action.
    latestOpacity = value.clamp(0, 1);
    if (opacityBusy) return opacityWrites;
    opacityBusy = true;
    opacityWrites = () async {
      try {
        double sent;
        do {
          sent = latestOpacity;
          await windowManager.setOpacity(sent);
        } while (sent != latestOpacity);
      } finally {
        opacityBusy = false;
      }
    }();
    return opacityWrites;
  }

  Future<void> _animateTray(bool opening) async {
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      trayMotion.value = opening ? 1 : 0;
    } else if (opening) {
      await trayMotion.forward(from: 0);
    } else {
      await trayMotion.reverse();
    }
    await opacityWrites;
  }

  Future<void> hideTray() async {
    if (changingWindow || !tray || exiting) return;
    changingWindow = true;
    trayResizeTimer?.cancel();
    trayLayoutEpoch++;
    try {
      await _animateTray(false);
      await windowManager.hide();
      await _setOpacity(1);
    } finally {
      changingWindow = false;
    }
  }

  void _refresh() {
    final theme = model?.settings['Theme'] as String?;
    final appearanceChanged =
        desktopLanguage != language || desktopTheme != theme;
    unawaited(_syncDesktopLanguage());
    desktopTheme = theme;
    if (mounted && appearanceChanged) setState(() {});
  }

  Future<void> _syncDesktopLanguage() async {
    if (desktopLanguage == language) return;
    desktopLanguage = language;
    try {
      await Desktop.call('setLanguage', language);
    } catch (_) {}
  }

  void _onTrayContentSize(Size size) {
    trayContentSize = size;
    if (!tray || changingWindow || exiting) return;
    trayResizeTimer?.cancel();
    trayResizeTimer = Timer(
      const Duration(milliseconds: 60),
      () => unawaited(_fitTrayToContent()),
    );
  }

  Future<void> _fitTrayToContent() async {
    if (trayFitInProgress ||
        !tray ||
        exiting ||
        trayContentSize == null ||
        trayWorkArea == null) {
      return;
    }
    trayFitInProgress = true;
    final epoch = trayLayoutEpoch;
    try {
      for (int attempt = 0; attempt < 2; attempt++) {
        if (!mounted || !tray || exiting || epoch != trayLayoutEpoch) return;
        final bounds = await windowManager.getBounds();
        if (!mounted) return;
        final view = View.of(context);
        final viewport = view.physicalSize / view.devicePixelRatio;
        final content = trayContentSize!;
        if ((content.width - viewport.width).abs() > 1) return;
        final frameHeight = (bounds.height - viewport.height).clamp(0.0, 80.0);
        final fitted = trayBoundsForContent(
          content: content,
          frameHeight: frameHeight,
          workArea: trayWorkArea!,
        );
        if ((bounds.height - fitted.height).abs() < 1 &&
            (bounds.top - fitted.top).abs() < 1) {
          break;
        }
        if (!tray || epoch != trayLayoutEpoch) return;
        await windowManager.setBounds(fitted);
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 200),
          onTimeout: () {},
        );
      }
    } finally {
      trayFitInProgress = false;
    }
  }

  Future<void> _initialize() async {
    try {
      await _syncDesktopLanguage();
      trayReady = await Desktop.call<bool>('initTray') ?? false;
    } catch (_) {}
    final backgroundStart =
        !widget.forceShow &&
        trayReady &&
        (widget.trayStart || model?.settings['StartMinimized'] == true);
    if (!backgroundStart && !widget.selfCheck) await showMain();
    await model?.initialize();
    if (widget.selfCheck) {
      await _selfCheck();
      return;
    }
    if (backgroundStart) {
      await windowManager.hide();
    }
  }

  Future<void> _selfCheck() async {
    final report = File(
      '${File(Platform.resolvedExecutable).parent.path}/desktop-checks.txt',
    );
    final checks = <String>[];
    try {
      if (model?.demo != true || !trayReady) throw StateError('演示后端或原生托盘未就绪');
      checks.add('PASS: demo backend / Shell_NotifyIcon tray');
      await Desktop.call<bool>('startupGet');
      checks.add('PASS: read current-user startup setting (no mutation)');
      await showMain();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final original = await windowManager.getBounds();
      final watch = Stopwatch()..start();
      await openTray();
      if (mainTrayRoute == null ||
          tray ||
          !await windowManager.isVisible() ||
          await windowManager.getBounds() != original) {
        throw StateError('可见主窗口被托盘菜单隐藏或调整了尺寸');
      }
      if (watch.elapsedMilliseconds > 400) throw StateError('可见窗口托盘弹出延迟过高');
      checks.add(
        'PASS: tray popover opens promptly and preserves visible main bounds',
      );
      _dismissMainTray();
      await windowManager.hide();
      await openTray();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final compact = await windowManager.getSize();
      if ((compact.width - 368).abs() > 5 || !tray) {
        throw StateError('托盘浮层尺寸不正确：$compact');
      }
      checks.add('PASS: compact tray panel / native window resize');
      if (!mounted) throw StateError('窗口已关闭');
      final view = View.of(context);
      final clientHeight = view.physicalSize.height / view.devicePixelRatio;
      final heightCapped = compact.height >= trayWorkArea!.height - 1;
      if (trayContentSize == null ||
          (!heightCapped &&
              (clientHeight - trayContentSize!.height).abs() > 2)) {
        throw StateError('托盘内容与窗口高度不一致');
      }
      checks.add(
        'PASS: tray height fits measured content including fixed bottom inset',
      );
      final savedProfiles = model!.settings['Profiles'];
      model!.settings['Profiles'] = <dynamic>[];
      model!.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final emptySize = await windowManager.getSize();
      if (!heightCapped && emptySize.height >= compact.height - 10) {
        throw StateError('无快捷配置时未收紧托盘高度');
      }
      checks.add(
        'PASS: empty quick-profile tray shrinks without a blank footer',
      );
      model!.settings['Profiles'] = savedProfiles;
      model!.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if ((!WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations &&
              trayAnimationFrames < 3) ||
          trayMotion.value != 1 ||
          (await windowManager.getOpacity() - 1).abs() > .01) {
        throw StateError('托盘弹出动画未完成');
      }
      await hideTray();
      if (trayMotion.value != 0 || await windowManager.isVisible()) {
        throw StateError('托盘收起动画未完成');
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await openTray();
      checks.add(
        'PASS: tray fade in/out / second opening / final native opacity',
      );
      model!.stage('crosshair', 3);
      await model!.flush();
      if (model!.value('crosshair') != 3) throw StateError('准星设置失败');
      checks.add('PASS: tray crosshair through real JSONL host (demo only)');
      await showMain();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final restored = await windowManager.getBounds();
      if ((restored.width - original.width).abs() > 5 ||
          (restored.height - original.height).abs() > 5 ||
          tray) {
        throw StateError('主窗口尺寸未恢复');
      }
      checks.add('PASS: main window restored / taskbar visibility');
      final clickWait =
          await Desktop.call<int>('testTrayClick', 'single') ?? 500;
      await Future<void>.delayed(Duration(milliseconds: clickWait + 400));
      if (mainTrayRoute == null || tray || !await windowManager.isVisible()) {
        throw StateError('Single tray click did not open the panel');
      }
      checks.add('PASS: native single click opens tray panel');
      final singlesBefore = await Desktop.call<int>('trayClickCount');
      await Desktop.call<int>('testTrayClick', 'double');
      await Future<void>.delayed(Duration(milliseconds: clickWait + 500));
      if (tray || mainTrayRoute != null || !await windowManager.isVisible()) {
        throw StateError('Double tray click did not open the main window');
      }
      if (await Desktop.call<int>('trayClickCount') != singlesBefore) {
        throw StateError('双击错误触发了单击菜单');
      }
      checks.add(
        'PASS: native double click opens main without a delayed single click',
      );
      Element? selector;
      void visit(Element element) {
        if (selector == null &&
            element.widget is DesktopSelect<int> &&
            (element.widget as DesktopSelect<int>).onChanged != null) {
          selector = element;
        }
        element.visitChildElements(visit);
      }

      navigator.currentContext!.visitChildElements(visit);
      if (selector == null) throw StateError('没有找到可用下拉菜单');
      final frames = <ui.FrameTiming>[];
      void record(List<ui.FrameTiming> batch) => frames.addAll(batch);
      WidgetsBinding.instance.addTimingsCallback(record);
      try {
        final menu = (selector!.widget as DesktopSelect<int>).open(selector!);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        navigator.currentState!.pop();
        await menu;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      } finally {
        WidgetsBinding.instance.removeTimingsCallback(record);
      }
      if (UiActivity.active) throw StateError('下拉菜单关闭后未释放交互状态');
      checks.add('PASS: desktop selector entrance/exit on native renderer');
      if (frames.isNotEmpty) {
        double percentile(Iterable<Duration> durations) {
          final samples = durations.map((d) => d.inMicroseconds / 1000).toList()
            ..sort();
          return samples[((samples.length - 1) * .95).round()];
        }

        checks.add(
          'TIMING: menu ${frames.length} frames, UI p95=${percentile(frames.map((f) => f.buildDuration)).toStringAsFixed(2)} ms, raster p95=${percentile(frames.map((f) => f.rasterDuration)).toStringAsFixed(2)} ms',
        );
      }
      await report.writeAsString('${checks.join('\n')}\n');
    } catch (e) {
      await report.writeAsString('${checks.join('\n')}\nFAIL: $e\n');
    }
    await quit();
  }

  Future<void> showMain() async {
    _dismissMainTray();
    if (changingWindow) {
      showMainPending = true;
      return;
    }
    showMainPending = false;
    if (await windowManager.isMinimized()) await windowManager.restore();
    if (!tray && await windowManager.isVisible()) {
      await windowManager.focus();
      return;
    }
    if (tray && !changingWindow && await windowManager.isVisible()) {
      await hideTray();
    }
    changingWindow = true;
    trayResizeTimer?.cancel();
    trayLayoutEpoch++;
    await windowManager.hide();
    await _setOpacity(0);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(1040, 700));
    if (mainBounds != null) await windowManager.setBounds(mainBounds!);
    if (wasMaximized) await windowManager.maximize();
    if (mounted) setState(() => tray = false);
    await windowManager.show();
    await windowManager.focus();
    // A hidden desktop window may stop producing frames. Show it before
    // awaiting a frame, and bound the wait so reopening cannot deadlock.
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );
    await _setOpacity(1);
    changingWindow = false;
    model?.tick();
  }

  Future<void> openTray() async {
    if (changingWindow || exiting) return;
    if (mainTrayRoute != null) {
      _dismissMainTray();
      return;
    }
    if (!tray &&
        await windowManager.isVisible() &&
        !await windowManager.isMinimized()) {
      final nav = navigator.currentState;
      if (nav == null || model == null) return;
      final route = RawDialogRoute<void>(
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        barrierLabel: language == 'zh' ? '关闭托盘菜单' : 'Dismiss tray menu',
        transitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, _, _) => TrayPopover(
          key: const ValueKey('main-tray-popover'),
          model: model!,
          onOpen: showMain,
          onClose: _dismissMainTray,
        ),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );
      mainTrayRoute = route;
      unawaited(
        nav.push(route).whenComplete(() {
          if (mainTrayRoute == route) mainTrayRoute = null;
        }),
      );
      await windowManager.focus();
      return;
    }
    if (navigator.currentState?.canPop() == true) {
      await showMain();
      return;
    }
    if (tray && await windowManager.isVisible()) {
      await hideTray();
      return;
    }
    changingWindow = true;
    trayLayoutEpoch++;
    if (!tray) {
      mainBounds = await windowManager.getBounds();
      wasMaximized = await windowManager.isMaximized();
    }
    await windowManager.hide();
    await _setOpacity(0);
    trayMotion.value = 0;
    if (mounted) setState(() => tray = true);
    if (wasMaximized) await windowManager.unmaximize();
    final topLeft = await calcWindowPosition(Size.zero, Alignment.topLeft);
    final bottomRight = await calcWindowPosition(
      Size.zero,
      Alignment.bottomRight,
    );
    trayWorkArea = Rect.fromPoints(topLeft, bottomRight).deflate(8);
    await windowManager.setMinimumSize(const Size(360, 240));
    await windowManager.setSize(const Size(368, 620));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.show();
    await windowManager.focus();
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(milliseconds: 50),
      onTimeout: () {},
    );
    // Fit in parallel with the entrance animation; never wait for hardware or
    // extra frame timeouts before the first visible tray frame.
    unawaited(_fitTrayToContent());
    await _animateTray(true);
    changingWindow = false;
    if (showMainPending) {
      await showMain();
      return;
    }
    if (!await windowManager.isFocused() && !widget.selfCheck) await hideTray();
    model?.tick();
  }

  void _dismissMainTray() {
    final route = mainTrayRoute;
    mainTrayRoute = null;
    if (route?.isActive == true) navigator.currentState?.removeRoute(route!);
  }

  @override
  void onWindowBlur() {
    if (mainTrayRoute != null) _dismissMainTray();
    if (tray && !changingWindow && !exiting) unawaited(hideTray());
  }

  @override
  void onWindowClose() async {
    if (exiting) return;
    if (trayReady && model?.settings['MinimizeToTray'] != false) {
      if (tray) {
        await hideTray();
      } else {
        await windowManager.hide();
      }
    } else {
      await quit();
    }
  }

  Future<void> quit() async {
    if (exiting) return;
    exiting = true;
    await model?.shutdown();
    await windowManager.setPreventClose(false);
    // Follow WM_CLOSE/WM_DESTROY so the runner tears down the engine with the
    // window. window_manager's Windows destroy() only posts WM_QUIT.
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final mode = model?.settings['Theme'];
    return MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      title: 'GO27Q32 Lite',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode == 'dark'
          ? ThemeMode.dark
          : mode == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      home: model == null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: LSelectableText(widget.failure ?? '无法启动控制服务'),
                ),
              ),
            )
          : tray
          ? SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .018),
                end: Offset.zero,
              ).animate(trayCurve),
              child: TrayPanel(
                model: model!,
                onOpen: showMain,
                onClose: hideTray,
                onContentSize: _onTrayContentSize,
              ),
            )
          : AppShell(
              model: model!,
              onQuit: quit,
              trayReady: trayReady,
              initialPage: mainPage,
              onPageChanged: (page) => mainPage = page,
            ),
    );
  }

  @override
  void dispose() {
    trayResizeTimer?.cancel();
    trayCurve.dispose();
    trayMotion.dispose();
    windowManager.removeListener(this);
    model?.removeListener(_refresh);
    model?.dispose();
    super.dispose();
  }
}
