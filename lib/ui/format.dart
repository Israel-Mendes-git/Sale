import '../data/repository.dart';
import '../domain/models.dart';

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String conversationTitle(SaleRepository repo, Conversation c, String viewerId) {
  if (c.kind == ConversationKind.group) return c.name ?? 'Grupo';
  final otherId = c.memberIds.firstWhere((id) => id != viewerId);
  return repo.profile(otherId).name;
}

String chamadoWhen(Chamado c) =>
    c.scheduledFor == null ? 'agora' : 'às ${hhmm(c.scheduledFor!)}';

String chamadoGame(Chamado c) {
  if (c.game != null) return c.drawn ? '🎲 ${c.game}' : c.game!;
  // Sorteio em que todas as opções foram vetadas.
  return c.drawn ? 'qualquer coisa (vetaram tudo)' : 'qualquer coisa';
}

String responseLabel(ChamadoResponse r) {
  final eta = r.eta;
  if (eta == null) return r.reply.label;
  return '${r.reply.label} · chega ~${hhmm(eta)}';
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
