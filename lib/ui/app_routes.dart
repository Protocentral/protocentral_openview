import 'package:go_router/go_router.dart';

import 'adaptive_scaffold.dart';
import 'screens/console_screen.dart';
import 'screens/developer_screen.dart';
import 'screens/device_manager/device_manager_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/replay_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const scan = '/scan';
  static const live = '/live';
  static const recordings = '/recordings';
  static const replay = '/replay';
  static const console = '/console';
  static const deviceManager = '/device-manager';
  static const developer = '/developer';
  static const settings = '/settings';

  static final router = GoRouter(
    initialLocation: home,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) =>
            AdaptiveScaffold(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: home, builder: (_, __) => const HomeScreen()),
          GoRoute(path: scan, builder: (_, __) => const ScanScreen()),
          GoRoute(path: live, builder: (_, __) => const LiveScreen()),
          GoRoute(
              path: recordings, builder: (_, __) => const RecordingsScreen()),
          GoRoute(
            path: replay,
            builder: (ctx, state) {
              final filePath =
                  state.uri.queryParameters['file'] ?? state.extra as String?;
              if (filePath == null || filePath.isEmpty) {
                // No file → bounce to the recordings list.
                return const RecordingsScreen();
              }
              return ReplayScreen(filePath: filePath);
            },
          ),
          GoRoute(path: console, builder: (_, __) => const ConsoleScreen()),
          GoRoute(
              path: deviceManager,
              builder: (_, __) => const DeviceManagerScreen()),
          GoRoute(
              path: developer, builder: (_, __) => const DeveloperScreen()),
          GoRoute(path: settings, builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
  );
}
