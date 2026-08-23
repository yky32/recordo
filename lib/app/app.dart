import 'package:flutter/material.dart';
import 'package:recordo/app/router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';

class RecordoApp extends StatelessWidget {
  const RecordoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Recordo',
      debugShowCheckedModeBanner: false,
      theme: RecordoTheme.dark,
      routerConfig: buildRouter(),
    );
  }
}
