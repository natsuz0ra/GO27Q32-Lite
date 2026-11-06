import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/desktop_select.dart';
import 'package:go27q32_lite/theme.dart';

void main() {
  testWidgets(
    'floating selector label paints above the outline without clipping',
    (t) async {
      final boundaryKey = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: buildTheme(
              Brightness.light,
            ).copyWith(hoverColor: Colors.pink),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: DesktopSelect<int>(
                    key: const ValueKey('labeled-selector'),
                    initialValue: 2,
                    decoration: const InputDecoration(
                      labelText: 'Timer Mode',
                      labelStyle: TextStyle(color: Colors.pink),
                      floatingLabelStyle: TextStyle(color: Colors.pink),
                    ),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('Countdown')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = t.getRect(find.byKey(const ValueKey('labeled-selector')));
      final label = t.getRect(find.text('Timer Mode'));
      expect(label.top, lessThan(field.top));
      final region = Rect.fromLTRB(
        label.left.floorToDouble(),
        label.top.floorToDouble(),
        label.right.ceilToDouble(),
        field.top.floorToDouble(),
      );
      final pinkPixels = await t.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var count = 0;
        for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
          for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
            final i = (y * image.width + x) * 4;
            if (bytes[i] > 160 && bytes[i + 1] < 100 && bytes[i + 2] > 60) {
              count++;
            }
          }
        }
        image.dispose();
        return count;
      });
      expect(
        pinkPixels,
        greaterThan(0),
        reason:
            'The part of the floating label above the field must remain painted.',
      );
      Future<List<int>> corners() async => (await t.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final pixels = <int>[];
        for (final point in [
          Offset(field.left + 1, field.bottom - 2),
          Offset(field.right - 2, field.bottom - 2),
        ]) {
          final i = (point.dy.floor() * image.width + point.dx.floor()) * 4;
          pixels.addAll(bytes.sublist(i, i + 4));
        }
        image.dispose();
        return pixels;
      }))!;
      final original = await corners();
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(field.center);
      await t.pumpAndSettle();
      expect(
        await corners(),
        original,
        reason: 'The hover ink must still respect the rounded outline.',
      );
      await mouse.removePointer();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
