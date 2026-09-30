import '../domain/calendar.dart';
import '../domain/models.dart';

/// Dados de desenvolvimento. Nomes e respostas pessoais quem define é cada
/// pessoa, no app; aqui ficam só marcadores neutros.

const seedProfiles = [
  Profile(id: 'p1', name: 'Pessoa 1', emoji: '🎮', color: 0xFFFFC107),
  Profile(id: 'p2', name: 'Pessoa 2', emoji: '👾', color: 0xFF4FC3F7),
  Profile(id: 'p3', name: 'Pessoa 3', emoji: '🕹️', color: 0xFF81C784),
];

/// Respostas comuns a todos. As pessoais cada um cadastra no perfil.
const seedQuickReplies = [
  QuickReply(id: 'bora', emoji: '✅', label: 'Bora!', kind: ReplyKind.yes),
  QuickReply(
    id: 'chego10',
    emoji: '⏱️',
    label: 'Chego em 10 min',
    kind: ReplyKind.later,
    etaMinutes: 10,
  ),
  QuickReply(
    id: 'chego20',
    emoji: '⏱️',
    label: 'Chego em 20 min',
    kind: ReplyKind.later,
    etaMinutes: 20,
  ),
  QuickReply(
    id: 'chego30',
    emoji: '⏱️',
    label: 'Chego em 30 min',
    kind: ReplyKind.later,
    etaMinutes: 30,
  ),
  QuickReply(id: 'hojenao', emoji: '❌', label: 'Hoje não', kind: ReplyKind.no),
  QuickReply(
    id: 'soneca',
    emoji: '💤',
    label: 'Me chama daqui a pouco',
    kind: ReplyKind.snooze,
  ),
];

const seedConversations = [
  Conversation(
    id: 'grupo',
    kind: ConversationKind.group,
    name: 'Os 3',
    memberIds: ['p1', 'p2', 'p3'],
  ),
  Conversation(
    id: 'p1-p2',
    kind: ConversationKind.direct,
    memberIds: ['p1', 'p2'],
  ),
  Conversation(
    id: 'p1-p3',
    kind: ConversationKind.direct,
    memberIds: ['p1', 'p3'],
  ),
  Conversation(
    id: 'p2-p3',
    kind: ConversationKind.direct,
    memberIds: ['p2', 'p3'],
  ),
];

/// Horários livres de exemplo, só para o calendário não nascer vazio.
const seedAvailability = [
  // Pessoa 1: noites e sábado à tarde.
  Availability(
    id: 'av-1',
    userId: 'p1',
    weekday: 1,
    range: TimeRange(19 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-2',
    userId: 'p1',
    weekday: 3,
    range: TimeRange(19 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-3',
    userId: 'p1',
    weekday: 4,
    range: TimeRange(19 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-4',
    userId: 'p1',
    weekday: 6,
    range: TimeRange(14 * 60, 24 * 60),
  ),
  // Pessoa 2: só mais tarde.
  Availability(
    id: 'av-5',
    userId: 'p2',
    weekday: 3,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-6',
    userId: 'p2',
    weekday: 4,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-7',
    userId: 'p2',
    weekday: 6,
    range: TimeRange(16 * 60, 20 * 60),
  ),
  Availability(
    id: 'av-8',
    userId: 'p2',
    weekday: 6,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  // Pessoa 3: pouco livre durante a semana.
  Availability(
    id: 'av-9',
    userId: 'p3',
    weekday: 4,
    range: TimeRange(20 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-10',
    userId: 'p3',
    weekday: 6,
    range: TimeRange(15 * 60, 22 * 60),
  ),
];

/// Encontro fixo de exemplo: quinta, 21h.
const seedMeetings = [
  WeeklyMeeting(
    id: 'encontro-grupo',
    conversationId: 'grupo',
    weekday: 4,
    minute: 21 * 60,
  ),
];
