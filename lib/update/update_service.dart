import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Repositório público de onde saem as versões do app.
const releasesRepo = 'Israel-Mendes-git/Sale';

@immutable
class AppRelease {
  const AppRelease({
    required this.version,
    required this.apkUrl,
    this.notes = '',
    this.sha256,
  });

  /// "1.2.0", sem o "v" da tag.
  final String version;
  final String apkUrl;
  final String notes;

  /// Conferido depois do download, quando o GitHub informa.
  final String? sha256;
}

/// De onde vem a informação da última versão publicada.
abstract interface class ReleaseSource {
  /// Nulo quando não há versão publicada.
  Future<AppRelease?> latest();
}

/// Última release do GitHub (`/releases/latest`), com o primeiro `.apk`.
class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource({http.Client? client, this.repo = releasesRepo})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String repo;

  @override
  Future<AppRelease?> latest() async {
    final res = await _client.get(
      Uri.https('api.github.com', '/repos/$repo/releases/latest'),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw UpdateCheckException('GitHub respondeu ${res.statusCode}');
    }
    return parseRelease(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

/// Converte o JSON de uma release do GitHub. Nulo se não houver APK.
AppRelease? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'] as String?;
  if (tag == null) return null;
  final assets = (json['assets'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final apk = assets
      .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
      .firstOrNull;
  if (apk == null) return null;

  final digest = apk['digest'] as String?;
  return AppRelease(
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    apkUrl: apk['browser_download_url'] as String,
    notes: (json['body'] as String? ?? '').trim(),
    sha256: digest != null && digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : null,
  );
}

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Compara versões "x.y.z" (o "+build" é ignorado). Negativo = [a] é menor.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// A release publicada, se for mais nova que a instalada.
Future<AppRelease?> checkForUpdate(
  ReleaseSource source,
  String installedVersion,
) async {
  final latest = await source.latest();
  if (latest == null) return null;
  return compareVersions(latest.version, installedVersion) > 0 ? latest : null;
}
