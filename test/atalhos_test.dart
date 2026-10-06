import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale/push/atalhos.dart';

void main() {
  // O widget da tela inicial abre o app com o mesmo extra do atalho de
  // segurar o ícone; se os nomes se desencontram, ele só abre o app.
  test('o widget da tela inicial manda o mesmo atalho', () {
    final widget = File(
      'android/app/src/main/kotlin/com/israelmendes/sale/WidgetChamar.kt',
    ).readAsStringSync();
    expect(widget, contains('ATALHO_CHAMAR_GRUPO = "$atalhoChamarGrupo"'));

    final plugin = File(_raizDoPacote('quick_actions_android'))
        .readAsStringSync();
    final extra = RegExp(r'EXTRA_ACTION = "([^"]+)"')
        .firstMatch(plugin)!
        .group(1);
    expect(widget, contains('EXTRA_DO_ATALHO = "$extra"'));
  });
}

/// O QuickActions.java do plugin, achado pelo package_config do pub.
String _raizDoPacote(String nome) {
  final config = File('.dart_tool/package_config.json').readAsStringSync();
  final raiz = RegExp('"rootUri": "([^"]*/$nome-[^"]*)"')
      .firstMatch(config)!
      .group(1)!;
  return '${Uri.parse(raiz).toFilePath()}/android/src/main/java/io/flutter/'
      'plugins/quickactions/QuickActions.java';
}
