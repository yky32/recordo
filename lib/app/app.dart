import 'package:flutter/material.dart';
import 'package:recordo/app/router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/core/theme/theme_controller.dart';

class RecordoApp extends StatelessWidget {
  const RecordoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Recordo',
          debugShowCheckedModeBanner: false,
          theme: RecordoTheme.light,
          darkTheme: RecordoTheme.dark,
          themeMode: ThemeController.instance.mode,
          routerConfig: buildRouter(),
        );
      },
    );
  }
}
