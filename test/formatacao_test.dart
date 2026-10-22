import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/formatacao.dart';

void main() {
  /// O texto que aparece na tela, já sem os sinais.
  String visivel(List<Trecho> trechos) => trechos.map((t) => t.texto).join();

  Trecho trechoDe(List<Trecho> trechos, String texto) =>
      trechos.firstWhere((t) => t.texto == texto);

  group('formatação como no WhatsApp', () {
    test('negrito, itálico, riscado e código perdem os sinais', () {
      final t = trechosDoTexto('*bora* _hoje_ ~amanhã~ `10.0.0.1`');
      expect(visivel(t), 'bora hoje amanhã 10.0.0.1');
      expect(trechoDe(t, 'bora').negrito, isTrue);
      expect(trechoDe(t, 'hoje').italico, isTrue);
      expect(trechoDe(t, 'amanhã').riscado, isTrue);
      expect(trechoDe(t, '10.0.0.1').codigo, isTrue);
    });

    test('dá para juntar: negrito e itálico', () {
      final t = trechosDoTexto('*_tudo_*');
      expect(visivel(t), 'tudo');
      expect(t.single.negrito && t.single.italico, isTrue);
    });

    test('o que não é formatação fica como foi escrito', () {
      for (final texto in [
        '2*3*4',
        'nome_do_arquivo.txt',
        '* solto *',
        'só um *',
        '**',
        'a~b~c',
      ]) {
        final t = trechosDoTexto(texto);
        expect(visivel(t), texto, reason: texto);
        expect(textoSimples(t), isTrue, reason: texto);
      }
    });

    test('dentro do código nada se formata', () {
      final t = trechosDoTexto('`*nao*_vira_`');
      expect(visivel(t), '*nao*_vira_');
      expect(t.single.codigo, isTrue);
      expect(t.single.negrito, isFalse);
    });

    test('não atravessa linha', () {
      final t = trechosDoTexto('*começa\ntermina*');
      expect(visivel(t), '*começa\ntermina*');
    });
  });

  group('links', () {
    test('o link é achado e a pontuação do fim fica de fora', () {
      final t = trechosDoTexto('olha https://sale.app/x_y_z.');
      expect(visivel(t), 'olha https://sale.app/x_y_z.');
      final link = trechoDe(t, 'https://sale.app/x_y_z');
      expect(link.link, 'https://sale.app/x_y_z');
      // O "_" do endereço não virou itálico.
      expect(link.italico, isFalse);
      expect(trechoDe(t, '.').link, isNull);
    });

    test('"www." ganha o https', () {
      final t = trechosDoTexto('www.exemplo.com');
      expect(t.single.link, 'https://www.exemplo.com');
    });

    test('texto sem link não tem link', () {
      expect(trechosDoTexto('exemplo.com sem protocolo').single.link, isNull);
    });
  });

  group('menções', () {
    const nomes = {'p1': 'Pessoa 1', 'p2': 'Pessoa 2'};

    test('a minha salta aos olhos; a dos outros só fica em negrito', () {
      final t = trechosDoTexto(
        '@Pessoa 1 e @Pessoa 2',
        nomes: nomes,
        userId: 'p1',
      );
      expect(trechoDe(t, '@Pessoa 1').mencaoMinha, isTrue);
      expect(trechoDe(t, '@Pessoa 2').mencaoMinha, isFalse);
      expect(trechoDe(t, ' e ').mencaoMinha, isNull);
    });

    test('@todos é de todo mundo', () {
      final t = trechosDoTexto('@todos bora', nomes: nomes, userId: 'p2');
      expect(trechoDe(t, '@todos').mencaoMinha, isTrue);
    });
  });
}
