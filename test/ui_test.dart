import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/app.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/editors.dart';
import 'package:go27q32_lite/game_timer.dart';
import 'package:go27q32_lite/l10n.dart';
import 'package:go27q32_lite/theme.dart';
import 'package:go27q32_lite/ui_parts.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('HarmonyOS')
      ..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans_SC_Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('go27q32/desktop'),
          (_) async => false,
        );
  });
  Future<ControlModel> model() async {
    final transport = FakeTransport();
    transport.data['settings']['Rules'] = [
      {
        'Enabled': true,
        'ExecutablePath': r'C:\Games\Cyberpunk 2077\Cyberpunk2077.exe',
        'ProfileId': 'game',
        'Priority': 20,
      },
      {
        'Enabled': false,
        'ExecutablePath': r'C:\Program Files\Video\PotPlayer.exe',
        'ProfileId': 'movie',
        'Priority': 10,
      },
    ];
    final m = ControlModel(transport);
    await m.initialize(polling: false);
    return m;
  }

  final captureKey = GlobalKey();
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/go27q32.png'),
        captureKey.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('docs/preview').create(recursive: true);
      await File(
        'docs/preview/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> host(
    WidgetTester tester,
    ControlModel m, {
    bool dark = false,
    Widget? child,
    String? language,
    Size size = const Size(1320, 880),
  }) async {
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: AnimatedBuilder(
          animation: m,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(
              language ?? m.settings['Language'] as String? ?? 'zh',
            ),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildTheme(dark ? Brightness.dark : Brightness.light),
            home: child ?? AppShell(model: m),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('game timer layouts in both languages', (tester) async {
    final m = await model();
    for (final language in ['zh', 'en']) {
      await m.preference('Language', language);
      await host(
        tester,
        m,
        language: language,
        size: const Size(720, 700),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: GameTimerCard(model: m),
          ),
        ),
      );
      await capture(tester, 'game-timer-$language');
      final card = tester.getRect(
        find.byKey(const ValueKey('game-timer-card')),
      );
      final position = tester.getRect(
        find.byKey(const ValueKey('assistPosition-false')),
      );
      expect(card.bottom - position.bottom, closeTo(12, 1));
      expect(card.height, lessThan(570));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    m.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'English pages, settings and tray fit at desktop and minimum sizes',
    (tester) async {
      final m = await model();
      m.profiles.first['Name'] = '画面模式';
      await m.preference('Language', 'en');
      await host(tester, m);
      expect(find.text('Display'), findsWidgets);
      expect(find.text('画面模式'), findsWidgets);
      for (int i = 0; i < 5; i++) {
        final title = [
          'Display',
          'HDR Status',
          'App Rules',
          'Profiles',
          'Settings',
        ][i];
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationDrawer),
            matching: find.text(title),
          ),
        );
        await capture(tester, 'en-$i');
        if (i == 3) {
          final name = tester.getRect(
            find.byKey(const ValueKey('profile-name-daily')),
          );
          final badge = tester.getRect(
            find.byKey(const ValueKey('profile-in-use-daily')),
          );
          expect(badge.center.dy, closeTo(name.center.dy, 1));
          expect(badge.left - name.right, closeTo(10, 1));
        }
      }
      final language = find.byKey(const ValueKey('app-language'));
      await tester.ensureVisible(language);
      await tester.pumpAndSettle();
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').last);
      await tester.pumpAndSettle();
      expect(m.settings['Language'], 'zh');
      expect(find.text('界面语言'), findsWidgets);
      await m.preference('Language', 'en');
      await host(tester, m, dark: true, size: const Size(1040, 700));
      for (final title in [
        'Display',
        'HDR Status',
        'App Rules',
        'Profiles',
        'Settings',
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationDrawer),
            matching: find.text(title),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await host(
        tester,
        m,
        size: const Size(368, 620),
        child: TrayPanel(model: m, onOpen: () {}, onClose: () {}),
      );
      await capture(tester, 'en-tray');
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('disabled setting tooltip is anchored above its dropdown', (
    tester,
  ) async {
    final m = await model();
    await m.command('hdr', {'enabled': true});
    await host(
      tester,
      m,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 100,
            child: FeatureControl(model: m, id: 'pictureMode'),
          ),
        ),
      ),
    );
    final control = tester.getRect(
      find.byKey(const ValueKey('pictureMode-true')),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(control.center);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final tip = tester.getRect(
      find.text('HDR 专用预设请通过显示器菜单切换', findRichText: true),
    );
    expect((tip.center.dx - control.center.dx).abs(), lessThan(5));
    expect(tip.bottom, lessThan(control.top));
    await capture(tester, 'control-tooltip');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    m.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('five pages, dark mode, minimum window and offline layout', (
    tester,
  ) async {
    final m = await model();
    await host(tester, m);
    expect(find.text('托盘浮层'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await capture(tester, 'display');
    final description = tester.getRect(
      find.byKey(const ValueKey('hdr-card-description')),
    );
    final link = tester.getRect(
      find.byKey(const ValueKey('hdr-card-link-label')),
    );
    expect(description.left, closeTo(link.left, .5));
    final linkButton = find.byKey(const ValueKey('hdr-card-link'));
    await tester.ensureVisible(linkButton);
    await tester.pumpAndSettle();
    expect(tester.getSize(linkButton).height, greaterThanOrEqualTo(40));
    final linkMouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await linkMouse.addPointer();
    await linkMouse.moveTo(tester.getCenter(linkButton));
    await capture(tester, 'hdr-link-hover');
    await linkMouse.removePointer();
    for (int i = 1; i < 5; i++) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDrawer),
          matching: find.text(pageNames[i]),
        ),
      );
      await capture(
        tester,
        ['display', 'hdr', 'rules', 'profiles', 'settings'][i],
      );
      if (i == 4) {
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(find.text('关闭后驻留托盘')));
        await capture(tester, 'settings-hover');
        await mouse.removePointer();
      }
    }
    await host(tester, m, dark: true);
    await capture(tester, 'dark');
    await host(tester, m, size: const Size(1040, 700));
    await capture(tester, 'minimum');
    for (int i = 0; i < 5; i++) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDrawer),
          matching: find.text(pageNames[i]),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    m.state['connected'] = false;
    await host(tester, m);
    await capture(tester, 'offline');
    await tester.pumpWidget(const SizedBox.shrink());
    m.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'device settings use real command values and follow external changes',
    (tester) async {
      final m = await model();
      await host(tester, m);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDrawer),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      final timeout = find.byKey(const ValueKey('osdTimeout-false'));
      await tester.ensureVisible(timeout);
      await tester.pumpAndSettle();
      await tester.tap(timeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 秒').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(m.confirmed('osdTimeout'), 5);
      m.state['values']['osdTimeout']['Value'] = 3;
      m.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: timeout, matching: find.text('20 秒')),
        findsOneWidget,
      );
      final joystick = find.byKey(const ValueKey('joystickUp-false'));
      await tester.ensureVisible(joystick);
      await tester.pumpAndSettle();
      await tester.tap(joystick);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ultra Clear').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(m.confirmed('joystickUp'), 13);
      expect(m.state['canUndo'], isFalse);
      await tester.ensureVisible(find.text('摇杆向右'));
      await capture(tester, 'settings-device');
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('profile editor, rule editor and tray are aligned and usable', (
    tester,
  ) async {
    final m = await model();
    await host(
      tester,
      m,
      child: Scaffold(body: ProfileEditor(model: m)),
    );
    await capture(tester, 'profile-editor');
    await host(
      tester,
      m,
      child: Scaffold(body: RuleEditor(model: m)),
    );
    await capture(tester, 'rule-editor');
    await host(
      tester,
      m,
      size: const Size(1040, 700),
      child: Scaffold(body: ProfileEditor(model: m)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await host(
      tester,
      m,
      size: const Size(368, 620),
      child: TrayPanel(model: m, onOpen: () {}, onClose: () {}),
    );
    await capture(tester, 'tray');
    final segment = tester.getRect(
      find.byKey(const ValueKey('tray-crosshair')),
    );
    final divider = tester.getRect(
      find.byKey(const ValueKey('tray-game-divider')),
    );
    final hdrSwitch = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('tray-hdr-row')),
        matching: find.byType(Switch),
      ),
    );
    final before = divider.top - segment.bottom;
    final after = hdrSwitch.center.dy - 16 - divider.bottom;
    expect(before, closeTo(16, .5));
    expect(after, closeTo(before, .5));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(
      scroll.position.maxScrollExtent,
      0,
      reason: 'normal tray contents fit without hidden footer buttons',
    );
    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(m.value('crosshair'), 3);
    m.settings['Profiles'] = <dynamic>[];
    Size? compact;
    await host(
      tester,
      m,
      size: const Size(368, 620),
      child: TrayPanel(
        model: m,
        onOpen: () {},
        onClose: () {},
        onContentSize: (size) => compact = size,
      ),
    );
    await host(
      tester,
      m,
      size: Size(368, compact!.height.ceilToDouble()),
      child: TrayPanel(model: m, onOpen: () {}, onClose: () {}),
    );
    await capture(tester, 'tray-empty');
    await tester.pumpWidget(const SizedBox.shrink());
    m.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
