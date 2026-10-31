import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'home_shell.dart';
import 'theme.dart';

class BulmacaApp extends ConsumerWidget {
  const BulmacaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider);
    final s = c.settings;
    final theme = buildTheme(s.paper);
    return MaterialApp(
      title: 'Bulmaca Gazetesi',
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final system = mq.textScaler.scale(100) / 100;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(system * s.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: !c.ready
          ? const _Splash()
          : c.fatalError != null
          ? _FatalScreen(message: c.fatalError!)
          : const HomeShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _FatalScreen extends StatelessWidget {
  const _FatalScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bulmaca Gazetesi', style: serifStyle(pal.ink, 30)),
              const SizedBox(height: 16),
              Icon(Icons.error_outline, color: pal.bad, size: 32),
              const SizedBox(height: 8),
              Text(message, style: sansStyle(pal.ink, 17, h: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
