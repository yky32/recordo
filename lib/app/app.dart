import 'package:flutter/material.dart';
import 'package:recordo/app/router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/core/theme/theme_controller.dart';

class RecordoApp extends StatefulWidget {
  const RecordoApp({super.key});

  @override
  State<RecordoApp> createState() => _RecordoAppState();
}

class _RecordoAppState extends State<RecordoApp> {
  /// Stable router — do not recreate on theme change.
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final mode = ThemeController.instance.mode;
        final gen = ThemeController.instance.generation;
        return MaterialApp.router(
          title: 'Recordo',
          debugShowCheckedModeBanner: false,
          theme: RecordoTheme.light,
          darkTheme: RecordoTheme.dark,
          themeMode: mode,
          routerConfig: _router,
          // UberColors reads ThemeController (not Theme.of). GoRouter pages
          // otherwise keep old Element tree until something else setStates
          // (e.g. dragging the sheet). KeyedSubtree forces a real rebuild.
          builder: (context, child) {
            return KeyedSubtree(
              key: ValueKey('recordo-theme-$gen'),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
