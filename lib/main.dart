import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/app/app.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
    ),
  );
  await Bootstrap.init();
  await RecordoSupabase.init(); // no-op without dart-defines
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
