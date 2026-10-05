/// As menções do chat: "@Nome" chama a atenção de alguém da conversa, e
/// "@todos" de todo mundo.
///
/// O texto da mensagem guarda a menção como foi escrita; quem foi mencionado
/// também vai numa lista na própria mensagem, que é por onde o servidor sabe
/// quem avisar com mais força.
library;

/// A palavra que menciona todo mundo da conversa.
const mencaoTodos = 'todos';

/// Um "@Nome" dentro do texto: onde começa e termina, e de quem é. [id] nulo
/// é o "@todos".
typedef Mencao = ({int inicio, int fim, String? id});

bool _letraOuNumero(String c) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);

/// As menções de [texto], na ordem em que aparecem. [nomes] é id -> nome de
/// quem está na conversa.
///
/// Nome mais longo ganha do mais curto ("@Ana Paula" é a Ana Paula, não a
/// Ana), e a menção precisa terminar onde termina a palavra: "@Anabela" não é
/// a Ana. Maiúscula e minúscula tanto faz.
List<Mencao> mencoesNoTexto(String texto, Map<String, String> nomes) {
  final candidatos = <(String nome, String? id)>[
    (mencaoTodos, null),
    for (final e in nomes.entries)
      if (e.value.trim().isNotEmpty) (e.value.trim(), e.key),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  final minusculo = texto.toLowerCase();
  final achadas = <Mencao>[];
  var i = 0;
  while (i < texto.length) {
    final arroba = texto.indexOf('@', i);
    if (arroba == -1) break;
    // "fulano@email" não é menção: o @ abre palavra.
    final abre = arroba == 0 || !_letraOuNumero(texto[arroba - 1]);
    Mencao? achada;
    if (abre) {
      for (final (nome, id) in candidatos) {
        final fim = arroba + 1 + nome.length;
        if (fim > texto.length) continue;
        if (minusculo.substring(arroba + 1, fim) != nome.toLowerCase()) {
          continue;
        }
        if (fim < texto.length && _letraOuNumero(texto[fim])) continue;
        achada = (inicio: arroba, fim: fim, id: id);
        break;
      }
    }
    if (achada == null) {
      i = arroba + 1;
    } else {
      achadas.add(achada);
      i = achada.fim;
    }
  }
  return achadas;
}

/// Quem [texto] menciona, fora quem escreveu: "@todos" vale por todo mundo
/// de [nomes].
Set<String> quemFoiMencionado(
  String texto,
  Map<String, String> nomes,
  String autorId,
) {
  final ids = <String>{};
  for (final mencao in mencoesNoTexto(texto, nomes)) {
    final id = mencao.id;
    if (id == null) {
      ids.addAll(nomes.keys);
    } else {
      ids.add(id);
    }
  }
  return ids..remove(autorId);
}

/// O que se está digitando depois de um "@" no fim do texto, para sugerir
/// nomes; nulo quando não há menção em andamento.
String? mencaoEmAndamento(String texto) {
  final arroba = texto.lastIndexOf('@');
  if (arroba == -1) return null;
  if (arroba > 0 && _letraOuNumero(texto[arroba - 1])) return null;
  final consulta = texto.substring(arroba + 1);
  // Nome de gente cabe em 24 letras; passou disso, ou pulou linha, já não é.
  if (consulta.length > 24 || consulta.contains('\n')) return null;
  return consulta;
}

/// O texto com a menção em andamento completada por [nome], e um espaço para
/// seguir escrevendo.
String completarMencao(String texto, String nome) {
  final arroba = texto.lastIndexOf('@');
  if (arroba == -1) return texto;
  return '${texto.substring(0, arroba)}@$nome ';
}
