import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/app.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/theme.dart';
import 'package:go27q32_lite/ui_parts.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('go27q32/desktop'),
          (_) async => false,
        ),
  );
  Future<ControlModel> createModel(FakeTransport transport) async {
    final model = ControlModel(transport);
    await model.initialize(polling: false);
    return model;
  }

  Future<void> mount(
    WidgetTester t,
    ControlModel model, {
    bool tray = false,
  }) async {
    t.view.devicePixelRatio = 1;
    await t.binding.setSurfaceSize(
      tray ? const Size(368, 620) : const Size(1320, 880),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: tray
            ? TrayPanel(model: model, onOpen: () {}, onClose: () {})
            : AppShell(model: model),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester t, ControlModel model) async {
    await t.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await t.binding.setSurfaceSize(null);
  }

  Finder feature(String id) =>
      find.byWidgetPredicate((w) => w is FeatureControl && w.id == id);
  for (final tray in [false, true]) {
    testWidgets(
      '${tray ? 'tray' : 'main'}: pending, write, failure and scrollbar never move controls',
      (t) async {
        final transport = FakeTransport(), model = await createModel(transport);
        await mount(t, model, tray: tray);
        final brightness = t.getRect(feature('brightness').first);
        final anchor = tray
            ? find.byKey(const ValueKey('tray-crosshair'))
            : feature('gamma');
        final anchorBefore = t.getRect(anchor.first);
        final scrollbar = t.state<ScrollableState>(
          find.byType(Scrollable).last,
        );
        final extent = scrollbar.position.maxScrollExtent;
        transport.heldSet = Completer<dynamic>();
        model.stage('brightness', 72);
        final writing = model.flush();
        await t.pump(const Duration(milliseconds: 120));
        expect(model.busy, isTrue);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(t.getRect(feature('brightness').first), brightness);
        expect(t.getRect(anchor.first), anchorBefore);
        expect(scrollbar.position.maxScrollExtent, extent);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        await mouse.moveTo(Offset(tray ? 364 : 1316, 380));
        await t.pump(const Duration(milliseconds: 80));
        expect(t.getRect(anchor.first), anchorBefore);
        transport.heldSet!.completeError(StateError('测试：硬件写入失败，保持原确认值'));
        await writing;
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('operation-error')), findsOneWidget);
        expect(t.getRect(feature('brightness').first), brightness);
        expect(t.getRect(anchor.first), anchorBefore);
        expect(scrollbar.position.maxScrollExtent, extent);
        await t.tap(find.byTooltip('关闭提示'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('operation-error')), findsNothing);
        expect(t.getRect(anchor.first), anchorBefore);
        expect(t.takeException(), isNull);
        await mouse.removePointer();
        await cleanup(t, model);
      },
    );
  }
  testWidgets('HDR flow spacing, compact parameter header and menu gaps', (
    t,
  ) async {
    final transport = FakeTransport(), model = await createModel(transport);
    await mount(t, model);
    final destinations = find.byType(NavigationDrawerDestination);
    final gap =
        t.getRect(destinations.at(1)).top -
        t.getRect(destinations.at(0)).bottom;
    expect(gap, greaterThanOrEqualTo(8));
    await t.tap(
      find.descendant(
        of: find.byType(NavigationDrawer),
        matching: find.text('HDR 状态'),
      ),
    );
    await t.pumpAndSettle();
    final left = t.getCenter(find.byKey(const ValueKey('hdr-flow-系统请求'))),
        arrow = t.getCenter(find.byKey(const ValueKey('hdr-flow-arrow'))),
        right = t.getCenter(find.byKey(const ValueKey('hdr-flow-实际输出')));
    expect(arrow.dx - left.dx, closeTo(right.dx - arrow.dx, .1));
    final leftState = t.getCenter(find.byKey(const ValueKey('hdr-state-系统请求')));
    final rightState = t.getCenter(
      find.byKey(const ValueKey('hdr-state-实际输出')),
    );
    expect(leftState.dy, closeTo(arrow.dy, .1));
    expect(rightState.dy, closeTo(arrow.dy, .1));
    final divider = find
        .descendant(
          of: find.byKey(const ValueKey('hdr-parameters-card')),
          matching: find.byType(Divider),
        )
        .first;
    final control = t.getRect(
      find.byKey(const ValueKey('hdr-brightness-control')),
    );
    expect(control.top - t.getRect(divider).bottom, closeTo(0, .1));
    await t.tap(
      find.descendant(
        of: find.byType(NavigationDrawer),
        matching: find.text('设置'),
      ),
    );
    await t.pumpAndSettle();
    final title = t.element(find.text('开机自启'));
    final subtitle = t.element(find.text('Windows 登录后在托盘后台运行'));
    expect(DefaultTextStyle.of(title).style.fontSize, 14);
    expect(DefaultTextStyle.of(subtitle).style.fontSize, 12);
    await cleanup(t, model);
  });
}
