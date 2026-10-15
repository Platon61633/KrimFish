import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin/admin_shell.dart';
import 'client/client_shell.dart';
import 'core/messenger.dart';
import 'data/firebase_setup.dart';
import 'core/theme.dart';
import 'login_screen.dart';
import 'registration_screen.dart';
import 'state/providers.dart';
import 'state/push.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const KrimFishApp(),
    ),
  );
}

class KrimFishApp extends StatelessWidget {
  const KrimFishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KrimFish',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(),
      home: const RootGate(),
    );
  }
}

/// Показывает вход или нужную оболочку в зависимости от роли.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    ref.watch(pushProvider); // регистрация устройства для уведомлений
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null && auth.error != null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Нет связи с сервером',
          text: auth.error!,
          action: FilledButton(
            onPressed: () => ref.read(authProvider.notifier).restore(),
            child: const Text('Повторить'),
          ),
        ),
      );
    }
    // Регистрация: у нового клиента ещё нет имени — спрашиваем один раз.
    final needsName = auth.user != null &&
        !auth.user!.isAdmin &&
        auth.user!.name.isEmpty &&
        !ref.watch(nameSkipProvider);
    if (needsName) return const RegistrationScreen();
    return switch (ref.watch(roleProvider)) {
      AppRole.client => const ClientShell(),
      AppRole.admin => const AdminShell(),
      null => const LoginScreen(),
    };
  }
}
