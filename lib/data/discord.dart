import 'dart:convert';

import 'package:http/http.dart' as http;

/// A ponte com o Discord, sem bot: o webhook de um canal para postar o
/// Chamado, e o widget público do servidor para saber quem está na call.
///
/// O widget precisa estar ligado no servidor (Configurações do servidor →
/// Widget → Ativar widget do servidor); é de lá também que sai o ID.

/// O formato do webhook de um canal, o mesmo que o banco confere.
final formatoDoWebhook = RegExp(
  r'^https://(discord|discordapp)\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$',
);

/// O formato do ID de um servidor.
final formatoDoServidor = RegExp(r'^[0-9]{5,25}$');

/// Quem está numa call do servidor, pelo JSON do widget: os nomes de quem tem
/// canal de voz, na ordem do widget.
List<String> quemEstaNaCall(Map<String, dynamic> widget) {
  final membros = (widget['members'] as List?) ?? const [];
  return [
    for (final m in membros.cast<Map<String, dynamic>>())
      if (m['channel_id'] != null)
        (m['username'] as String?) ?? (m['nick'] as String?) ?? '?',
  ];
}

/// Busca quem está na call agora. Widget desligado, servidor errado ou sem
/// rede dão lista vazia: a faixa simplesmente não aparece.
Future<List<String>> buscarQuemEstaNaCall(
  String servidor, {
  http.Client? cliente,
}) async {
  final c = cliente ?? http.Client();
  try {
    final resposta = await c
        .get(Uri.parse('https://discord.com/api/guilds/$servidor/widget.json'))
        .timeout(const Duration(seconds: 8));
    if (resposta.statusCode != 200) return const [];
    return quemEstaNaCall(jsonDecode(resposta.body) as Map<String, dynamic>);
  } catch (_) {
    return const [];
  } finally {
    if (cliente == null) c.close();
  }
}

/// Posta uma mensagem de teste no webhook, para quem acabou de colar a URL
/// saber se deu certo. Devolve se o Discord aceitou.
Future<bool> testarWebhook(String webhook, {http.Client? cliente}) async {
  final c = cliente ?? http.Client();
  try {
    final resposta = await c
        .post(
          Uri.parse(webhook),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'Sale?',
            'content':
                'O Sale? está ligado neste canal: os Chamados do grupo '
                'aparecem aqui.',
          }),
        )
        .timeout(const Duration(seconds: 8));
    return resposta.statusCode >= 200 && resposta.statusCode < 300;
  } catch (_) {
    return false;
  } finally {
    if (cliente == null) c.close();
  }
}
