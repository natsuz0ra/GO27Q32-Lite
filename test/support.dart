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
  }
  late Json data;
  final calls = <String>[];
  Completer<dynamic>? heldTick, heldSet;
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
      state['hdr']['Enabled'] = args!['enabled'];
      state['hdr']['ActiveHdr'] = args['enabled'];
    }
    if (method == 'settings') {
      data['settings'] = copyJson(args!);
      return copyJson(args);
    }
    if (method == 'automatic') state['automatic'] = args!['enabled'];
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
