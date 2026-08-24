import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/features/history/history_screen.dart';
import 'package:recordo/features/home/home_map_screen.dart';
import 'package:recordo/features/park_detail/park_detail_screen.dart';
import 'package:recordo/features/session/active_session_screen.dart';
import 'package:recordo/features/settings/report_park_screen.dart';
import 'package:recordo/features/settings/settings_screen.dart';

import 'package:recordo/app/routes.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeMapScreen(),
        routes: [
          // Query id so OSM ids with "/" work: /park?id=osm:way/123
          GoRoute(
            path: 'park',
            builder: (context, state) {
              final id = state.uri.queryParameters['id'] ?? '';
              return ParkDetailScreen(parkId: id);
            },
          ),
          // Legacy path form (simple ids only) — still decode if present
          GoRoute(
            path: 'park/:id',
            redirect: (context, state) {
              final raw = state.pathParameters['id'] ?? '';
              final id = Uri.decodeComponent(raw);
              return parkDetailLocation(id);
            },
          ),
          GoRoute(
            path: 'session',
            builder: (context, state) => const ActiveSessionScreen(),
          ),
          GoRoute(
            path: 'history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'report-park',
                builder: (context, state) => const ReportParkScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
