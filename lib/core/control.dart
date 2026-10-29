import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../l10n.dart';

typedef Json = Map<String, dynamic>;
Json copyJson(Json value) => jsonDecode(jsonEncode(value)) as Json;

/// Keep background snapshots out of short pointer/keyboard menu interactions.
class UiActivity {
  static int depth = 0;
  static bool get active => depth > 0;
}

abstract class ControlTransport {
  Future<dynamic> call(String method, [Json? args]);
  Future<void> close();
}

class HostTransport implements ControlTransport {
  HostTransport._(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final message = jsonDecode(line) as Json;
            final request = _requests.remove(message['id']);
            if (message['ok'] == true) {
              request?.complete(message['result']);
            } else {
              request?.completeError(
                StateError(message['error'] as String? ?? '控制服务返回错误'),
              );
            }
          } catch (e) {
            _fail(e);
          }
        }, onDone: () => _fail(StateError('控制服务已退出，请重新启动程序。')));
    process.stderr.transform(utf8.decoder).listen((s) {
      if (s.trim().isNotEmpty) lastError = s.trim();
    });
  }
  final Process process;
  int _id = 0;
  String lastError = '';
  final _requests = <int, Completer<dynamic>>{};
  static Future<HostTransport> start({bool demo = false}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前硬件后端支持 Windows；macOS 硬件支持尚未实现。');
    }
    final folder = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$folder/backend/GO27Q32.ControlHost.exe',
      '${Directory.current.path}/native/ControlHost/bin/Release/net9.0-windows/GO27Q32.ControlHost.exe',
    ];
    final path = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) {
      throw StateError('找不到 backend/GO27Q32.ControlHost.exe，请使用完整发行包。');
    }
    return HostTransport._(
      await Process.start(path, [
        if (demo) '--demo',
      ], mode: ProcessStartMode.normal),
    );
  }

  void _fail(Object error) {
    for (final c in _requests.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _requests.clear();
  }

  @override
  Future<dynamic> call(String method, [Json? args]) async {
    final id = ++_id;
    final c = Completer<dynamic>();
    _requests[id] = c;
    process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'args': args ?? {}}),
    );
    return c.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _requests.remove(id);
        throw TimeoutException('显示器响应超时，请检查连接。');
      },
    );
  }

  @override
  Future<void> close() async {
    try {
      await call('shutdown');
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 30));
    } catch (_) {
      process.kill();
    }
  }
}

class ControlModel extends ChangeNotifier {
  ControlModel(this.transport);
  final ControlTransport transport;
  Json state = {},
      settings = {
        'Profiles': <dynamic>[],
        'Rules': <dynamic>[],
        'DefaultProfiles': <String, dynamic>{},
        'Theme': 'system',
        'Language': initialLanguage(Platform.localeName),
        'LiveSync': true,
        'MinimizeToTray': true,
      };
  List<Json> features = [];
  final pending = <String, int>{}, inFlight = <String, int>{};
  Timer? _poll, _debounce;
  int _revision = 0;
  bool dragging = false;
  bool ready = false,
      busy = false,
      polling = false,
      demo = false,
      closed = false;
  String? error;
  bool get connected => state['connected'] == true;
  bool get automatic => state['automatic'] == true;
  bool get activeHdr => (state['hdr'] as Json?)?['ActiveHdr'] == true;
  bool get hdrEnabled => (state['hdr'] as Json?)?['Enabled'] == true;
  bool get stableHdr => state['hdr'] != null && activeHdr == hdrEnabled;
  String get monitorId => state['monitorId'] as String? ?? '';
  String get status => state['status'] as String? ?? '正在启动控制服务…';
  List<Json> get profiles => (settings['Profiles'] as List).cast<Json>();
  List<Json> get deviceProfiles =>
      profiles.where((p) => p['MonitorId'] == monitorId).toList();
  List<Json> get rules => (settings['Rules'] as List).cast<Json>();
  Json? get activeProfile =>
      profiles.where((p) => p['Id'] == state['activeProfile']).firstOrNull;
  Json? feature(String id) => features.where((f) => f['Id'] == id).firstOrNull;
  int? confirmed(String id) =>
      ((state['values'] as Json?)?[id] as Json?)?['Value'] as int?;
  int? value(String id) => pending[id] ?? inFlight[id] ?? confirmed(id);
  int maximum(String id) {
    final max = feature(id)?['Max'] as int? ?? 100;
    final reported =
        ((state['values'] as Json?)?[id] as Json?)?['Maximum'] as int? ?? max;
    return reported > 0 && reported < max ? reported : max;
  }

