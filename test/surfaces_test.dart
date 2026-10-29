import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/app.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/theme.dart';
import 'package:go27q32_lite/tray_layout.dart';
import 'package:go27q32_lite/ui_parts.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'card hover and pressed ink cannot paint outside bottom rounded corners',
    (t) async {
      final capture = GlobalKey(), card = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const SizedBox.shrink(),
          ),
        ),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              backgroundColor: Colors.green,
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: 320,
                    child: SectionCard(
                      key: card,
                      title: '启动与托盘',
                      child: SwitchListTile(
                        title: const Text('关闭后驻留托盘'),
                        value: true,
                        hoverColor: Colors.pink,
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(card));
      Future<List<int>> cornerPixels() async => (await t.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        final result = <int>[];
        for (final point in [
          Offset(rect.left + 2, rect.bottom - 3),
          Offset(rect.right - 3, rect.bottom - 3),
        ]) {
          final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
          result.addAll(bytes.sublist(index, index + 4));
        }
        image.dispose();
        return result;
      }))!;
      final original = await cornerPixels();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      final target = t.getCenter(find.byType(SwitchListTile));
      await mouse.moveTo(target);
      await t.pumpAndSettle();
      expect(
        await cornerPixels(),
        original,
        reason: 'hover tint must respect the card silhouette',
      );
      await mouse.down(target);
      await t.pump(const Duration(milliseconds: 160));
      expect(
        await cornerPixels(),
        original,
        reason: 'pressed ripple must respect the card silhouette',
      );
      await mouse.up();
      await mouse.removePointer();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'tray with no quick profiles measures content and leaves exactly 16px below its button',
    (t) async {
      final transport = FakeTransport(), m = ControlModel(transport);
      await m.initialize(polling: false);
      m.settings['Profiles'] = <dynamic>[];
      Size? measured;
      await t.binding.setSurfaceSize(const Size(368, 620));
      Widget panel() => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TrayPanel(
          model: m,
          onOpen: () {},
          onClose: () {},
          onContentSize: (size) => measured = size,
        ),
      );
      await t.pumpWidget(panel());
      await t.pumpAndSettle();
      expect(measured, isNotNull);
      expect(measured!.height, lessThan(600));
      await t.binding.setSurfaceSize(
        Size(368, measured!.height.ceilToDouble()),
      );
      await t.pumpAndSettle();
      final button = t.getRect(find.byKey(const ValueKey('tray-open-main')));
      expect(measured!.height - button.bottom, closeTo(16, 1));
      final before = measured;
      transport.heldSet = Completer<dynamic>();
      m.stage('brightness', 72);
      final writing = m.flush();
      await t.pump();
      expect(measured, before);
      transport.heldSet!.complete(copyJson(transport.state));
      await writing;
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await transport.close();
      await t.binding.setSurfaceSize(null);
    },
  );
  test(
    'tray bounds follow content height, keep their bottom anchor, and cap to the work area',
    () {
      const area = Rect.fromLTWH(8, 8, 1904, 1000);
      final short = trayBoundsForContent(
        content: const Size(355, 500),
        frameHeight: 12,
        workArea: area,
      );
      final tall = trayBoundsForContent(
        content: const Size(355, 620),
        frameHeight: 12,
        workArea: area,
      );
      expect(short.height, 512);
      expect(tall.height, 632);
      expect(short.bottom, tall.bottom);
      expect(short.right, area.right);
      final capped = trayBoundsForContent(
        content: const Size(355, 1600),
        frameHeight: 12,
        workArea: area,
      );
      expect(capped.height, area.height);
      expect(capped.top, area.top);
    },
  );
}
