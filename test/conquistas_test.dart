import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/conquistas.dart';
import 'package:sale/domain/models.dart';

const _bora = QuickReply(
  id: 'bora',
  icon: 'check',
  label: 'Bora!',
  kind: ReplyKind.yes,
);
const _naoVou = QuickReply(
  id: 'nao',
  icon: 'x',
  label: 'Hoje não',
  kind: ReplyKind.no,
);

var _n = 0;

/// Um Chamado de [autor] para [chamados], com as respostas dadas.
Chamado _chamado({
  required String autor,
  required DateTime quando,
  Map<String, ChamadoResponse?> respostas = const {},
  ChamadoStatus status = ChamadoStatus.closed,
}) => Chamado(
  id: 'c${_n++}',
  conversationId: 'grupo',
  authorId: autor,
  createdAt: quando,
  responses: respostas,
  status: status,
);

/// "Bora!" respondido em [quando], chegando [atraso] depois.
ChamadoResponse _veio(DateTime quando, {Duration? atraso}) => ChamadoResponse(
  reply: _bora,
  respondedAt: quando,
  arrivedAt: atraso == null ? null : quando.add(atraso),
);

Conquista _a(List<Conquista> todas, String titulo) =>
    todas.firstWhere((c) => c.titulo == titulo);

void main() {
  final dia = DateTime(2026, 10, 5, 21);

  test('sem história, nada ganho e tudo com o que falta', () {
    final todas = conquistasDe('p1', const []);
    expect(todas.where((c) => c.ganhou), isEmpty);
    expect(_a(todas, 'Convocador').progresso, '0/10');
  });

  test('chamar conta para o primeiro batsinal e o convocador', () {
    final todas = conquistasDe('p1', [
      for (var i = 0; i < 3; i++) _chamado(autor: 'p1', quando: dia),
    ]);
    expect(_a(todas, 'Primeiro batsinal').ganhou, isTrue);
    expect(_a(todas, 'Convocador').progresso, '3/10');
    // As ganhas vêm primeiro.
    expect(todas.first.titulo, 'Primeiro batsinal');
  });

  test('três chegadas na hora seguidas fazem o pontual', () {
    final todas = conquistasDe('p2', [
      for (var i = 0; i < 3; i++)
        _chamado(
          autor: 'p1',
          quando: dia.add(Duration(days: i)),
          respostas: {
            'p2': _veio(dia.add(Duration(days: i)), atraso: Duration.zero),
          },
        ),
    ]);
    expect(_a(todas, 'O Pontual').ganhou, isTrue);
    expect(_a(todas, 'Sempre topa').progresso, '3/10');
  });

  test('um atraso no meio quebra a sequência do pontual', () {
    final todas = conquistasDe('p2', [
      for (final (i, atraso) in [0, 40, 0].indexed)
        _chamado(
          autor: 'p1',
          quando: dia.add(Duration(days: i)),
          respostas: {
            'p2': _veio(
              dia.add(Duration(days: i)),
              atraso: Duration(minutes: atraso),
            ),
          },
        ),
    ]);
    expect(_a(todas, 'O Pontual').progresso, '1/3');
    expect(_a(todas, 'Atrasado de carteirinha').ganhou, isTrue);
  });

  test('topar de madrugada é coruja; sumir é fantasma', () {
    final madrugada = DateTime(2026, 10, 6, 2);
    final todas = conquistasDe('p2', [
      _chamado(
        autor: 'p1',
        quando: madrugada,
        respostas: {'p2': _veio(madrugada)},
      ),
      for (var i = 0; i < 5; i++)
        _chamado(autor: 'p1', quando: dia, respostas: {'p2': null}),
      _chamado(
        autor: 'p1',
        quando: dia,
        respostas: {'p2': ChamadoResponse(reply: _naoVou, respondedAt: dia)},
      ),
    ]);
    expect(_a(todas, 'Coruja').ganhou, isTrue);
    expect(_a(todas, 'Fantasma').ganhou, isTrue);
  });

  test('a do dia conta as vitórias', () {
    final todas = conquistasDe('p1', const [], vitoriasDoDia: 2);
    expect(_a(todas, 'A do dia').ganhou, isTrue);
    expect(_a(todas, 'Lenda do Hall').progresso, '2/5');
  });
}
