import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/update/update_service.dart';

import 'helpers.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v1.2.0',
  List<Map<String, dynamic>>? assets,
  String? body = '- Semana nova',
}) => {
  'tag_name': tag,
  'body': body,
  'assets':
      assets ??
      [
        {'name': 'notas.txt', 'browser_download_url': 'https://x/notas.txt'},
        {
          'name': 'Sale-v1.2.0.apk',
          'browser_download_url': 'https://x/Sale-v1.2.0.apk',
          'digest': 'sha256:abc123',
        },
      ],
};

void main() {
  group('comparar versões', () {
    test('ordena por número, não por texto', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0+7', '1.2.0+3'), 0);
      expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
    });
  });

  group('ler a release do GitHub', () {
    test('pega a versão sem "v", o APK, as notas e o sha256', () {
      final r = parseRelease(releaseJson())!;
      expect(r.version, '1.2.0');
      expect(r.apkUrl, 'https://x/Sale-v1.2.0.apk');
      expect(r.notes, '- Semana nova');
      expect(r.sha256, 'abc123');
    });

    test('release sem APK não conta como atualização', () {
      expect(parseRelease(releaseJson(assets: [])), isNull);
      expect(parseRelease({'assets': []}), isNull);
    });

    test('sem digest, segue sem conferir o sha256', () {
      final r = parseRelease(
        releaseJson(
          body: null,
          assets: [
            {'name': 'a.apk', 'browser_download_url': 'https://x/a.apk'},
          ],
        ),
      )!;
      expect(r.sha256, isNull);
      expect(r.notes, '');
    });
  });

  group('checkForUpdate', () {
    const newer = AppRelease(version: '1.2.0', apkUrl: 'https://x/a.apk');

    test('avisa só se a publicada for mais nova', () async {
      expect(await checkForUpdate(FakeReleaseSource(newer), '1.1.0'), newer);
      expect(await checkForUpdate(FakeReleaseSource(newer), '1.2.0'), isNull);
      expect(await checkForUpdate(FakeReleaseSource(newer), '1.3.0'), isNull);
      expect(await checkForUpdate(FakeReleaseSource(), '1.1.0'), isNull);
    });
  });

  group('aviso no app', () {
    const newer = AppRelease(
      version: '1.2.0',
      apkUrl: 'https://x/a.apk',
      notes: '- Semana nova',
    );

    testWidgets(
      'aparece com versão nova, mostra as novidades e some no "Depois"',
      (tester) async {
        await pumpApp(tester, releases: FakeReleaseSource(newer));
        await signInAs(tester, 'Israel');

        expect(find.text('Versão 1.2.0 disponível'), findsOneWidget);
        await tester.tap(find.text('Atualizar'));
        await tester.pumpAndSettle();
        expect(find.text('Sale? 1.2.0'), findsOneWidget);
        expect(find.text('- Semana nova'), findsOneWidget);
        await tester.tap(find.text('Agora não'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Depois'));
        await tester.pumpAndSettle();
        expect(find.text('Versão 1.2.0 disponível'), findsNothing);
      },
    );

    testWidgets('em dia, não aparece nada', (tester) async {
      await pumpApp(
        tester,
        releases: FakeReleaseSource(newer),
        installed: '1.2.0',
      );
      await signInAs(tester, 'Israel');
      expect(find.textContaining('disponível'), findsNothing);
    });

    testWidgets('"Verificar atualização" no menu consulta de novo', (
      tester,
    ) async {
      final source = FakeReleaseSource();
      await pumpApp(tester, releases: source);
      await signInAs(tester, 'Israel');
      final before = source.calls;

      await tester.tap(find.byTooltip('Trocar usuário (desenvolvimento)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar atualização (v1.1.0)'));
      await tester.pumpAndSettle();
      expect(source.calls, greaterThan(before));
      expect(
        find.text('Você já está na última versão (1.1.0).'),
        findsOneWidget,
      );

      // Publicaram uma nova: a próxima verificação abre o diálogo.
      source.release = newer;
      await tester.tap(find.byTooltip('Trocar usuário (desenvolvimento)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar atualização (v1.1.0)'));
      await tester.pumpAndSettle();
      expect(find.text('Sale? 1.2.0'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
