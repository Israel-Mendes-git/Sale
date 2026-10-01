/// Configuração de build, vinda de `--dart-define-from-file=config/sale.json`.
///
/// Sem ela o app roda com o backend em memória (testes e desenvolvimento).
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// Para onde o navegador volta depois do login. Precisa estar cadastrado
  /// em Authentication → URL Configuration → Redirect URLs, no Supabase, e
  /// casar com o `intent-filter` do `AndroidManifest.xml`.
  static const authRedirect = 'sale://login-callback';

  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
