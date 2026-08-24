import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/app/app.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await Bootstrap.init();
  await ThemeController.instance.hydrate();
  await RecordoSupabase.init();
  _syncSystemUi();
  ThemeController.instance.addListener(_syncSystemUi);

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ParkCatalogCubit()..load()),
        BlocProvider(create: (_) => SessionCubit()..hydrate()),
      ],
      child: const RecordoApp(),
    ),
  );
}

void _syncSystemUi() {
  final dark = ThemeController.instance.isDark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? Colors.black : const Color(0xFFF3F3F3),
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    ),
  );
}
