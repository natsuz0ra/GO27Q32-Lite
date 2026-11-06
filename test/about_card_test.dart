import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go27q32_lite/about_card.dart';
import 'package:go27q32_lite/core/updates.dart';
import 'package:go27q32_lite/l10n.dart';
import 'package:go27q32_lite/theme.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      'about sections align and update feedback keeps licenses still in $language',
      (t) async {
        await t.binding.setSurfaceSize(const Size(360, 760));
        var quit = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: AboutCard(
                  onQuit: () => quit++,
                  updateChecker: UpdateChecker(
                    fetchRelease: () async => {
                      'tag_name': 'v1.0.0',
                      'html_url':
                          'https://github.com/natsuz0ra/GO27Q32-Lite/releases/tag/v1.0.0',
                      'draft': false,
                      'prerelease': false,
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final license = find.byKey(const ValueKey('about-licenses'));
        final licenseBefore = t.getRect(license);
        final licenseTitle = find.text(language == 'zh' ? '开源许可' : 'Licenses');
        final quitTitle = find.text(language == 'zh' ? '退出程序' : 'Quit');
        expect(t.getTopLeft(licenseTitle).dx, t.getTopLeft(quitTitle).dx);
        expect(
          find.text(
            language == 'zh'
                ? 'HarmonyOS Sans 字体与第三方组件'
                : 'HarmonyOS Sans and third-party components',
          ),
          findsOneWidget,
        );
        await t.tap(find.text(language == 'zh' ? '检查更新' : 'Check for Updates'));
        await t.pumpAndSettle();
        expect(t.getRect(license), licenseBefore);
        expect(
          find.text(language == 'zh' ? '已是最新版本' : 'You are up to date'),
          findsOneWidget,
        );
        await t.tap(quitTitle);
        expect(quit, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.binding.setSurfaceSize(null);
      },
    );
  }
}
