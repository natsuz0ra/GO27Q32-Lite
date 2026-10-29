import 'dart:math' as math;
import 'package:flutter/widgets.dart';

Rect trayBoundsForContent({
  required Size content,
  required Rect workArea,
  double frameHeight = 0,
}) {
  final width = math.min(368.0, workArea.width);
  final height = math.min(
    workArea.height,
    math.max(240.0, (content.height + frameHeight).ceilToDouble()),
  );
  return Rect.fromLTWH(
    workArea.right - width,
    workArea.bottom - height,
    width,
    height,
  );
}
