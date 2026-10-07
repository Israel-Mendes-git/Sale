import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// O Discord do grupo, sem bot e sem postar nada: o widget público do
/// servidor diz quem está em cada call, quem está online e o que cada um está
/// jogando. O servidor do Sale? lê o mesmo widget a cada minuto para guardar
/// o tempo de call e avisar quando a call abre.
///
/// O widget precisa estar ligado no servidor (Configurações do servidor →
/// Widget → Ativar widget do servidor); é de lá também que sai o ID.

/// O formato do ID de um servidor, o mesmo que o banco confere.
final formatoDoServidor = RegExp(r'^[0-9]{5,25}$');

/// Alguém do servidor que aparece no widget: quem está online.
@immutable
class MembroDoDiscord {
  const MembroDoDiscord({
    required this.nome,
    this.status = 'online',
    this.jogo,
    this.canal,
    this.mudo = false,
    this.surdo = false,
    this.avatarUrl,
  });

  final String nome;

  /// online, idle (ausente) ou dnd (não perturbe).
  final String status;

  /// O jogo que o Discord diz que a pessoa está jogando.
  final String? jogo;

  /// O id do canal de voz em que a pessoa está; nulo = fora de call.
  final String? canal;

  /// Microfone desligado (por ela ou pelo servidor).
  final bool mudo;

  /// Som desligado (por ela ou pelo servidor).
  final bool surdo;
  final String? avatarUrl;

  bool get naCall => canal != null;
}

/// Uma call (canal de voz) com gente dentro.
@immutable
class CallDoDiscord {
  const CallDoDiscord({required this.nome, required this.membros});

  final String nome;
  final List<MembroDoDiscord> membros;
}

/// O que o widget do servidor mostra agora.
@immutable
class ServidorDoDiscord {
  const ServidorDoDiscord({
    required this.nome,
    required this.membros,
    this.canais = const {},
    this.convite,
  });

  final String nome;

  /// Quem está online, na ordem do widget.
  final List<MembroDoDiscord> membros;

  /// id -> nome dos canais de voz.
  final Map<String, String> canais;

  /// O convite do widget, que abre o servidor no Discord. Nulo quando o
  /// servidor não escolheu um canal de convite no widget.
  final String? convite;

  /// As calls com alguém dentro, na ordem dos canais.
  List<CallDoDiscord> get calls => [
    for (final e in canais.entries)
      if (membros.where((m) => m.canal == e.key).toList() case final dentro
          when dentro.isNotEmpty)
        CallDoDiscord(nome: e.value, membros: dentro),
  ];

  /// Todo mundo que está numa call, de qualquer canal.
  List<MembroDoDiscord> get naCall => [
    for (final m in membros)
      if (m.naCall) m,
  ];
}

/// Lê o JSON do widget. Membro sem nome fica de fora.
ServidorDoDiscord lerWidget(Map<String, dynamic> widget) {
  final canais = {
    for (final c in ((widget['channels'] as List?) ?? const []).cast<Map>())
      '${c['id']}': '${c['name']}',
  };
  final membros = [
    for (final m in ((widget['members'] as List?) ?? const []).cast<Map>())
      if (m['username'] case final String nome when nome.isNotEmpty)
        MembroDoDiscord(
          nome: nome,
          status: (m['status'] as String?) ?? 'online',
          jogo: (m['game'] as Map?)?['name'] as String?,
          canal: m['channel_id'] == null ? null : '${m['channel_id']}',
          mudo: m['mute'] == true || m['self_mute'] == true,
          surdo: m['deaf'] == true || m['self_deaf'] == true,
          avatarUrl: m['avatar_url'] as String?,
        ),
  ];
  return ServidorDoDiscord(
    nome: (widget['name'] as String?) ?? 'Discord',
    membros: membros,
    canais: canais,
    convite: widget['instant_invite'] as String?,
  );
}

/// Busca o widget agora. Widget desligado, servidor errado ou sem rede dão
/// nulo: o app simplesmente não mostra o Discord.
Future<ServidorDoDiscord?> buscarServidor(
  String servidor, {
  http.Client? cliente,
}) async {
  final c = cliente ?? http.Client();
  try {
    final resposta = await c
        .get(Uri.parse('https://discord.com/api/guilds/$servidor/widget.json'))
        .timeout(const Duration(seconds: 8));
    if (resposta.statusCode != 200) return null;
    return lerWidget(jsonDecode(resposta.body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    if (cliente == null) c.close();
  }
}

/// Quanto alguém ficou em call: o nome no Discord e, quando bate com alguém
/// do grupo ("Seu nome no Discord", no perfil), quem é.
@immutable
class TempoDeCall {
  const TempoDeCall({required this.nome, required this.minutos, this.userId});

  final String nome;
  final int minutos;
  final String? userId;
}

/// "45 min", "2 h", "2 h 15" — como no resumo da semana.
String duracaoEmTexto(int minutos) {
  if (minutos < 60) return '$minutos min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}
