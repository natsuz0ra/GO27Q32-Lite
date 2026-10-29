import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/core/control.dart';
import 'support.dart';

void main() {
  late FakeTransport transport;
  late ControlModel m;
  setUp(() async {
    transport = FakeTransport();
    m = ControlModel(transport);
    await m.initialize(polling: false);
  });
  tearDown(() => m.dispose());
  test('Gamma and crosshair reflect the audited wire order', () {
    expect((m.feature('gamma')!['Choices'] as List).map((v) => v['Name']), [
      '关闭',
      '1.8',
      '2.0',
      '2.2',
      '2.4',
      '2.6',
    ]);
    expect(m.feature('crosshair')!['Code'], 0xEF);
    expect(
      (m.feature('crosshair')!['Choices'] as List).map((v) => v['Value']),
      [0, 1, 2, 3, 4],
    );
  });
  test('late polling cannot replace a staged slider value', () async {
    transport.heldTick = Completer<dynamic>();
    final polling = m.tick();
    m.stage('brightness', 72);
    final old = copyJson(m.state);
    old['values']['brightness']['Value'] = 10;
    transport.heldTick!.complete(old);
    await polling;
    expect(m.value('brightness'), 72);
    expect(m.confirmed('brightness'), 50);
  });
  test(
    'optimistic values remain visible until readback confirms the write',
    () async {
      m.stage('brightness', 72);
      transport.heldSet = Completer<dynamic>();
      final write = m.flush();
      expect(m.value('brightness'), 72);
      expect(m.confirmed('brightness'), 50);
      final result = copyJson(m.state);
      result['values']['brightness']['Value'] = 72;
      transport.heldSet!.complete(result);
      await write;
      expect(m.value('brightness'), 72);
      expect(m.pending, isEmpty);
      expect(m.inFlight, isEmpty);
    },
  );
  test(
    'failed write restores confirmed values and reports the error',
    () async {
      transport.rejectSet = true;
      m.stage('brightness', 72);
      await m.flush();
      expect(m.value('brightness'), 50);
      expect(m.error, contains('写入失败'));
    },
  );
  test('a poll with no material changes does not rebuild controls', () async {
    int count = 0;
    m.addListener(() => count++);
    await m.tick();
    expect(count, 0);
  });
  test('external OSD and Windows HDR changes are observed', () async {
    transport.state['values']['brightness']['Value'] = 61;
    transport.state['hdr']['Enabled'] = true;
    transport.state['hdr']['ActiveHdr'] = true;
    await m.tick();
    expect(m.value('brightness'), 61);
    expect(m.activeHdr, isTrue);
    expect(m.blocked('pictureMode'), contains('HDR 专用预设'));
  });
  test('dragging defers DDC writes and background reads', () async {
    m.beginDrag();
    m.stage('brightness', 75);
    await m.flush();
    await m.tick();
    expect(transport.calls, ['init']);
    m.endDrag();
    await m.flush();
    expect(m.confirmed('brightness'), 75);
  });
  test(
    'open selectors defer new polls and reject a snapshot that arrives mid-menu',
    () async {
      UiActivity.depth++;
      try {
        await m.tick();
        expect(transport.calls, ['init']);
      } finally {
        UiActivity.depth--;
      }
      transport.heldTick = Completer<dynamic>();
      final polling = m.tick();
      UiActivity.depth++;
      try {
        final next = copyJson(m.state);
        next['values']['brightness']['Value'] = 91;
        transport.heldTick!.complete(next);
        await polling;
        expect(m.value('brightness'), 50);
      } finally {
        UiActivity.depth--;
        transport.heldTick = null;
      }
      transport.state['values']['brightness']['Value'] = 91;
      await m.tick();
      expect(m.value('brightness'), 91);
    },
  );
  test('a newer slider request survives the first readback', () async {
    m.stage('brightness', 60);
    transport.heldSet = Completer<dynamic>();
    final write = m.flush();
    m.stage('brightness', 80);
    final result = copyJson(m.state);
    result['values']['brightness']['Value'] = 60;
    final hold = transport.heldSet!;
    transport.heldSet = null;
    hold.complete(result);
    await write;
    expect(m.value('brightness'), 80);
  });
  test('automatic, sRGB and ECO locks are enforced by the UI model', () {
    m.state['values']['pictureMode']['Value'] = 7;
    expect(m.blocked('gamma'), contains('sRGB'));
    m.state['values']['pictureMode']['Value'] = 9;
    expect(m.blocked('brightness'), contains('ECO'));
    m.state['automatic'] = true;
    expect(m.blocked('crosshair'), contains('应用规则'));
  });
  test('device preferences work independently of HDR and automation', () async {
    m.state['automatic'] = true;
    m.state['hdr'] = null;
    expect(m.blocked('joystickUp'), isNull);
    m.stage('joystickUp', 13);
    await m.flush();
    expect(m.confirmed('joystickUp'), 13);
    expect(m.state['canUndo'], isFalse);
    expect(m.label('joystickUp'), 'Ultra Clear');
    m.state['connected'] = false;
    expect(m.blocked('joystickUp'), contains('未连接'));
  });
  test(
    'external device preferences sync and unavailable ones stay disabled',
    () async {
      transport.state['values']['osdTimeout']['Value'] = 5;
      await m.tick();
      expect(m.label('osdTimeout'), '30 秒');
      (m.state['values'] as Json).remove('ledIndicator');
      expect(m.blocked('ledIndicator'), contains('无法读取'));
      m.stage('ledIndicator', 1);
      expect(m.pending, isEmpty);
    },
  );
}
