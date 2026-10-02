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
///
/// [now] fixa a hora; [clock] serve para quem precisa que o tempo ande no
/// meio do teste (o placar do atraso, por exemplo).
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  DateTime? now,
  DateTime Function()? clock,
  ReleaseSource? releases,
  String installed = '1.1.0',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      if (clock != null)
        clockProvider.overrideWithValue(clock)
      else if (now != null)
        clockProvider.overrideWithValue(() => now),
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

/// Rola a tela que está na frente até achar [finder]. A de trás continua na
/// árvore, por isso o scrollable precisa ser o último.
///
/// Tela com campo de texto precisa dizer qual lista rolar: o campo também é
/// um scrollable, e fica depois da lista na árvore.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  bool up = false,
  Finder? scrollable,
}) async {
  await tester.scrollUntilVisible(
    finder,
    up ? -200 : 200,
    scrollable: scrollable ?? find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// O que rola na lista da tela que está na frente — e não o campo de texto
/// dentro dela.
final frontList = find
    .descendant(
      of: find.byType(ListView).last,
      matching: find.byType(Scrollable),
    )
    .first;

/// Troca de pessoa com o app já aberto, pelo seletor de desenvolvimento.
Future<void> switchTo(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Trocar usuário (desenvolvimento)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Entrar como $name'));
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
