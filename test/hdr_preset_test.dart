import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/core/control.dart';
import 'package:go27q32_lite/hdr_preset_card.dart';
import 'package:go27q32_lite/l10n.dart';
import 'package:go27q32_lite/theme.dart';
import 'package:go27q32_lite/ui_parts.dart';
import 'support.dart';

void main() {
  test(
    'blackout waits once, suppresses polling, and continues recovery after the first wait window',
    () async {
      final fake = FakeTransport();
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      await m.command('hdr', {'enabled': true});
      fake.heldTick = Completer<dynamic>();
      final stalePoll = m.tick();
      fake.heldHdrPreset = Completer<dynamic>();
      final sending = m.command('hdrPreset', {'value': 0});
      expect(m.hdrPresetSwitching, isTrue);
      expect(m.blocked('brightness'), contains('重新连接'));
      await m.tick();
      expect(fake.calls.where((c) => c == 'hdrPreset').length, 1);
      fake.heldTick!.completeError(
        StateError('temporary disconnected display'),
      );
      await stalePoll;
      expect(m.error, isNull);
      final waiting = copyJson(fake.state);
      waiting['hdr'] = null;
      waiting['connected'] = false;
      waiting['hdrPresetRecovering'] = true;
      waiting['hdrPresetRequest'] = {'Value': 0, 'MonitorId': m.monitorId};
      fake.heldHdrPreset!.complete(waiting);
      expect(await sending, isTrue);
      expect(m.busy, isFalse);
      expect(m.hdrPresetSwitching, isTrue);
      expect(m.hdrPresetRequest?['Value'], 0);
      expect(m.hdrSwitchBlocked, contains('连接恢复'));
      fake.heldTick = null;
      fake.state['hdrPresetRecovering'] = false;
      fake.state['connected'] = true;
      await m.tick();
      expect(m.hdrPresetSwitching, isFalse);
      expect(m.error, isNull);
      expect(fake.calls.where((c) => c == 'hdrPreset').length, 1);
      m.dispose();
    },
  );
  testWidgets(
    'Windows HDR can be turned off from its switch while rules are active',
    (t) async {
      final fake = FakeTransport();
      fake.state['hdr']['Enabled'] = true;
      fake.state['hdr']['ActiveHdr'] = true;
      fake.state['automatic'] = true;
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      await t.pumpWidget(
        AnimatedBuilder(
          animation: m,
          builder: (_, _) => MaterialApp(
            home: Scaffold(body: HdrSwitch(model: m)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(fake.calls, contains('hdr'));
      expect(m.hdrEnabled, isFalse);
      expect(m.automatic, isFalse);
      m.state['hdr'] = null;
      expect(m.hdrSwitchBlocked, isNotNull);
      expect(m.hdrPresetBlocked, isNotNull);
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
    },
  );
  testWidgets(
    'HDR picker is a command, allows zero and repeat, never reports current mode',
    (t) async {
      final fake = FakeTransport();
      final m = ControlModel(fake);
      await m.initialize(polling: false);
      await t.binding.setSurfaceSize(const Size(360, 780));
      await t.pumpWidget(
        AnimatedBuilder(
          animation: m,
          builder: (_, _) => MaterialApp(
            theme: buildTheme(Brightness.light),
            localizationsDelegates: const [AppLocalizations.delegate],
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: HdrPresetCard(model: m)),
          ),
        ),
      );
      await t.pumpAndSettle();
      FilledButton button() =>
          t.widget<FilledButton>(find.byKey(const ValueKey('hdr-preset-send')));
      expect(button().onPressed, isNull);
      expect(find.text('No request this session'), findsOneWidget);
      await m.command('hdr', {'enabled': true});
      await t.pumpAndSettle();
      expect(button().onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('hdr-preset-picker')));
      await t.pumpAndSettle();
      expect(find.text('HDR Peak 1300'), findsOneWidget);
      await t.tap(find.text('HDR Display'));
      await t.pumpAndSettle();
      expect(fake.calls.where((c) => c == 'hdrPreset'), isEmpty);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byKey(const ValueKey('hdr-preset-send')));
        await t.pumpAndSettle();
      }
      expect(fake.calls.where((c) => c == 'hdrPreset').length, 2);
      expect(m.hdrPresetRequest?['Value'], 0);
      expect(m.confirmed('pictureMode'), isNull);
      expect(find.text('Last Request (Not Current Mode)'), findsOneWidget);
      expect(find.text('HDR Display'), findsNWidgets(2));
      await m.command('automatic', {'enabled': true});
      await t.pumpAndSettle();
      expect(button().onPressed, isNotNull);
      expect(
        find.text(
          'Switching manually pauses app rules. Saved profiles stay unchanged.',
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('hdr-preset-send')));
      await t.pumpAndSettle();
      expect(m.automatic, isFalse);
      expect(m.hdrPresetRequest?['Value'], 0);
      await m.command('automatic', {'enabled': true});
      await m.command('hdr', {'enabled': false});
      await t.pumpAndSettle();
      expect(m.automatic, isFalse);
      expect(find.text('No request this session'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );

  test('new HDR copy is translated rather than falling back to Chinese', () {
    const en = AppLocalizations('en');
    for (final message in [
      'HDR显示',
      'HDR游戏',
      'HDR电影',
      'HDR亮彩',
      'HDRPeak 1300',
      '切换预设',
      '上次请求（非当前模式）',
      '本次运行尚未发送',
      'HDR 预设超出允许范围。',
      'HDR 预设切换请求未能发送。',
      'HDR 预设请求后显示路径或输出改变，请检查机身菜单。',
      'HDR 预设切换请求已发送，请以机身菜单为准。',
      'HDR 预设请使用专用切换命令。',
      '手动切换会暂停应用规则，不修改已保存配置。',
    ]) {
      expect(en.text(message), isNot(message), reason: message);
    }
  });
}
