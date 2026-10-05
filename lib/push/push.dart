import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../config.dart';
import '../data/repository.dart';
import '../domain/sounds.dart';
import '../ui/format.dart';

/// O Chamado chegando com o app fechado.
///
/// O servidor manda só dados, sem título nem corpo (ver docs/PUSH.md): quem
/// monta a notificação é o app, porque ela precisa abrir em tela cheia, como
/// uma ligação, e isso o Android só deixa o próprio aplicativo fazer.
///
/// Sem `android/app/google-services.json` nada disso liga, e o app funciona
/// igual — só não toca com o app fechado.

/// Para abrir o Chamado a partir da notificação, de fora de qualquer tela.
final appNavigator = GlobalKey<NavigatorState>();

/// O que a notificação tocada pede para abrir. A tela de conversas escuta.
final chamadoTocado = ValueNotifier<String?>(null);

/// A conversa que a notificação tocada pede para abrir.
final conversaTocada = ValueNotifier<String?>(null);

/// A conversa que está aberta na tela agora, preenchida pela tela do chat.
/// Mensagem dela não vira aviso: quem está lendo não precisa ser avisado.
///
/// Com o app fechado isto é sempre nulo, e está certo: nenhuma conversa está
/// aberta.
final conversaAberta = ValueNotifier<String?>(null);

/// Os Chamados ficam juntos nas configurações do Android: um canal por som,
/// debaixo de um grupo só. É o Android que manda nisso — o som é propriedade
/// do canal, e canal criado não troca de som.
const _grupoDeCanais = AndroidNotificationChannelGroup(
  'chamados',
  'Chamados',
  description: 'Quando alguém te chama pra jogar.',
);

/// O canal de um som, pelo nome com que o Chamado o pede.
String idDoCanal(String chave) => 'chamado_$chave';

/// O canal de um dos sons que vêm no app.
AndroidNotificationChannel _canalDoApp(String chave) => _canalDoSom(
  chave: chave,
  nome: builtInSounds[chave]!,
  som: RawResourceAndroidNotificationSound(chave),
);

AndroidNotificationChannel _canalDoSom({
  required String chave,
  required String nome,
  required AndroidNotificationSound som,
}) => AndroidNotificationChannel(
  idDoCanal(chave),
  'Chamado · $nome',
  description: 'Chamado com o som $nome.',
  importance: Importance.max,
  groupId: _grupoDeCanais.id,
  sound: som,
  // Toca no volume de chamada, não no de aviso: é uma ligação, não um e-mail.
  audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
);

/// Mensagem de chat também não é uma ligação: canal próprio, som comum de
/// notificação e nada de tela cheia. Quem quiser pode calar as mensagens e
/// continuar ouvindo o Chamado.
const _canalMensagem = AndroidNotificationChannel(
  'mensagem',
  'Mensagens',
  description: 'Mensagens no chat do grupo.',
  importance: Importance.high,
);

/// Menção é mensagem com o nome da pessoa: canal próprio e mais alto, para
/// quem calou o grupo continuar sabendo quando é com ela.
const _canalMencao = AndroidNotificationChannel(
  'mencao',
  'Menções',
  description: 'Quando alguém te menciona no chat (@você ou @todos).',
  importance: Importance.max,
);

/// O lembrete do encontro não é uma ligação: canal próprio, de importância
/// normal, para quem quiser desligar um sem perder o outro.
const _canalLembrete = AndroidNotificationChannel(
  'lembrete',
  'Lembretes do encontro',
  description: 'Antes da hora do encontro fixo do grupo.',
  importance: Importance.defaultImportance,
);

/// As respostas que cabem na própria notificação do Chamado. O Android mostra
/// até três botões: ficam as três mais comuns, e o resto (outro tempo, soneca,
/// respostas próprias) continua a um toque, abrindo o app.
///
/// O id diz o tipo e o tempo da resposta comum ("responder:later:20"), e quem
/// trata o toque acha a resposta no servidor por eles.
const acoesDoChamado = [
  AndroidNotificationAction('responder:yes:', '✅ Bora!'),
  AndroidNotificationAction('responder:later:20', '⏱️ Chego em 20'),
  AndroidNotificationAction('responder:no:', '❌ Hoje não'),
];

/// O tipo e os minutos de uma ação de responder, ou nulo quando a ação não é
/// de responder.
({String tipo, int? minutos})? lerRespostaDaAcao(String? acao) {
  if (acao == null || !acao.startsWith('responder:')) return null;
  final partes = acao.split(':');
  if (partes.length != 3 || partes[1].isEmpty) return null;
  return (tipo: partes[1], minutos: int.tryParse(partes[2]));
}

final _notificacoes = FlutterLocalNotificationsPlugin();

