import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/app.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/game_timer.dart';
import 'package:go27q32_lite/l10n.dart';
import 'package:go27q32_lite/theme.dart';
import 'package:go27q32_lite/tray_popover.dart';
import 'package:go27q32_lite/ui_parts.dart';
import 'support.dart';

void main() {
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('go27q32/desktop'),
          (_) async => false,
        ),
  );
  Future<void> mount(WidgetTester t, Widget child, String language) async {
    t.view.devicePixelRatio = 1;
    await t.binding.setSurfaceSize(const Size(1320, 880));
    await t.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<ControlModel> create(String language) async {
    final m = ControlModel(FakeTransport());
    await m.initialize(polling: false);
    m.settings['Language'] = language;
    return m;
  }

  Future<void> cleanup(WidgetTester t, ControlModel m) async {
    await t.pumpWidget(const SizedBox.shrink());
    m.dispose();
    await t.binding.setSurfaceSize(null);
  }

  for (final language in ['zh', 'en']) {
    testWidgets('rule summary cards share top and bottom edges in $language', (
      t,
    ) async {
      final m = await create(language);
      await mount(t, AppShell(model: m, initialPage: 2), language);
      final left = find.byWidgetPredicate(
        (w) => w is SectionCard && w.title == '自动应用配置',
      );
      final right = find.byWidgetPredicate(
        (w) => w is SectionCard && w.title == '当前配置',
      );
      expect(t.getRect(left).top, t.getRect(right).top);
      expect(t.getRect(left).bottom, t.getRect(right).bottom);
      expect(find.byKey(const ValueKey('hdr-probe-open')), findsNothing);
      expect(t.takeException(), isNull);
      await cleanup(t, m);
    });
  }
  testWidgets(
    'timer validates seconds and distinguishes current time from start duration',
    (t) async {
      final m = await create('zh');
      await mount(
        t,
        AnimatedBuilder(
          animation: m,
          builder: (_, _) =>
              SingleChildScrollView(child: GameTimerCard(model: m)),
        ),
        'zh',
      );
      final start = find.byKey(const ValueKey('timer-start'));
      await t.enterText(find.byKey(const ValueKey('timer-59')), '60');
      await t.pump();
      expect(t.widget<FilledButton>(start).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('timer-99')), '99');
      await t.enterText(find.byKey(const ValueKey('timer-59')), '59');
      await t.pump();
      await t.tap(start);
      await t.pumpAndSettle();
      expect(m.confirmed('timerDuration'), 25403);
      await t.tap(find.byKey(const ValueKey('timer-pause')));
      await t.pumpAndSettle();
      expect(m.confirmed('timerRunning'), 0);
      await t.tap(find.byKey(const ValueKey('timer-mode')));
      await t.pumpAndSettle();
      expect(find.text('关闭'), findsNothing);
      await t.tap(find.text('倒计时').last);
      await t.pumpAndSettle();
      // Stopping does not depend on a valid pending countdown or chosen mode.
      await t.enterText(find.byKey(const ValueKey('timer-59')), '60');
      await t.pump();
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('timer-stop')))
            .onPressed,
        isNotNull,
      );
      await t.tap(find.byKey(const ValueKey('timer-stop')));
      await t.pumpAndSettle();
      expect(m.confirmed('gameTimer'), 0);
      expect(find.text('计时器已关闭'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('timer-stop')))
            .onPressed,
        isNull,
      );
      m.state['values']['timerDuration']['Value'] = 1280;
      m.notifyListeners();
      await t.pump();
      expect(find.text('05:00'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('timer-99')))
            .controller!
            .text,
        '99',
      );
      expect(t.takeException(), isNull);
      await cleanup(t, m);
    },
  );
  testWidgets('main tray popover fits content and leaves main page in place', (
    t,
  ) async {
    final m = await create('en');
    await mount(
      t,
      Stack(
        children: [
          const Positioned(left: 24, top: 24, child: Text('main-page')),
          Positioned.fill(
            child: TrayPopover(model: m, onOpen: () {}, onClose: () {}),
          ),
        ],
      ),
      'en',
    );
    final original = t.getRect(find.text('main-page'));
    final tray = find.byType(TrayPanel);
    expect(t.getSize(tray).width, 368);
    final first = t.getSize(tray).height;
    m.settings['Profiles'] = <dynamic>[];
    m.notifyListeners();
    await t.pumpAndSettle();
    expect(t.getSize(tray).height, lessThan(first));
    expect(t.getRect(find.text('main-page')), original);
    expect(t.takeException(), isNull);
    await cleanup(t, m);
  });
}
