// Checks whether back-to-back DDC reads return stale values (a known DDC/CI framing issue).
// Run with: dart run tool/ddc_stability.dart
import 'dart:io';

import 'package:go27q32_lite/core/ddc.dart';

Future<void> main() async {
  final targets = Ddc.open();
  if (targets.isEmpty) {
    stdout.writeln('no monitor');
    exit(1);
  }
  final handle = targets.first.handle;
  const codes = [0x10, 0x12, 0xE6, 0xE7, 0xE8, 0xF1];
  for (final gap in [0, 60, 200]) {
    stdout.writeln('--- gap ${gap}ms ---');
    for (final code in codes) {
      final samples = <String>[];
      for (var i = 0; i < 4; i++) {
        final r = Ddc.read(handle, code);
        samples.add(r == null ? 'none' : '${r.current}/${r.maximum}');
        if (gap > 0) await Future<void>.delayed(Duration(milliseconds: gap));
      }
      final stable = samples.toSet().length == 1;
      stdout.writeln('0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}  ${samples.join('  ')}   ${stable ? 'stable' : 'FLAPPING'}');
    }
  }
}