/// Os canais são criados uma vez por isolate (o do app e o que o Android
/// acorda com o app fechado); criar de novo não muda nada e custa idas e
/// voltas à plataforma.
Future<void>? _preparando;

AndroidFlutterLocalNotificationsPlugin? get _android => _notificacoes
    .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();

/// Mensagem que chega com o app fechado: o Android acorda um isolate só para
/// isto, sem telas nem estado. Dá para montar a notificação e mais nada.
@pragma('vm:entry-point')
Future<void> _comOAppFechado(RemoteMessage mensagem) async {
  await Firebase.initializeApp();
  await _prepararNotificacoes();
  await _mostrar(mensagem);
}

/// Prepara uma vez, e tenta de novo se tiver falhado (sem plataforma na mão,
/// o que falhou agora pode dar certo na próxima notificação).
Future<void> _prepararNotificacoes() async {
  final rodando = _preparando;
  if (rodando != null) return rodando;
  final tentativa = _prepararCanais();
  _preparando = tentativa;
  try {
    await tentativa;
  } catch (_) {
    _preparando = null;
    rethrow;
  }
}

/// Toque na notificação — ou num botão dela — com o app de pé.
void _aoTocar(NotificationResponse resposta) {
  if (lerRespostaDaAcao(resposta.actionId) != null) {
    unawaited(_responderPelaNotificacao(resposta));
    return;
  }
  // O que abrir vem no payload, como "chamado:<id>" ou "conversa:<id>".
  final payload = resposta.payload ?? '';
  final corte = payload.indexOf(':');
  if (corte == -1) return;
  final tipo = payload.substring(0, corte);
  final id = payload.substring(corte + 1);
  if (id.isEmpty) return;
  if (tipo == 'conversa') conversaTocada.value = id;
  if (tipo == 'chamado') chamadoTocado.value = id;
}

/// Botão da notificação tocado com o app fechado: o Android acorda um isolate
/// só para isto, como no push.
@pragma('vm:entry-point')
Future<void> _aoTocarComOAppFechado(NotificationResponse resposta) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _responderPelaNotificacao(resposta);
}

/// Responde o Chamado pelo botão da notificação, sem abrir o app.
///
/// Sem rede ou com a sessão vencida, a notificação volta dizendo que não deu,
/// e tocar nela abre o Chamado para responder por lá: ninguém fica achando que
/// respondeu quando não respondeu.
Future<void> _responderPelaNotificacao(NotificationResponse resposta) async {
  final acao = lerRespostaDaAcao(resposta.actionId);
  final payload = resposta.payload ?? '';
  if (acao == null || !payload.startsWith('chamado:')) return;
  if (!AppConfig.hasBackend) return;
  final chamadoId = payload.substring('chamado:'.length);
  try {
    final db = await _servidor();
    if (db == null) return;
    var busca = db
        .from('quick_replies')
        .select('id')
        .isFilter('owner_id', null)
        .eq('kind', acao.tipo);
    final minutos = acao.minutos;
    busca = minutos == null
        ? busca.isFilter('eta_minutes', null)
        : busca.eq('eta_minutes', minutos);
    final linha = await busca
        .limit(1)
        .single()
        .timeout(const Duration(seconds: 8));
    await db
        .rpc(
          'respond_chamado',
          params: {'p_chamado': chamadoId, 'p_reply': linha['id']},
        )
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Não deu para responder pela notificação: $e');
    await _prepararNotificacoes();
    await _notificacoes.show(
      id: chamadoId.hashCode,
      title: 'Não deu para responder',
      body: 'Toque para abrir o Chamado e responder por lá.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canalMensagem.id,
          _canalMensagem.name,
          channelDescription: _canalMensagem.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'chamado:$chamadoId',
    );
  }
}

Future<void> _prepararCanais() async {
  await _notificacoes.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notificacao'),
    ),
    onDidReceiveNotificationResponse: _aoTocar,
    onDidReceiveBackgroundNotificationResponse: _aoTocarComOAppFechado,
  );
  await _android?.createNotificationChannelGroup(_grupoDeCanais);
  for (final chave in builtInSounds.keys) {
    await _android?.createNotificationChannel(_canalDoApp(chave));
  }
  // O canal de quando o Chamado tocava o som padrão do aparelho não serve
  // mais, e canal criado não muda de som: este sai, e quem toca são os novos.
  await _android?.deleteNotificationChannel(channelId: 'chamado');
  await _android?.createNotificationChannel(_canalLembrete);
  await _android?.createNotificationChannel(_canalMensagem);
  await _android?.createNotificationChannel(_canalMencao);
}

/// Cria o canal de um som que o grupo subiu e que este aparelho já baixou.
/// [uri] é o endereço do arquivo registrado no aparelho.
///
/// Som que o aparelho ainda não baixou não tem canal, e o Chamado dele toca o
/// som da marca — até o app abrir, baixar e criar o canal.
Future<void> criarCanalDoSom({
  required String chave,
  required String nome,
  required String uri,
}) async {
  await _prepararNotificacoes();
  await _android?.createNotificationChannel(
    _canalDoSom(
      chave: chave,
      nome: nome,
      som: UriAndroidNotificationSound(uri),
    ),
  );
}

