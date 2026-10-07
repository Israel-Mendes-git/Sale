import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// As conquistas: as bobagens e glórias de cada um, contadas dos Chamados e da
/// do dia. Conta pura, como o placar (`stats.dart`).

/// Uma conquista e quanto falta para ela.
@immutable
class Conquista {
  const Conquista({
    required this.emoji,
    required this.titulo,
    required this.descricao,
    required this.atual,
    required this.meta,
  });

  final String emoji;
  final String titulo;
  final String descricao;

  /// Quanto já foi feito, e quanto precisa.
  final int atual;
  final int meta;

  bool get ganhou => atual >= meta;

  /// "3/10" enquanto não ganhou; o que passou da meta não conta.
  String get progresso => '${math.min(atual, meta)}/$meta';
}

/// As conquistas de [userId], das ganhas às que faltam.
///
/// [historico] são os Chamados em que a pessoa esteve (chamando ou chamada);
/// [vitoriasDoDia] é quantas vezes uma mensagem dela foi a do dia;
/// [minutosDeCall], quanto ficou na call do Discord do grupo — nulo quando o
/// grupo não ligou o Discord ou a pessoa não disse o nome dela lá, e aí a
/// conquista da call nem aparece.
List<Conquista> conquistasDe(
  String userId,
  Iterable<Chamado> historico, {
  int vitoriasDoDia = 0,
  int? minutosDeCall,
}) {
  final cronologia = [...historico]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  var chamou = 0;
  var topou = 0;
  var ignorou = 0;
  var deMadrugada = 0;
  var atrasoFeio = 0;
  var pontuaisSeguidas = 0;
  var melhorSequencia = 0;

  for (final chamado in cronologia) {
    if (chamado.authorId == userId && !chamado.automatic) chamou++;
    if (!chamado.responses.containsKey(userId)) continue;
    final resposta = chamado.responses[userId];
    if (resposta == null) {
      if (!chamado.isOpen) ignorou++;
      continue;
    }
    final vem =
        resposta.reply.kind == ReplyKind.yes ||
        resposta.reply.kind == ReplyKind.later;
    if (vem) {
      topou++;
      // De madrugada: entre a meia-noite e as 6h.
      if (resposta.respondedAt.toLocal().hour < 6) deMadrugada++;
    }
    final atraso = chamado.lateBy(userId);
    if (atraso != null) {
      // Na hora ou antes é pontual; menos de um minuto conta como na hora.
      if (atraso.inMinutes <= 0) {
        pontuaisSeguidas++;
        melhorSequencia = math.max(melhorSequencia, pontuaisSeguidas);
      } else {
        pontuaisSeguidas = 0;
      }
      if (atraso.inMinutes >= 30) atrasoFeio++;
    }
  }

  final todas = [
    Conquista(
      emoji: '📣',
      titulo: 'Primeiro batsinal',
      descricao: 'Disparou o primeiro Chamado.',
      atual: chamou,
      meta: 1,
    ),
    Conquista(
      emoji: '🔦',
      titulo: 'Convocador',
      descricao: 'Disparou 10 Chamados.',
      atual: chamou,
      meta: 10,
    ),
    Conquista(
      emoji: '✅',
      titulo: 'Sempre topa',
      descricao: 'Disse que vinha 10 vezes.',
      atual: topou,
      meta: 10,
    ),
    Conquista(
      emoji: '⏱️',
      titulo: 'O Pontual',
      descricao: 'Chegou na hora 3 vezes seguidas.',
      atual: melhorSequencia,
      meta: 3,
    ),
    Conquista(
      emoji: '🦉',
      titulo: 'Coruja',
      descricao: 'Topou um Chamado de madrugada.',
      atual: deMadrugada,
      meta: 1,
    ),
    Conquista(
      emoji: '🏆',
      titulo: 'A do dia',
      descricao: 'Teve uma mensagem eleita a do dia.',
      atual: vitoriasDoDia,
      meta: 1,
    ),
    Conquista(
      emoji: '👑',
      titulo: 'Lenda do Hall',
      descricao: 'Foi a do dia cinco vezes.',
      atual: vitoriasDoDia,
      meta: 5,
    ),
    if (minutosDeCall != null)
      Conquista(
        emoji: '🎧',
        titulo: 'Morador da call',
        descricao: 'Ficou 10 horas na call do Discord do grupo.',
        atual: minutosDeCall ~/ 60,
        meta: 10,
      ),
    Conquista(
      emoji: '🐢',
      titulo: 'Atrasado de carteirinha',
      descricao: 'Chegou meia hora (ou mais) depois do prometido.',
      atual: atrasoFeio,
      meta: 1,
    ),
    Conquista(
      emoji: '👻',
      titulo: 'Fantasma',
      descricao: 'Deixou 5 Chamados sem resposta.',
      atual: ignorou,
      meta: 5,
    ),
  ];
  // As ganhas primeiro; dentro de cada parte, a ordem de cima.
  return [...todas.where((c) => c.ganhou), ...todas.where((c) => !c.ganhou)];
}
