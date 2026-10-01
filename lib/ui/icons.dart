import 'package:flutter/material.dart';

/// Os ícones das respostas rápidas, pelo nome guardado no banco.
///
/// O banco guarda o nome ('comida'), não o desenho: assim a mesma resposta
/// fica igual em qualquer celular — emoji muda de cara conforme o aparelho —
/// e dá para trocar o desenho sem mexer nos dados.
const replyIcons = <String, IconData>{
  // Das respostas comuns a todos.
  'check': Icons.check_rounded,
  'relogio': Icons.schedule_rounded,
  'xis': Icons.close_rounded,
  'soneca': Icons.snooze_rounded,
  // Para as que cada um cadastra.
  'balao': Icons.chat_bubble_outline_rounded,
  'trabalho': Icons.work_outline_rounded,
  'estudo': Icons.school_outlined,
  'comida': Icons.restaurant_rounded,
  'cafe': Icons.local_cafe_outlined,
  'casa': Icons.home_outlined,
  'rua': Icons.directions_walk_rounded,
  'carro': Icons.directions_car_outlined,
  'cama': Icons.bedtime_outlined,
  'banho': Icons.shower_outlined,
  'familia': Icons.family_restroom_rounded,
  'bebe': Icons.child_care_rounded,
  'cachorro': Icons.pets_rounded,
  'tv': Icons.tv_rounded,
  'musica': Icons.headphones_rounded,
  'treino': Icons.fitness_center_rounded,
  'telefone': Icons.phone_outlined,
  'jogo': Icons.sports_esports_outlined,
  'ocupado': Icons.do_not_disturb_on_outlined,
  'talvez': Icons.help_outline_rounded,
};

/// Desenho de uma resposta. Nome desconhecido (resposta antiga, versão nova
/// do app) cai no balão, em vez de sumir.
IconData replyIcon(String? name) =>
    replyIcons[name] ?? Icons.chat_bubble_outline_rounded;

/// O que aparece na grade ao criar uma resposta própria: as quatro primeiras
/// são das respostas comuns, então ficam de fora.
const choosableReplyIcons = [
  'balao',
  'trabalho',
  'estudo',
  'comida',
  'cafe',
  'casa',
  'rua',
  'carro',
  'cama',
  'banho',
  'familia',
  'bebe',
  'cachorro',
  'tv',
  'musica',
  'treino',
  'telefone',
  'jogo',
  'ocupado',
  'talvez',
];