  String label(String id, [int? v]) {
    final locale = AppLocalizations(
      settings['Language'] as String? ?? initialLanguage(Platform.localeName),
    );
    v ??= value(id);
    if (v == null) return locale.text('未读取');
    final choices = feature(id)?['Choices'] as List?;
    if (choices != null) {
      return locale.text(
        choices.cast<Json>().where((c) => c['Value'] == v).firstOrNull?['Name']
                as String? ??
            '未知值 $v',
      );
    }
    return '$v${id == 'brightness' || id == 'contrast' || id == 'volume' ? '%' : ''}';
  }

  String? blocked(String id, {bool ignoreManagement = false}) {
    if (!connected) return '显示器未连接';
    final deviceSetting = feature(id)?['DeviceSetting'] == true;
    if (!ignoreManagement && automatic && !deviceSetting) {
      return '由应用规则管理，请先暂停自动切换';
    }
    if (!ignoreManagement && busy && !inFlight.containsKey(id)) return '正在应用设置';
    if (deviceSetting) return value(id) == null ? '当前无法读取此设备设置' : null;
    if (!stableHdr) return 'HDR 状态未知或正在切换';
    if (activeHdr && id == 'pictureMode') return 'HDR 专用预设请通过显示器菜单切换';
    if (!activeHdr &&
        value('pictureMode') == 7 &&
        {
          'contrast',
          'sharpness',
          'blackEqualizer',
          'colorVibrance',
          'gamma',
          'colorTemperature',
          'lowBlueLight',
          'superResolution',
          'overdrive',
        }.contains(id)) {
      return 'sRGB 模式锁定此参数';
    }
    if (!activeHdr && value('pictureMode') == 9 && id == 'brightness') {
      return 'ECO 模式锁定亮度';
    }
    if (value(id) == null) return '当前模式无法读取此项';
    return null;
  }

  Future<void> initialize({bool polling = true}) async {
    try {
      final data = await transport.call('init') as Json;
      state = data['state'] as Json;
      settings = data['settings'] as Json;
      features = (data['features'] as List).cast<Json>();
      demo = data['demo'] == true;
      ready = true;
      if (polling) {
        _poll = Timer.periodic(
          const Duration(milliseconds: 1500),
          (_) => tick(),
        );
      }
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void stage(String id, int v) {
    if (blocked(id) != null) return;
    pending[id] = v;
    _revision++;
    error = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), flush);
    notifyListeners();
  }

  void beginDrag() {
    dragging = true;
    _debounce?.cancel();
  }

  void endDrag() {
    dragging = false;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), flush);
  }

  Future<void> flush() async {
    if (busy || closed || dragging || pending.isEmpty) return;
    final changes = Map<String, int>.from(pending);
    pending.clear();
    inFlight.addAll(changes);
    busy = true;
    _revision++;
    notifyListeners();
    try {
      for (final pair in changes.entries) {
        state =
            await transport.call('set', {
                  'feature': pair.key,
                  'value': pair.value,
                })
                as Json;
      }
    } catch (e) {
      error = '$e';
      await _recover();
    } finally {
      inFlight.clear();
      busy = false;
      notifyListeners();
      if (pending.isNotEmpty) await flush();
    }
  }

  Future<void> tick() async {
    if (!ready ||
        busy ||
        dragging ||
        UiActivity.active ||
        polling ||
        pending.isNotEmpty ||
        closed) {
      return;
    }
    polling = true;
    final revision = _revision;
    try {
      final next = await transport.call('tick') as Json;
      if (revision == _revision &&
          !busy &&
          !UiActivity.active &&
          pending.isEmpty &&
          !closed) {
        final old = Map.of(state)
              ..remove('updatedAt')
              ..remove('processCheckedAt'),
            comparable = Map.of(next)
              ..remove('updatedAt')
              ..remove('processCheckedAt');
        state = next;
        if (jsonEncode(old) != jsonEncode(comparable)) {
          notifyListeners();
        }
      }
    } catch (e) {
      if (error != '$e') {
        error = '$e';
        notifyListeners();
      }
    } finally {
      polling = false;
    }
  }

  Future<bool> command(String method, [Json? args]) async {
    if (busy || closed) return false;
    _debounce?.cancel();
    if (pending.isNotEmpty) await flush();
    busy = true;
    _revision++;
    error = null;
    notifyListeners();
    try {
      state = await transport.call(method, args) as Json;
      return true;
    } catch (e) {
      error = '$e';
      await _recover();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _recover() async {
    try {
      state = await transport.call('state') as Json;
    } catch (_) {}
  }

  Future<bool> saveSettings(Json edited) async {
    if (busy || closed) return false;
    if (pending.isNotEmpty) await flush();
    busy = true;
    _revision++;
    error = null;
    notifyListeners();
    try {
      settings = await transport.call('settings', edited) as Json;
      return true;
    } catch (e) {
      error = '$e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> preference(String key, dynamic v) async {
    final edited = copyJson(settings);
    edited[key] = v;
    await saveSettings(edited);
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<void> shutdown() async {
    closed = true;
    _poll?.cancel();
    _debounce?.cancel();
    await transport.close();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
