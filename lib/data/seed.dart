import '../domain/calendar.dart';
import '../domain/models.dart';

/// Dados de desenvolvimento: o grupo inicial e as respostas do PRD.

const seedProfiles = [
  Profile(id: 'israel', name: 'Israel', emoji: '🦇', color: 0xFFFFC107),
  Profile(id: 'beto', name: 'Beto', emoji: '🐈', color: 0xFF4FC3F7),
  Profile(id: 'caio', name: 'Caio', emoji: '🏃', color: 0xFF81C784),
];

const seedQuickReplies = [
  // Comuns a todos.
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

  // Israel.
  QuickReply(
    id: 'israel-trabalho',
    ownerId: 'israel',
    emoji: '💼',
    label: 'No trabalho',
    kind: ReplyKind.no,
  ),
  QuickReply(
    id: 'israel-jogando',
    ownerId: 'israel',
    emoji: '🎮',
    label: 'Já tô jogando, entra aí',
    kind: ReplyKind.yes,
  ),

  // Beto.
  QuickReply(
    id: 'beto-namorada',
    ownerId: 'beto',
    emoji: '💑',
    label: 'Tô na casa da namorada',
    kind: ReplyKind.later,
    asksEta: true,
  ),
  QuickReply(
    id: 'beto-gatos',
    ownerId: 'beto',
    emoji: '🐈',
    label: 'Passeando com os gatos',
    kind: ReplyKind.later,
    asksEta: true,
  ),
  QuickReply(
    id: 'beto-jantando',
    ownerId: 'beto',
    emoji: '🍝',
    label: 'Tô jantando',
    kind: ReplyKind.later,
    asksEta: true,
  ),

  // Caio.
  QuickReply(
    id: 'caio-fora',
    ownerId: 'caio',
    emoji: '🚶',
    label: 'Não tô em casa',
    kind: ReplyKind.later,
    asksEta: true,
  ),
  QuickReply(
    id: 'caio-ocupado',
    ownerId: 'caio',
    emoji: '📵',
    label: 'Ocupado',
    kind: ReplyKind.no,
  ),
  QuickReply(
    id: 'caio-sair',
    ownerId: 'caio',
    emoji: '🚪',
    label: 'Tenho que sair',
    kind: ReplyKind.no,
  ),
];

const seedConversations = [
  Conversation(
    id: 'grupo',
    kind: ConversationKind.group,
    name: 'Os 3',
    memberIds: ['israel', 'beto', 'caio'],
  ),
  Conversation(
    id: 'israel-beto',
    kind: ConversationKind.direct,
    memberIds: ['israel', 'beto'],
  ),
  Conversation(
    id: 'israel-caio',
    kind: ConversationKind.direct,
    memberIds: ['israel', 'caio'],
  ),
  Conversation(
    id: 'beto-caio',
    kind: ConversationKind.direct,
    memberIds: ['beto', 'caio'],
  ),
];

/// Horários livres de exemplo, só para o calendário não nascer vazio.
const seedAvailability = [
  // Israel: noites depois do trabalho e sábado à tarde.
  Availability(
    id: 'av-1',
    userId: 'israel',
    weekday: 1,
    range: TimeRange(19 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-2',
    userId: 'israel',
    weekday: 3,
    range: TimeRange(19 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-3',
    userId: 'israel',
    weekday: 4,
    range: TimeRange(19 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-4',
    userId: 'israel',
    weekday: 6,
    range: TimeRange(14 * 60, 24 * 60),
  ),
  // Beto: só mais tarde.
  Availability(
    id: 'av-5',
    userId: 'beto',
    weekday: 3,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-6',
    userId: 'beto',
    weekday: 4,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  Availability(
    id: 'av-7',
    userId: 'beto',
    weekday: 6,
    range: TimeRange(16 * 60, 20 * 60),
  ),
  Availability(
    id: 'av-8',
    userId: 'beto',
    weekday: 6,
    range: TimeRange(21 * 60, 24 * 60),
  ),
  // Caio: quase nunca em casa durante a semana.
  Availability(
    id: 'av-9',
    userId: 'caio',
    weekday: 4,
    range: TimeRange(20 * 60, 23 * 60),
  ),
  Availability(
    id: 'av-10',
    userId: 'caio',
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
