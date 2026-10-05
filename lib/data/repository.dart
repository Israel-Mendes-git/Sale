import 'package:flutter/foundation.dart';

import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/sounds.dart';

const maxNameLength = 24;
const maxReplyLength = 40;
const maxGroupNameLength = 40;
const maxSoundNameLength = 24;

/// Som do grupo é toque de celular, não música: dois megabytes bastam, e é
/// também o limite do bucket no Supabase.
const maxSoundBytes = 2 * 1024 * 1024;

/// Imagem de celular passa fácil disso depois de comprimida, e é também o
/// limite do bucket no Supabase.
const maxImageBytes = 10 * 1024 * 1024;

/// Legenda é legenda, não crônica: o resto vai como mensagem.
const maxCaptionLength = 200;

/// Recado de voz não é podcast: cinco minutos de teto na gravação.
const maxAudioSeconds = 5 * 60;

/// O arquivo do recado cabe folgado nisso (voz comprimida é ~1 MB/min), e é
/// também o limite do bucket "anexos" no Supabase.
const maxAudioBytes = 10 * 1024 * 1024;

/// Tudo o que as telas precisam do backend.
///
/// Duas implementações: [MemoryRepository], para desenvolver as telas sem
/// servidor, e `SupabaseRepository`, usada quando o APK sai com a
/// configuração do Supabase.
abstract interface class SaleRepository {
  List<Profile> get profiles;
  Profile profile(String id);

  /// Respostas comuns a todos mais as próprias de [userId].
  List<QuickReply> quickRepliesFor(String userId);

  /// Grupos de que a pessoa participa. Enquanto estiver vazia, o app pede
  /// para criar um grupo ou entrar com um código de convite.
  Stream<List<Group>> watchGroups(String userId);

  /// Cria o grupo (com a conversa do grupo) e entra nele.
  Future<void> createGroup(String name);

  /// Entra num grupo pelo código de convite.
  Future<void> joinGroup(String inviteCode);

  Stream<List<Conversation>> watchConversations(String userId);
  Stream<List<Message>> watchMessages(String conversationId);
  Stream<Chamado> watchChamado(String chamadoId);

  /// Chamados abertos que ainda esperam resposta de [userId].
  Stream<List<Chamado>> watchPendingFor(String userId);

  /// [replyTo] cita outra mensagem da mesma conversa.
  Future<void> sendText({
    required String conversationId,
    required String authorId,
    required String text,
    String? replyTo,
  });

  /// Manda uma imagem na conversa, com legenda se houver. [bytes] é o arquivo
  /// que a pessoa escolheu no celular; [width] e [height] são o tamanho dele,
  /// que a bolha usa para nascer na proporção certa.
  Future<void> sendImage({
    required String conversationId,
    required String authorId,
    required Uint8List bytes,
    required String fileName,
    int? width,
    int? height,
    String? caption,
    String? replyTo,
  });

  /// Manda um recado de voz na conversa. [bytes] é o arquivo gravado e
  /// [duration] é a duração em segundos, que a bolha mostra antes de baixar.
  Future<void> sendAudio({
    required String conversationId,
    required String authorId,
    required Uint8List bytes,
    required String fileName,
    required int duration,
    String? replyTo,
  });

  /// Reage a uma mensagem, ou troca a reação que já estava lá. [emoji] nulo
  /// tira a reação de [userId] — é o que acontece ao tocar de novo na mesma.
  Future<void> react({
    required String messageId,
    required String userId,
    required String? emoji,
  });

  /// Quem do grupo de [userId] está com o app aberto agora, por id.
  Stream<Set<String>> watchOnline(String userId);

  /// Este aparelho com o app na frente ([present]) ou já não. Quem fecha o app
  /// some do "online" sozinho, mesmo sem avisar: a presença cai com a conexão.
  Future<void> setPresent({required String userId, required bool present});

  /// Quem está digitando ou gravando em [conversationId], por id. Vale
  /// enquanto alguém escuta, que é a conversa aberta na tela.
  Stream<Map<String, ChatActivity>> watchActivity(String conversationId);

  /// Conta o que [userId] está fazendo na conversa; nulo = parou.
  Future<void> setActivity({
    required String conversationId,
    required String userId,
    ChatActivity? activity,
  });

  /// Troca o texto de uma mensagem própria e a marca como editada. Só o autor
  /// edita, e só mensagem de gente (card de Chamado não).
  Future<void> editMessage({
    required String messageId,
    required String userId,
    required String text,
  });

  /// Apaga uma mensagem própria: ela vira uma lápide, sem texto, anexo nem
  /// reações, e some da citação de quem a respondeu. Só o autor apaga.
  Future<void> deleteMessage({
    required String messageId,
    required String userId,
  });

