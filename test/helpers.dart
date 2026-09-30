import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/calendar.dart';
import 'package:sale/main.dart';
import 'package:sale/state/providers.dart';
import 'package:sale/update/update_providers.dart';
import 'package:sale/update/update_service.dart';

/// Origem de versões falsa: nada de internet nos testes.
class FakeReleaseSource implements ReleaseSource {
  FakeReleaseSource([this.release]);

  AppRelease? release;
  var calls = 0;

  @override
  Future<AppRelease?> latest() async {
    calls++;
    return release;
  }
}

/// Sobe o app com relógio fixo, versão instalada fixa e sem rede, numa
/// tela do tamanho de um celular.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  DateTime? now,
  ReleaseSource? releases,
  String installed = '1.1.0',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      if (now != null) clockProvider.overrideWithValue(() => now),
      releaseSourceProvider.overrideWithValue(releases ?? FakeReleaseSource()),
      installedVersionProvider.overrideWith((ref) async => installed),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SaleApp()),
  );
  return container;
}

Future<void> signInAs(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Lê o repositório fora do relógio falso do teste: esperar o stream
/// direto dentro do testWidgets trava o toque seguinte.
Future<CalendarData> calendarOf(
  WidgetTester tester,
  ProviderContainer c,
  String userId,
) async => (await tester.runAsync(
  () => c.read(repositoryProvider).watchCalendar(userId).first,
))!;
