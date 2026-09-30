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

String chamadoGame(Chamado c) => c.game ?? 'qualquer coisa';

String responseLabel(ChamadoResponse r) {
  final eta = r.eta;
  if (eta == null) return '${r.reply.emoji} ${r.reply.label}';
  return '${r.reply.emoji} ${r.reply.label} · chega ~${hhmm(eta)}';
}
