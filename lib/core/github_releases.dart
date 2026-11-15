import 'dart:convert';

import 'package:http/http.dart' as http;

/// Repositório GitHub (owner/repo) extraído de uma URL de port.
class GithubRepo {
  const GithubRepo(this.owner, this.repo);

  final String owner;
  final String repo;

  @override
  String toString() => '$owner/$repo';
}

const Set<String> _reservedPaths = <String>{
  'releases',
  'tags',
  'tree',
  'blob',
  'issues',
  'pulls',
  'actions',
  'raw',
  'download',
  'archive',
  'sponsors',
};

/// Extrai owner/repo de uma URL do GitHub (ex.: github.com/owner/repo).
GithubRepo? githubRepoOf(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.host.toLowerCase().endsWith('github.com')) {
    return null;
  }
  final List<String> segments =
      uri.pathSegments.where((String part) => part.isNotEmpty).toList();
  if (segments.length < 2 || _reservedPaths.contains(segments[0])) {
    return null;
  }
  return GithubRepo(segments[0], segments[1]);
}

/// Um arquivo .apk anexado a uma release.
class ApkAsset {
  const ApkAsset({required this.name, required this.url, this.sizeBytes = 0});

  final String name;
  final String url;
  final int sizeBytes;
}

/// Uma release do GitHub com APKs anexados (tag + assets).
class GithubRelease {
  const GithubRelease({required this.tag, required this.assets});

  /// Etiqueta da release (ex.: `v1.2.0`).
  final String tag;

  /// APKs anexados à release.
  final List<ApkAsset> assets;
}

/// Busca a release mais recente que tenha anexos .apk, com a sua tag.
Future<GithubRelease?> fetchLatestApkRelease(GithubRepo repo) async {
  final Uri uri = Uri.parse(
    'https://api.github.com/repos/${repo.owner}/${repo.repo}/releases?per_page=20',
  );
  final http.Response response = await http.get(
    uri,
    headers: const <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'PORTIX',
    },
  );
  if (response.statusCode != 200) {
    throw Exception('github ${response.statusCode}');
  }
  final Object? body = jsonDecode(response.body);
  if (body is! List) {
    return null;
  }
  for (final Object? release in body) {
    if (release is! Map) {
      continue;
    }
    final Object? assets = release['assets'];
    if (assets is! List) {
      continue;
    }
    final List<ApkAsset> apks = <ApkAsset>[];
    for (final Object? asset in assets) {
      if (asset is! Map) {
        continue;
      }
      final String name = (asset['name'] ?? '').toString();
      final String url = (asset['browser_download_url'] ?? '').toString();
      final Object? size = asset['size'];
      if (url.isNotEmpty && name.toLowerCase().endsWith('.apk')) {
        apks.add(ApkAsset(
          name: name,
          url: url,
          sizeBytes: size is num ? size.toInt() : 0,
        ));
      }
    }
    if (apks.isNotEmpty) {
      return GithubRelease(
        tag: (release['tag_name'] ?? '').toString(),
        assets: apks,
      );
    }
  }
  return null;
}
