import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/repository.dart';

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

const _canal = AndroidNotificationChannel(
  'chamado',
  'Chamados',
  description: 'Quando alguém te chama pra jogar.',
  importance: Importance.max,
);

final _notificacoes = FlutterLocalNotificationsPlugin();

/// Mensagem que chega com o app fechado: o Android acorda um isolate só para
/// isto, sem telas nem estado. Dá para montar a notificação e mais nada.
@pragma('vm:entry-point')
Future<void> _comOAppFechado(RemoteMessage mensagem) async {
  await Firebase.initializeApp();
  await _prepararNotificacoes();
  await _mostrar(mensagem);
}

Future<void> _prepararNotificacoes() async {
  await _notificacoes.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notificacao'),
    ),
    onDidReceiveNotificationResponse: (resposta) {
      final id = resposta.payload;
      if (id != null && id.isNotEmpty) chamadoTocado.value = id;
    },
  );
  await _notificacoes
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_canal);
}

Future<void> _mostrar(RemoteMessage mensagem) async {
  final dados = mensagem.data;
  final chamadoId = dados['chamadoId'] as String?;
  if (chamadoId == null) return;

  final autor = dados['autor'] as String? ?? 'Alguém';
  final jogo = (dados['jogo'] as String? ?? '').trim();
  final nota = (dados['nota'] as String? ?? '').trim();
  final detalhe = [
    if (jogo.isNotEmpty) jogo,
    if (nota.isNotEmpty) '"$nota"',
  ].join(' · ');

  await _notificacoes.show(
    id: chamadoId.hashCode,
    title: '$autor te chamou pra jogar',
    body: detalhe.isEmpty ? 'Toque para responder' : detalhe,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _canal.id,
        _canal.name,
        channelDescription: _canal.description,
        importance: Importance.max,
        priority: Priority.max,
        // Como uma ligação: abre por cima da tela bloqueada.
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        ticker: 'Chamado',
      ),
    ),
    payload: chamadoId,
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
  FirebaseMessaging.onMessageOpenedApp.listen((mensagem) {
    final id = mensagem.data['chamadoId'] as String?;
    if (id != null) chamadoTocado.value = id;
  });

  // O app estava fechado e abriu pela notificação.
  final inicial = await mensagens.getInitialMessage();
  final idInicial = inicial?.data['chamadoId'] as String?;
  if (idInicial != null) chamadoTocado.value = idInicial;

  final token = await mensagens.getToken();
  if (token != null) await repository.saveDeviceToken(token);
  // O token é trocado de tempos em tempos pelo próprio Firebase.
  mensagens.onTokenRefresh.listen(repository.saveDeviceToken);
}