/// Tira o canal de um som que saiu da lista do grupo: sem isto ele ficaria
/// para sempre nas configurações do aparelho, com nome de som que não existe.
Future<void> apagarCanalDoSom(String chave) async {
  await _prepararNotificacoes();
  await _android?.deleteNotificationChannel(channelId: idDoCanal(chave));
}

/// O canal com o som que o Chamado pediu.
///
/// Som que vem no app tem canal desde a instalação. Som do grupo só tem canal
/// onde o arquivo já foi baixado; onde não foi, toca o da marca em vez de
/// chegar calado.
Future<AndroidNotificationChannel> _canalDoChamado(String pedido) async {
  final chave = pedido.isEmpty ? defaultSoundKey : pedido;
  if (builtInSounds.containsKey(chave)) return _canalDoApp(chave);

  final canais = await _android?.getNotificationChannels() ?? const [];
  final id = idDoCanal(chave);
  return canais.where((c) => c.id == id).firstOrNull ??
      _canalDoApp(defaultSoundKey);
}

Future<void> _mostrar(RemoteMessage mensagem) async {
  final dados = mensagem.data;
  if (dados['tipo'] == 'lembrete') return _mostrarLembrete(dados);
  if (dados['tipo'] == 'mensagem') return _mostrarMensagem(dados);

  final chamadoId = dados['chamadoId'] as String?;
  if (chamadoId == null) return;

  final autor = dados['autor'] as String? ?? 'Alguém';
  // O encontro fixo não tem ninguém chamando: é a hora que chegou.
  final automatico = (dados['automatico'] as String? ?? '').isNotEmpty;
  final jogo = (dados['jogo'] as String? ?? '').trim();
  final nota = (dados['nota'] as String? ?? '').trim();
  final detalhe = [
    if (jogo.isNotEmpty) jogo,
    if (nota.isNotEmpty) '"$nota"',
  ].join(' · ');

  // Por que está tocando: a soneca que a pessoa pediu, a insistência de um
  // Chamado sem resposta ou um Chamado novo.
  final titulo = switch (dados['motivo'] as String? ?? '') {
    'soneca' => 'Você pediu pra ser chamado de novo',
    'insistencia' when automatico => 'O grupo ainda está esperando',
    'insistencia' => '$autor ainda está esperando',
    _ when automatico => 'Hora do encontro do grupo',
    _ => '$autor te chamou pra jogar',
  };

  final canal = await _canalDoChamado(dados['som'] as String? ?? '');

  await _notificacoes.show(
    id: chamadoId.hashCode,
    title: titulo,
    body: detalhe.isEmpty ? 'Toque para responder' : detalhe,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        canal.id,
        canal.name,
        channelDescription: canal.description,
        importance: Importance.max,
        priority: Priority.max,
        // Como uma ligação: abre por cima da tela bloqueada.
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        ticker: 'Chamado',
        // Responder sem abrir o app: o resto das respostas fica a um toque.
        actions: acoesDoChamado,
      ),
    ),
    payload: 'chamado:$chamadoId',
  );
}

/// Mensagem do chat chegando: um aviso por conversa, com as mensagens novas
/// empilhadas, como num aplicativo de conversa.
///
/// Quem está com a conversa aberta não é avisado. O resto do grupo vê quem
/// escreveu e o que escreveu, e tocando no aviso cai dentro da conversa.
Future<void> _mostrarMensagem(Map<String, dynamic> dados) async {
  final conversaId = dados['conversaId'] as String?;
  final texto = (dados['texto'] as String? ?? '').trim();
  if (conversaId == null || texto.isEmpty) return;
  if (conversaAberta.value == conversaId) return;

  final autor = dados['autor'] as String? ?? 'Alguém';

  // Menção não se empilha com o resto: é um aviso só dela, mais alto.
  if ((dados['mencao'] as String? ?? '').isNotEmpty) {
    final mensagemId = dados['mensagemId'] as String? ?? conversaId;
    await _notificacoes.show(
      id: 'mencao:$mensagemId'.hashCode,
      title: '$autor te mencionou',
      body: texto,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canalMencao.id,
          _canalMencao.name,
          channelDescription: _canalMencao.description,
          importance: Importance.max,
          priority: Priority.max,
          styleInformation: BigTextStyleInformation(texto),
        ),
      ),
      payload: 'conversa:$conversaId',
    );
    await _marcarEntregue();
    return;
  }

  // Um aviso por conversa: o novo toma o lugar do antigo, acumulando as
  // mensagens em vez de empilhar avisos.
  final id = 'conversa:$conversaId'.hashCode;

  // O que já estava no aviso continua nele: assim a pessoa lê o fio da
  // conversa sem abrir o app.
  final anterior = await _android?.getActiveNotificationMessagingStyle(id: id);
  final estilo = MessagingStyleInformation(
    const Person(name: 'Você'),
    groupConversation: true,
    messages: [
      ...?anterior?.messages,
      Message(texto, DateTime.now(), Person(name: autor)),
    ],
  );

  await _notificacoes.show(
    id: id,
    title: autor,
    body: texto,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _canalMensagem.id,
        _canalMensagem.name,
        channelDescription: _canalMensagem.description,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: estilo,
      ),
    ),
    payload: 'conversa:$conversaId',
  );

  // Chegou no aparelho: é isso que o segundo tique conta a quem escreveu.
  await _marcarEntregue();
}