  /// O arquivo de um anexo ([Attachment.path]), para a tela mostrá-lo. Cada
  /// aparelho baixa uma vez: da segunda em diante sai do próprio aparelho.
  Future<Uint8List> attachmentBytes(String path);

  /// Marca que as mensagens que já estavam no servidor chegaram neste
  /// aparelho, em todas as conversas de [userId]. O app chama quando abre e
  /// quando volta do segundo plano: texto não manda push, então a mensagem
  /// chega quando o app está aberto, e é esse instante que vale.
  Future<void> markDelivered(String userId);

  /// Marca que [userId] abriu a conversa e viu as mensagens até agora. Quem
  /// viu também recebeu.
  Future<void> markRead({
    required String conversationId,
    required String userId,
  });

  Future<Chamado> sendChamado({
    required String conversationId,
    required String authorId,
    required List<String> targetIds,
    String? soundId,
    String? gameId,
    bool drawGame = false,
    String? note,
    DateTime? scheduledFor,
  });

  /// Veta o jogo sorteado e sorteia outro entre os que sobraram.
  Future<void> vetoGame({required String chamadoId, required String userId});

  Future<void> respond({
    required String chamadoId,
    required String userId,
    required QuickReply reply,
    int? etaMinutes,
  });

  Future<void> closeChamado(String chamadoId);

  /// Marca que [userId] chegou agora. Só vale para quem prometeu vir e
  /// ainda não marcou; é o outro lado do "chego em X min" no placar.
  Future<void> markArrived({required String chamadoId, required String userId});

  /// Chamados em que [userId] prometeu vir e ainda não marcou "Cheguei".
  Stream<List<Chamado>> watchArrivalPending(String userId);

  /// Os Chamados que [userId] vê, dos mais recentes para trás, para o
  /// placar e as estatísticas. Vem limitado: o placar não precisa de tudo.
  Stream<List<Chamado>> watchHistory(String userId);

  // Perfil.

  /// Troca o nome exibido. Recusa nome vazio ou com mais de [maxNameLength].
  Future<void> renameProfile(String userId, String name);

  /// Cria uma resposta própria de [ownerId]. "Vou, mas depois" pergunta o
  /// tempo na hora de responder. [icon] é um nome de `replyIcons`.
  Future<QuickReply> addQuickReply({
    required String ownerId,
    required String icon,
    required String label,
    required ReplyKind kind,
  });

  /// O som que [userId] usa quando chama; nulo volta ao som da marca.
  Future<void> setProfileSound(String userId, String? soundId);

  /// Remove uma resposta própria; as comuns a todos não podem ser removidas.
  Future<void> removeQuickReply(String replyId);

  // Jogos.

  Stream<GameLibrary> watchGames();

  /// Adiciona um jogo, já marcado como de [addedBy].
  Future<Game> addGame({
    required String name,
    required int minPlayers,
    required int maxPlayers,
    required String addedBy,
  });

  Future<void> setOwnsGame({
    required String gameId,
    required String userId,
    required bool owns,
  });

  Future<void> removeGame(String gameId);

  // Som do Chamado.

  /// Os sons que vêm no app mais os que o grupo subiu.
  Stream<List<Sound>> watchSounds();

  /// Sobe um som para o grupo, com o arquivo que a pessoa escolheu no
  /// aparelho. [fileName] serve para guardar a extensão.
  Future<Sound> addSound({
    required String name,
    required String fileName,
    required Uint8List bytes,
  });

  /// Tira um som do grupo; os que vêm no app ninguém tira.
  Future<void> removeSound(String soundId);

  /// O arquivo de um som do grupo, para o aparelho guardar e tocar.
  Future<Uint8List> soundBytes(Sound sound);

  // Calendário.

  /// Encontros dos grupos de [userId], exceções, confirmações, a
  /// disponibilidade de todos e os Chamados agendados abertos em que
  /// [userId] chamou ou foi chamado.
  Stream<CalendarData> watchCalendar(String userId);

  /// Cria ou substitui o encontro fixo da conversa (um por grupo).
  Future<void> saveMeeting({
    required String conversationId,
    required int weekday,
    required int minute,
    String? game,
  });

  Future<void> deleteMeeting(String meetingId);

  /// Cria ou substitui a exceção daquela data.
  Future<void> setMeetingException(MeetingException exception);

  Future<void> clearMeetingException(String meetingId, DateTime date);

  /// Cria ou substitui a confirmação da pessoa naquela data.
  Future<void> setRsvp(Rsvp rsvp);

  Future<void> addAvailability({
    required String userId,
    required int weekday,
    required TimeRange range,
  });

  Future<void> removeAvailability(String availabilityId);

  // Push.

  /// Registra o aparelho para receber Chamado com o app fechado.
  Future<void> saveDeviceToken(String token);

  Future<void> removeDeviceToken(String token);
}
