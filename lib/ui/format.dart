import '../data/repository.dart';
import '../domain/models.dart';

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String conversationTitle(SaleRepository repo, Conversation c, String viewerId) {
  if (c.kind == ConversationKind.group) return c.name ?? 'Grupo';
  final otherId = c.memberIds.firstWhere((id) => id != viewerId);
  return repo.profile(otherId).name;
}

/// Em uma linha, o que a mensagem diz: serve para a prévia na lista de
/// conversas e para a citação dentro da bolha.
String messageSummary(Message m) {
  if (m.isDeleted) return 'Mensagem apagada';
  final texto = m.text?.trim() ?? '';
  if (m.isChamado) return 'Chamado';
  if (m.isImage) return texto.isEmpty ? '📷 Foto' : '📷 $texto';
  return texto;
}

String chamadoWhen(Chamado c) =>
    c.scheduledFor == null ? 'agora' : 'às ${hhmm(c.scheduledFor!)}';

String chamadoGame(Chamado c) {
  if (c.game != null) return c.drawn ? '🎲 ${c.game}' : c.game!;
  // Sorteio em que todas as opções foram vetadas.
  return c.drawn ? 'qualquer coisa (vetaram tudo)' : 'qualquer coisa';
}

/// A resposta de [userId] no card: "Tô jantando · chega ~21:20" ou
/// "Me chama daqui a pouco · de novo às 21:20".
String responseLabel(Chamado chamado, String userId) {
  final response = chamado.responses[userId];
  if (response == null) return '';
  final label = response.reply.label;
  // A soneca não promete chegada: ela marca a volta do Chamado.
  final snooze = response.snoozedUntil;
  if (snooze != null) return '$label · de novo às ${hhmm(snooze)}';
  // O "chega ~" é de quem pediu um tempo; de quem vem na hora, a hora já
  // está no cabeçalho do Chamado.
  if (response.reply.kind != ReplyKind.later) return label;
  final promised = chamado.promisedBy(userId);
  return promised == null ? label : '$label · chega ~${hhmm(promised)}';
}

/// O aviso da insistência no card: vazio enquanto o Chamado não tocou de
/// novo.
String nudgeLabel(Chamado chamado) {
  final at = chamado.nudgedAt;
  return at == null
      ? ''
      : 'Tocou de novo às ${hhmm(at)}, para quem não respondeu';
}

/// Tempo curto, do jeito que se fala: "12 min", "1 h 05", "2 h".
String shortDuration(Duration d) {
  final minutes = d.inMinutes.abs();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h ${rest.toString().padLeft(2, '0')}';
}

/// O atraso em palavras. Menos de um minuto conta como na hora — o placar
/// não é cronômetro de prova.
String lateLabel(Duration late) {
  final minutes = late.inMinutes;
  if (minutes == 0) return 'na hora';
  return minutes > 0
      ? '${shortDuration(late)} atrasado'
      : '${shortDuration(late)} adiantado';
}

/// A chegada na linha de cada um: "chegou 21:05 · 7 min atrasado". Vazio
/// enquanto a pessoa não marca que chegou.
String arrivalLabel(Chamado chamado, String userId) {
  final at = chamado.responses[userId]?.arrivedAt;
  if (at == null) return '';
  final late = chamado.lateBy(userId);
  return late == null
      ? 'chegou ${hhmm(at)}'
      : 'chegou ${hhmm(at)} · ${lateLabel(late)}';
}

const weekdayShort = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const weekdayLong = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

/// Minutos desde a meia-noite → "21:00"; 1440 vira "24:00".
String minutesLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String ddmm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// "qui 02/10".
String dayLabel(DateTime d) => '${weekdayShort[d.weekday - 1]} ${ddmm(d)}';
