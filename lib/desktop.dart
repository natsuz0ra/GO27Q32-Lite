import 'dart:io';
import 'package:flutter/services.dart';

class Desktop {
  static const channel = MethodChannel('go27q32/desktop');
  static bool get supported => Platform.isWindows;
  static Future<T?> call<T>(String method, [dynamic arguments]) async {
    if (!supported) return null;
    return channel.invokeMethod<T>(method, arguments);
  }
}
