import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: SaleApp()));
}

class SaleApp extends ConsumerWidget {
  const SaleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider);
    return MaterialApp(
      title: 'Sale?',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A chave recria a navegação ao trocar de usuário.
      home: userId == null
          ? const LoginScreen()
          : HomeScreen(key: ValueKey(userId), userId: userId),
    );
  }
}
