import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/editors.dart';
import 'package:go27q32_lite/theme.dart';
import 'support.dart';

void main() {
  testWidgets(
    'existing HDR crosshair can be edited without a preset or SDR values',
    (t) async {
      final fake = FakeTransport();
      fake.state['hdr']['Enabled'] = true;
      fake.state['hdr']['ActiveHdr'] = true;
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      final existing = <String, dynamic>{
        'Id': 'cod',
        'Name': 'COD',
        'MonitorId': m.monitorId,
        'HdrPolicy': -1,
        'HdrPreset': null,
        'Values': <String, dynamic>{},
        'HdrValues': <String, dynamic>{'crosshair': 2, 'brightness': 80},
      };
      Json? result;
      await t.binding.setSurfaceSize(const Size(1100, 900));
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Json>(
                  context: context,
                  builder: (_) => ProfileEditor(model: m, existing: existing),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final crosshair = find.byKey(const ValueKey('profile-value-crosshair'));
      await t.ensureVisible(crosshair);
      await t.pumpAndSettle();
      await t.tap(crosshair);
      await t.pumpAndSettle();
      await t.tap(find.text('准星 3'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存配置'));
      await t.pumpAndSettle();
      expect(result!['HdrValues'], {'crosshair': 3, 'brightness': 80});
      expect(result!['Values'], isEmpty);
      expect(result!['HdrPreset'], isNull);
      expect(fake.calls, ['init']);
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'HDR editor captures independent controls, never shadow picture readings',
    (t) async {
      final fake = FakeTransport();
      fake.state['hdr']['Enabled'] = true;
      fake.state['hdr']['ActiveHdr'] =
          true; // Keep old shadow values in the fixture to reproduce the bug.
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      Json? result;
      await t.binding.setSurfaceSize(const Size(1100, 900));
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Json>(
                  context: context,
                  builder: (_) => ProfileEditor(model: m),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.text('亮度'), findsNothing);
      expect(find.text('准星'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('profile-hdr-preset')));
      await t.pumpAndSettle();
      await t.tap(find.text('HDR电影'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存配置'));
      await t.pumpAndSettle();
      expect(result!['HdrPreset'], 2);
      expect(result!['HdrPolicy'], 1);
      expect(result!['Values'], isEmpty);
      expect((result!['HdrValues'] as Json).keys.every(hdrProfile), isTrue);
      expect(result!['HdrValues']['crosshair'], m.confirmed('crosshair'));
      expect(fake.calls, ['init']);
      expect(m.blocked('brightness'), isNotNull);
      m.stage('brightness', 99);
      await m.flush();
      expect(fake.calls, ['init']);
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'legacy HDR data stays separate until explicitly copied to SDR without overwriting',
    (t) async {
      final fake = FakeTransport();
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      final legacy = {
        'Id': 'legacy',
        'Name': 'Legacy',
        'MonitorId': m.monitorId,
        'HdrPolicy': 1,
        'HdrPreset': null,
        'Values': <String, dynamic>{'brightness': 42},
        'HdrValues': <String, dynamic>{'brightness': 80, 'contrast': 50},
      };
      Json? result;
      await t.binding.setSurfaceSize(const Size(1100, 900));
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Json>(
                  context: context,
                  builder: (_) => ProfileEditor(model: m, existing: legacy),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('亮度'), findsNothing);
      await t.tap(find.text('SDR 参数'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('copy-legacy-to-sdr')));
      await t.pumpAndSettle();
      await t.tap(find.text('HDR 设置'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('profile-hdr-preset')));
      await t.pumpAndSettle();
      await t.tap(find.text('HDR显示'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存配置'));
      await t.pumpAndSettle();
      expect(result!['Values'], {'brightness': 42, 'contrast': 50});
      expect(result!['HdrValues'], {'brightness': 80, 'contrast': 50});
      expect(result!['HdrPreset'], 0);
      expect(legacy['Values'], {'brightness': 42});
      expect(fake.calls, ['init']);
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );
}
