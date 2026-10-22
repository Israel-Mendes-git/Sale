/// A formatação do texto da mensagem, como no WhatsApp: *negrito*, _itálico_,
/// ~riscado~ e `código`, mais os links e as menções em destaque.
///
/// O texto guardado é o que se digitou, com os sinais; quem desenha a bolha
/// pede aqui os trechos já sem eles.
library;

import 'mentions.dart';

/// Um pedaço do texto com o mesmo jeito do começo ao fim.
typedef Trecho = ({
  String texto,
  bool negrito,
  bool italico,
  bool riscado,
  bool codigo,
  String? link,
  // Nulo: não é menção. Verdadeiro: é para quem está lendo (ou "@todos").
  bool? mencaoMinha,
});

/// Endereço na mensagem: com "http(s)://" ou começando por "www.".
final _link = RegExp(r'(?:https?://|www\.)[^\s<>]+', caseSensitive: false);

/// O que costuma fechar a frase depois do link e não é dele.
const _pontuacaoFinal = '.,;:!?)]}\'"';

/// `código`: dentro dele nada mais é formatado.
final _codigo = RegExp(r'`([^`\n]+)`');

/// *x*, _x_ e ~x~: o sinal abre e fecha palavra, e o miolo não começa nem
/// termina em espaço — "2*3*4" e "nome_do_arquivo" continuam como estão.
RegExp _marcador(String s) {
  // No modo unicode só se escapa o que é sinal de regex: "\_" seria erro.
  final e = RegExp.escape(s);
  return RegExp(
    '(?<![\\p{L}\\p{N}$s])$e(?!\\s)([^$s\\n]*?[^\\s$s])$e(?![\\p{L}\\p{N}$s])',
    unicode: true,
  );
}

final _negrito = _marcador('*');
final _italico = _marcador('_');
final _riscado = _marcador('~');

/// O endereço que o link abre: "www." ganha o "https://".
String enderecoDoLink(String link) =>
    link.toLowerCase().startsWith('www.') ? 'https://$link' : link;

/// Os links de [texto], na ordem, sem a pontuação que fecha a frase.
List<({int inicio, int fim})> linksNoTexto(String texto) => [
  for (final m in _link.allMatches(texto))
    (inicio: m.start, fim: _semPontuacaoFinal(texto, m.start, m.end)),
];

int _semPontuacaoFinal(String texto, int inicio, int fim) {
  while (fim > inicio && _pontuacaoFinal.contains(texto[fim - 1])) {
    fim--;
  }
  return fim;
}

/// [texto] quebrado em trechos. [nomes] é id -> nome de quem está na conversa,
/// para as menções; [userId] é quem lê, cuja menção salta aos olhos.
List<Trecho> trechosDoTexto(
  String texto, {
  Map<String, String> nomes = const {},
  String? userId,
}) {
  final n = texto.length;
  final negrito = List.filled(n, false);
  final italico = List.filled(n, false);
  final riscado = List.filled(n, false);
  final codigo = List.filled(n, false);
  final escondido = List.filled(n, false);
  final link = List<String?>.filled(n, null);
  final mencao = List<bool?>.filled(n, null);

  // Link e código ficam como foram escritos: "_" de endereço não é itálico.
  final intocavel = List.filled(n, false);
  for (final l in linksNoTexto(texto)) {
    final endereco = enderecoDoLink(texto.substring(l.inicio, l.fim));
    for (var i = l.inicio; i < l.fim; i++) {
      link[i] = endereco;
      intocavel[i] = true;
    }
  }
  for (final m in _codigo.allMatches(texto)) {
    if (intocavel[m.start]) continue;
    escondido[m.start] = true;
    escondido[m.end - 1] = true;
    for (var i = m.start; i < m.end; i++) {
      codigo[i] = true;
      intocavel[i] = true;
    }
  }

  void marcar(RegExp re, List<bool> estilo) {
    for (final m in re.allMatches(texto)) {
      if (intocavel[m.start] || intocavel[m.end - 1]) continue;
      escondido[m.start] = true;
      escondido[m.end - 1] = true;
      for (var i = m.start + 1; i < m.end - 1; i++) {
        if (!intocavel[i]) estilo[i] = true;
      }
    }
  }

  marcar(_negrito, negrito);
  marcar(_italico, italico);
  marcar(_riscado, riscado);

  for (final m in mencoesNoTexto(texto, nomes)) {
    for (var i = m.inicio; i < m.fim; i++) {
      if (!intocavel[i]) mencao[i] = m.id == null || m.id == userId;
    }
  }

  final trechos = <Trecho>[];
  final atual = StringBuffer();
  Trecho? jeito;
  bool mesmoJeito(Trecho a, Trecho b) =>
      a.negrito == b.negrito &&
      a.italico == b.italico &&
      a.riscado == b.riscado &&
      a.codigo == b.codigo &&
      a.link == b.link &&
      a.mencaoMinha == b.mencaoMinha;
  void fechar() {
    if (jeito != null && atual.isNotEmpty) {
      trechos.add((
        texto: atual.toString(),
        negrito: jeito.negrito,
        italico: jeito.italico,
        riscado: jeito.riscado,
        codigo: jeito.codigo,
        link: jeito.link,
        mencaoMinha: jeito.mencaoMinha,
      ));
    }
    atual.clear();
  }

  for (var i = 0; i < n; i++) {
    if (escondido[i]) continue;
    final deste = (
      texto: '',
      negrito: negrito[i],
      italico: italico[i],
      riscado: riscado[i],
      codigo: codigo[i],
      link: link[i],
      mencaoMinha: mencao[i],
    );
    if (jeito == null || !mesmoJeito(jeito, deste)) {
      fechar();
      jeito = deste;
    }
    atual.write(texto[i]);
  }
  fechar();
  return trechos;
}

/// Verdadeiro quando o texto não tem nada a formatar: a bolha usa o Text
/// simples, que é mais leve.
bool textoSimples(List<Trecho> trechos) =>
    trechos.length <= 1 &&
    trechos.every(
      (t) =>
          !t.negrito &&
          !t.italico &&
          !t.riscado &&
          !t.codigo &&
          t.link == null &&
          t.mencaoMinha == null,
    );
