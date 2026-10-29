import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../version.dart';

/// SemVer comparison; build metadata does not change release precedence.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion._(this.numbers, this.prerelease);
  final List<BigInt> numbers;
  final List<String> prerelease;

  static ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final pre = match[4]?.split('.') ?? <String>[];
    if (pre.any((s) => RegExp(r'^0\d+$').hasMatch(s))) return null;
    return ReleaseVersion._([
      for (var i = 1; i <= 3; i++) BigInt.parse(match[i]!),
    ], pre);
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = numbers[i].compareTo(other.numbers[i]);
      if (result != 0) return result;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty ? (other.prerelease.isEmpty ? 0 : 1) : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = BigInt.tryParse(prerelease[i]);
      final b = BigInt.tryParse(other.prerelease[i]);
      final result = a != null && b != null
          ? a.compareTo(b)
          : a != null
          ? -1
          : b != null
          ? 1
          : prerelease[i].compareTo(other.prerelease[i]);
      if (result != 0) return result;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}

class UpdateResult {
  const UpdateResult(this.version, this.url, this.hasUpdate);
  final String version;
  final Uri url;
  final bool hasUpdate;
}

class UpdateChecker {
  UpdateChecker({this.currentVersion = appVersion, this.fetchRelease});
  final String currentVersion;
  final Future<Map<String, dynamic>> Function()? fetchRelease;

  Future<UpdateResult> check() async {
    final release = await (fetchRelease?.call() ?? _fetch());
    final tag = release['tag_name'];
    final local = ReleaseVersion.parse(currentVersion);
    final remote = tag is String ? ReleaseVersion.parse(tag) : null;
    final url = Uri.tryParse(release['html_url'] as String? ?? '');
    final base = Uri.parse(projectUrl);
    if (local == null ||
        remote == null ||
        release['draft'] != false ||
        release['prerelease'] != false ||
        remote.prerelease.isNotEmpty ||
        url == null ||
        url.scheme != 'https' ||
        url.host != base.host ||
        url.hasPort ||
        url.userInfo.isNotEmpty ||
        !url.path.startsWith('${base.path}/releases/tag/') ||
        url.query.isNotEmpty ||
        url.fragment.isNotEmpty) {
      throw const FormatException('更新信息无效，请到 GitHub Release 查看。');
    }
    return UpdateResult(tag as String, url, remote.compareTo(local) > 0);
  }

  Future<Map<String, dynamic>> _fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.https(
            'api.github.com',
            '/repos/natsuz0ra/GO27Q32-Lite/releases/latest',
          ),
        );
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'GO27Q32-Lite/$currentVersion',
        );
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('GitHub HTTP ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const FormatException('更新信息无效，请到 GitHub Release 查看。');
          }
          bytes.addAll(chunk);
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}
