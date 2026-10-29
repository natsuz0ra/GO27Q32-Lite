import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Minimal DDC/CI binding over dxva2.dll — no C# and no native helper process.
///
/// The monitor handle returned by `GetPhysicalMonitorsFromHMONITOR` on this machine can be
/// `0` while DDC still answers, so a null handle is not treated as "disconnected".
final class PhysicalMonitor extends Struct {
  external Pointer<Void> handle;

  @Array(128)
  external Array<Uint16> description;
}

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

typedef _EnumProcNative =
    Int32 Function(IntPtr, IntPtr, Pointer<_Rect>, IntPtr);
typedef _EnumMonitorsNative =
    Int32 Function(
      IntPtr,
      IntPtr,
      Pointer<NativeFunction<_EnumProcNative>>,
      IntPtr,
    );
typedef _EnumMonitorsDart =
    int Function(int, int, Pointer<NativeFunction<_EnumProcNative>>, int);

typedef _GetCountNative = Int32 Function(IntPtr, Pointer<Uint32>);
typedef _GetCountDart = int Function(int, Pointer<Uint32>);

typedef _GetMonitorsNative =
    Int32 Function(IntPtr, Uint32, Pointer<PhysicalMonitor>);
typedef _GetMonitorsDart = int Function(int, int, Pointer<PhysicalMonitor>);

typedef _GetVcpNative =
    Int32 Function(
      IntPtr,
      Uint8,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _GetVcpDart =
    int Function(int, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>);

typedef _SetVcpNative = Int32 Function(IntPtr, Uint8, Uint32);
typedef _SetVcpDart = int Function(int, int, int);

typedef _DestroyNative = Int32 Function(IntPtr);
typedef _DestroyDart = int Function(int);

class MonitorTarget {
  MonitorTarget(this.handle, this.description);
  final int handle;
  final String description;
}

class VcpReading {
  const VcpReading(this.code, this.current, this.maximum);
  final int code;
  final int current;
  final int maximum;

  @override
  String toString() =>
      '0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')} cur=$current max=$maximum';
}

class Ddc {
  Ddc._();

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _dxva2 = DynamicLibrary.open('dxva2.dll');

  static final _enumDisplayMonitors = _user32
      .lookupFunction<_EnumMonitorsNative, _EnumMonitorsDart>(
        'EnumDisplayMonitors',
      );
  static final _getCount = _dxva2
      .lookupFunction<_GetCountNative, _GetCountDart>(
        'GetNumberOfPhysicalMonitorsFromHMONITOR',
      );
  static final _getMonitors = _dxva2
      .lookupFunction<_GetMonitorsNative, _GetMonitorsDart>(
        'GetPhysicalMonitorsFromHMONITOR',
      );
  static final _getVcp = _dxva2.lookupFunction<_GetVcpNative, _GetVcpDart>(
    'GetVCPFeatureAndVCPFeatureReply',
  );
  static final _setVcp = _dxva2.lookupFunction<_SetVcpNative, _SetVcpDart>(
    'SetVCPFeature',
  );
  static final _destroy = _dxva2.lookupFunction<_DestroyNative, _DestroyDart>(
    'DestroyPhysicalMonitor',
  );

  /// Enumerates every physical monitor attached to an active desktop.
  static List<MonitorTarget> open() {
    final targets = <MonitorTarget>[];
    _sink = targets;
    // Pointer.fromFunction keeps the callback static, which is all EnumDisplayMonitors needs.
    final proc = Pointer.fromFunction<_EnumProcNative>(_enumProc, 0);
    try {
      _enumDisplayMonitors(0, 0, proc, 0);
    } finally {
      _sink = null;
    }
    return targets;
  }

  static List<MonitorTarget>? _sink;

  static int _enumProc(int hMonitor, int hdc, Pointer<_Rect> rect, int data) {
    final count = calloc<Uint32>();
    try {
      if (_getCount(hMonitor, count) == 0 || count.value == 0) return 1;
      final monitors = calloc<PhysicalMonitor>(count.value);
      try {
        if (_getMonitors(hMonitor, count.value, monitors) == 0) return 1;
        for (var i = 0; i < count.value; i++) {
          final entry = (monitors + i).ref;
          _sink?.add(
            MonitorTarget(
              entry.handle.address,
              _readDescription(entry.description),
            ),
          );
        }
      } finally {
        calloc.free(monitors);
      }
    } finally {
      calloc.free(count);
    }
    return 1;
  }

  /// Reads one VCP feature. Returns null when the monitor does not answer that code.
  static VcpReading? read(int handle, int code) {
    final type = calloc<Uint32>();
    final current = calloc<Uint32>();
    final maximum = calloc<Uint32>();
    try {
      final ok = _getVcp(handle, code, type, current, maximum);
      if (ok == 0) return null;
      return VcpReading(code, current.value, maximum.value);
    } finally {
      calloc.free(type);
      calloc.free(current);
      calloc.free(maximum);
    }
  }

  static bool write(int handle, int code, int value) =>
      _setVcp(handle, code, value) != 0;

  /// PHYSICAL_MONITOR.szPhysicalMonitorDescription is a fixed 128-element UTF-16 buffer.
  static String _readDescription(Array<Uint16> chars) {
    final buffer = StringBuffer();
    for (var i = 0; i < 128; i++) {
      final code = chars[i];
      if (code == 0) break;
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  static void close(MonitorTarget target) => _destroy(target.handle);

  static bool get isSupported => Platform.isWindows;
}
