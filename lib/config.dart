/// Configuração de build, vinda de `--dart-define-from-file=config/sale.json`.
///
/// Sem ela o app roda com o backend em memória (testes e desenvolvimento).
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
