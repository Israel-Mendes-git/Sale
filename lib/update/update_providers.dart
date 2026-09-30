import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_service.dart';

final releaseSourceProvider = Provider<ReleaseSource>(
  (ref) => GitHubReleaseSource(),
);

/// Versão instalada ("1.1.0").
final installedVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Atualização disponível; nulo = está em dia. Reconsultar com
/// `ref.invalidate(availableUpdateProvider)`.
final availableUpdateProvider = FutureProvider<AppRelease?>((ref) async {
  final installed = await ref.watch(installedVersionProvider.future);
  return checkForUpdate(ref.watch(releaseSourceProvider), installed);
});

/// Versão que a pessoa mandou "depois" nesta sessão, para o aviso sumir.
final dismissedUpdateProvider = NotifierProvider<DismissedUpdate, String?>(
  DismissedUpdate.new,
);

class DismissedUpdate extends Notifier<String?> {
  @override
  String? build() => null;

  void dismiss(String version) => state = version;
}

/// O aviso de atualização está na tela?
final updateBannerVisibleProvider = Provider<bool>((ref) {
  final update = ref.watch(availableUpdateProvider).value;
  return update != null && ref.watch(dismissedUpdateProvider) != update.version;
});
