import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/screens/conversations_screen.dart';
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
      // A chave recria a navegação ao trocar de usuário.
      home: userId == null
          ? const LoginScreen()
          : ConversationsScreen(key: ValueKey(userId), userId: userId),
    );
  }
}
