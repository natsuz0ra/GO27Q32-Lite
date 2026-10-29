import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/l10n.dart';

void main() {
  test('initial language uses Chinese only for Chinese system locales', () {
    for (final locale in ['zh-CN', 'zh_TW', 'ZH-HK']) {
      expect(initialLanguage(locale), 'zh');
    }
    for (final locale in ['en-US', 'ja-JP', 'fr-FR', '']) {
      expect(initialLanguage(locale), 'en');
    }
  });
  test('English uses the vendor terms and preserves user profile names', () {
    const en = AppLocalizations('en');
    expect(en.text('黑平衡'), 'Black eQualizer');
    expect(en.text('自然'), 'Natural');
    expect(en.text('过驱'), 'Overdrive');
    expect(en.text('电源指示灯'), 'LED Indicator');
    expect(en.text('仅待机时开启'), 'Standby On');
    expect(en.text('调节亮度'), 'Adjust Brightness');
    expect(en.text('已使用「画面模式」。'), 'Applied “画面模式”.');
    expect(
      en.text('Bad state: 参数超出允许范围。'),
      'The value is outside the allowed range.',
    );
    expect(const AppLocalizations('zh').text('设置'), '设置');
  });
}
