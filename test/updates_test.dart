import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go27q32_lite/core/updates.dart';
import 'package:go27q32_lite/update_card.dart';

Map<String, dynamic> release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://github.com/natsuz0ra/GO27Q32-Lite/releases/tag/$tag',
  'draft': false,
  'prerelease': false,
};

void main() {
  test(
    'only strictly newer stable versions prompt; metadata is ignored',
    () async {
      for (final (remote, expected) in [
        ('v1.0.0', false),
        ('v0.9.9', false),
        ('v1.0.0+999', false),
        ('v1.0.1', true),
        ('v1.1.0', true),
        ('v2.0.0', true),
      ]) {
        final result = await UpdateChecker(
          currentVersion: '1.0.0+18',
          fetchRelease: () async => release(remote),
        ).check();
        expect(result.hasUpdate, expected, reason: remote);
      }
      final checker = UpdateChecker(
        currentVersion: '1.9.0',
        fetchRelease: () async => release('v1.10.0'),
      );
      expect((await checker.check()).hasUpdate, true);
    },
  );

  test('SemVer handles prerelease ordering and rejects malformed versions', () {
    final ordered = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
    ];
    for (var i = 1; i < ordered.length; i++) {
      expect(
        ReleaseVersion.parse(
          ordered[i],
        )!.compareTo(ReleaseVersion.parse(ordered[i - 1])!),
        greaterThan(0),
      );
    }
    for (final invalid in [
      '1.0',
      '01.0.0',
      '1.0.0-alpha.01',
      '1.0.0-',
      'latest',
    ]) {
      expect(ReleaseVersion.parse(invalid), isNull);
    }
  });

  test(
    'rejects drafts, prereleases and release links outside the project',
    () async {
      for (final data in [
        {...release('v1.1.0'), 'draft': true},
        {...release('v1.1.0'), 'prerelease': true},
        release('v1.1.0-beta'),
        {...release('v1.1.0'), 'html_url': 'https://example.com/file.exe'},
        {
          ...release('v1.1.0'),
          'html_url':
              'https://github.com.evil.test/natsuz0ra/GO27Q32-Lite/releases/tag/v1.1.0',
        },
        release('latest'),
      ]) {
        await expectLater(
          UpdateChecker(fetchRelease: () async => data).check(),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets('manual check never prompts for same or lower releases', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateControls(
            checker: UpdateChecker(
              fetchRelease: () async {
                requests++;
                return release('v1.0.0');
              },
            ),
          ),
        ),
      ),
    );
    expect(requests, 0);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.text('打开下载页'), findsNothing);
  });

  testWidgets('network errors offer retry without claiming a new version', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateControls(
            checker: UpdateChecker(
              fetchRelease: () async => throw Exception('offline'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('打开下载页'), findsOneWidget);
    expect(find.textContaining('发现新版本'), findsNothing);
  });
}
