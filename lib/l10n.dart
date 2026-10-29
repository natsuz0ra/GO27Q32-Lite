import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'l10n/messages_en.dart';

String initialLanguage(String systemLanguage) =>
    systemLanguage.toLowerCase().startsWith('zh') ? 'zh' : 'en';

class AppLocalizations {
  const AppLocalizations(this.language);
  final String language;
  static const supportedLocales = [Locale('zh'), Locale('en')];
  static const delegate = _AppLocalizationsDelegate();
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations('zh');
  static final _templates = enMessages.entries
      .where((e) => RegExp(r'\{\d+\}').hasMatch(e.key))
      .map((e) {
        final parts = e.key.split(RegExp(r'\{\d+\}'));
        return (
          RegExp('^${parts.map(RegExp.escape).join('([\\s\\S]*?)')}\$'),
          e.value,
          const {
            '调节{0}',
            '{0}已写入并读回确认。',
            '{0}读取失败（0x{1}，错误 {2}）',
            '{0}写入失败',
            '{0}超出显示器报告的范围',
            '配置参数超出范围或不允许自动应用：{0}',
            '导入失败：{0}',
            '导出失败：{0}',
            '诊断失败：{0}',
          }.contains(e.key),
        );
      })
      .toList();
  String text(String message) {
    if (language != 'en') return message;
    if (enMessages[message] case final String exact) return exact;
    for (final prefix in ['Bad state: ', 'Exception: ']) {
      if (message.startsWith(prefix)) {
        return text(message.substring(prefix.length));
      }
    }
    for (final (pattern, translation, translateArguments) in _templates) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return translation.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
          final value = match.group(int.parse(m[1]!) + 1) ?? '';
          return translateArguments && value != message ? text(value) : value;
        });
      }
    }
    return message;
  }
}

String tr(BuildContext context, String message) =>
    AppLocalizations.of(context).text(message);

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale.languageCode));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Const-friendly localized UI copy. User-supplied names use Text directly.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
    this.translate = true,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;
  final bool translate;
  @override
  Widget build(BuildContext context) => Text(
    translate ? tr(context, data) : data,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

class LTooltip extends StatelessWidget {
  const LTooltip({
    super.key,
    required this.message,
    required this.child,
    this.verticalOffset,
  });
  final String message;
  final Widget child;
  final double? verticalOffset;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr(context, message),
    verticalOffset: verticalOffset,
    child: child,
  );
}

class LSelectableText extends StatelessWidget {
  const LSelectableText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) =>
      SelectableText(tr(context, data), style: style);
}