/// O Chamado ou a conversa que a notificação tocada pede para abrir.
void _abrirOQueTocaram(RemoteMessage mensagem) {
  final chamado = mensagem.data['chamadoId'] as String?;
  if (chamado != null && chamado.isNotEmpty) {
    chamadoTocado.value = chamado;
    return;
  }
  final conversa = mensagem.data['conversaId'] as String?;
  if (mensagem.data['tipo'] == 'mensagem' &&
      conversa != null &&
      conversa.isNotEmpty) {
    conversaTocada.value = conversa;
  }
}

/// Marca no servidor que as mensagens chegaram neste aparelho.
///
/// Com o app aberto isto já acontece pela tela; aqui vale para o app fechado,
/// quando quem recebe o push é um isolate sem app de pé — e é o que faz o
/// segundo tique dizer a verdade com o celular no bolso.
Future<void> _marcarEntregue() async {
  if (!AppConfig.hasBackend) return;
  try {
    final db = await _servidor();
    await db?.rpc('mark_delivered').timeout(const Duration(seconds: 5));
  } catch (e) {
    // Sem rede, ou sessão vencida: quem está com o app aberto marca depois.
    debugPrint('Não deu para marcar a entrega: $e');
  }
}

/// O servidor visto de dentro do isolate: o do app, quando ele está de pé, ou
/// um cliente só para esta notificação, com a sessão guardada no aparelho.
Future<supabase.SupabaseClient?> _servidor() async {
  try {
    return supabase.Supabase.instance.client;
  } catch (_) {
    final instancia = await supabase.Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    return instancia.client;
  }
}

/// O encontro fixo chegando, duas horas antes, para quem ainda não confirmou
/// presença. Aviso comum: não abre em tela cheia nem toca como ligação. Quem
/// toca nele abre o app, onde o "você vai?" espera na lista de conversas.
Future<void> _mostrarLembrete(Map<String, dynamic> dados) async {
  final hora = DateTime.tryParse(dados['hora'] as String? ?? '');
  if (hora == null) return;
  final jogo = (dados['jogo'] as String? ?? '').trim();
  final conversa = dados['conversaId'] as String? ?? 'encontro';

  await _notificacoes.show(
    // Um aviso por grupo: o lembrete novo toma o lugar do antigo.
    id: conversa.hashCode,
    title: 'Encontro do grupo às ${hhmm(hora.toLocal())}',
    body: jogo.isEmpty ? 'Você vai?' : '$jogo · você vai?',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _canalLembrete.id,
        _canalLembrete.name,
        channelDescription: _canalLembrete.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}

/// Liga o push para [userId]: permissão, aparelho registrado no servidor e as
/// mensagens virando notificação. Falhar aqui não derruba o app — o Chamado
/// continua aparecendo com o app aberto.
Future<void> ligarPush({
  required SaleRepository repository,
  required String userId,
}) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Push desligado: falta a configuração do Firebase ($e)');
    return;
  }

  await _prepararNotificacoes();
  final mensagens = FirebaseMessaging.instance;

  final permissao = await mensagens.requestPermission();
  if (permissao.authorizationStatus == AuthorizationStatus.denied) {
    debugPrint('Push desligado: a pessoa recusou as notificações');
    return;
  }

  FirebaseMessaging.onBackgroundMessage(_comOAppFechado);
  FirebaseMessaging.onMessage.listen(_mostrar);

  // Tocar na notificação com o app em segundo plano.
  FirebaseMessaging.onMessageOpenedApp.listen(_abrirOQueTocaram);

  // O app estava fechado e abriu pela notificação.
  final inicial = await mensagens.getInitialMessage();
  if (inicial != null) _abrirOQueTocaram(inicial);

  final token = await mensagens.getToken();
  if (token != null) await repository.saveDeviceToken(token);
  // O token é trocado de tempos em tempos pelo próprio Firebase.
  mensagens.onTokenRefresh.listen(repository.saveDeviceToken);
}
