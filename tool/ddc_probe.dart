// Standalone probe: proves the Dart FFI path reaches the monitor without any C# helper.
// Run with: dart run tool/ddc_probe.dart
import 'dart:io';

import 'package:go27q32_lite/core/ddc.dart';

void main() {
  if (!Ddc.isSupported) {
    stdout.writeln('windows only');
    exit(1);
  }
  final targets = Ddc.open();
  stdout.writeln('monitors found: ${targets.length}');
  if (targets.isEmpty) exit(1);
  for (final target in targets) {
    stdout.writeln('handle=0x${target.handle.toRadixString(16)}  "${target.description}"');
  }
  final first = targets.first;
  const codes = {
    0x10: 'brightness',
    0x12: 'contrast',
    0x14: 'color preset',
    0xE6: 'candidate A',
    0xE7: 'picture mode',
    0xE8: 'vibrance',
    0xF1: 'candidate B',
    0xF2: 'candidate C',
    0xF3: 'candidate D',
  };
  var answered = 0;
  for (final entry in codes.entries) {
    final reading = Ddc.read(first.handle, entry.key);
    if (reading == null) {
      stdout.writeln('0x${entry.key.toRadixString(16).toUpperCase().padLeft(2, '0')}  ${entry.value.padRight(16)} no answer');
      continue;
    }
    answered++;
    stdout.writeln('${reading.toString().padRight(24)} ${entry.value}');
  }
  stdout.writeln('answered=$answered/${codes.length}');
}
