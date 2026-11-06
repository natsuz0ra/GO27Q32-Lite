import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:go27q32_lite/core/control.dart';

class FakeTransport implements ControlTransport {
  FakeTransport() {
    final raw = File(
      'test/fixtures/init.json',
    ).readAsStringSync().replaceFirst('\uFEFF', '');
    data = (jsonDecode(raw) as Json)['result'] as Json;
    data['settings']['Language'] ??= 'zh';
    data['hdrPresets'] = [
      for (final (value, name) in [
        'HDR显示',
        'HDR游戏',
        'HDR电影',
        'HDR亮彩',
        'HDRPeak 1300',
      ].indexed)
        {'Value': value, 'Name': name},
    ];
  }
  late Json data;
  final calls = <String>[];
  Completer<dynamic>? heldTick, heldSet, heldHdrPreset;
  bool rejectSet = false;
  Json get state => data['state'] as Json;
  @override
  Future<dynamic> call(String method, [Json? args]) async {
    calls.add(method);
    if (method == 'init') return copyJson(data);
    if (method == 'tick' && heldTick != null) return heldTick!.future;
    if (method == 'set') {
      if (heldSet != null) return heldSet!.future;
      if (rejectSet) throw StateError('写入失败');
      (state['values'] as Json)[args!['feature']]['Value'] = args['value'];
      final f = (data['features'] as List).cast<Json>().firstWhere(
        (f) => f['Id'] == args['feature'],
      );
      if (f['DeviceSetting'] != true) state['canUndo'] = true;
    }
    if (method == 'hdr') {
      state['automatic'] = false;
      state['hdrPresetRequest'] = null;
      state['hdr']['Enabled'] = args!['enabled'];
      state['hdr']['ActiveHdr'] = args['enabled'];
      final values = state['values'] as Json;
      if (args['enabled'] == true) {
        values.removeWhere((key, _) => sdrPicture(key));
      } else {
        for (final f in (data['features'] as List).cast<Json>().where(
          (f) => sdrPicture(f['Id'] as String),
        )) {
          values[f['Id']] = {
            'Value': f['Id'] == 'gamma'
                ? 3
                : f['Choices'] == null
                ? 50.clamp(0, f['Max'] as int)
                : 0,
            'Maximum': f['Max'],
          };
        }
      }
    }
    if (method == 'settings') {
      // Settings never persist a requested HDR preset as actual monitor state.
      data['settings'] = copyJson(args!);
      return copyJson(args);
    }
    if (method == 'automatic') state['automatic'] = args!['enabled'];
    if (method == 'hdrPreset') {
      if (heldHdrPreset != null) return heldHdrPreset!.future;
      state['automatic'] = false;
      if (rejectSet) throw StateError('HDR 预设切换请求未能发送。');
      state['hdrPresetRequest'] = {
        'Value': args!['value'],
        'MonitorId': state['monitorId'],
        'SentAt': DateTime.now().toIso8601String(),
      };
      state['dirty'] = true;
      state['canUndo'] = false;
      (state['values'] as Json).remove('pictureMode');
    }
    if (method == 'timer') {
      final mode = args!['mode'] as int;
      final packed = ((args['minutes'] as int) << 8) | (args['seconds'] as int);
      state['values']['gameTimer']['Value'] = mode;
      state['values']['timerDuration']['Value'] = mode != 2
          ? 0
          : packed == 0
          ? 1280
          : packed;
      state['values']['timerRunning']['Value'] = mode == 0 ? 0 : 1;
    }
    if (method == 'timerPause') {
      state['values']['timerRunning']['Value'] = args!['paused'] == true
          ? 0
          : 1;
    }
    if (method == 'processes') return <Json>[];
    return copyJson(state);
  }

  @override
  Future<void> close() async {}
}
