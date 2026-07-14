// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_spacing.dart';
import 'app_routes.dart';

/// Top-level scaffold that adapts navigation to screen size.
///
/// - Compact (< 600 dp): bottom NavigationBar (mobile)
/// - Medium (< 1200 dp): NavigationRail (tablet, small desktop)
/// - Expanded (>= 1200 dp): extended NavigationRail (desktop)
class AdaptiveScaffold extends StatelessWidget {
  final Widget child;
  final String location;
  const AdaptiveScaffold({super.key, required this.child, required this.location});

  static const _destinations = <_NavDest>[
    _NavDest(AppRoutes.home, 'Home', Icons.dashboard_outlined, Icons.dashboard),
    _NavDest(AppRoutes.scan, 'Connect', Icons.cable_outlined, Icons.cable),
    _NavDest(AppRoutes.live, 'Live', Icons.show_chart_outlined, Icons.show_chart),
    _NavDest(AppRoutes.recordings, 'Recordings', Icons.folder_outlined, Icons.folder),
    _NavDest(AppRoutes.console, 'Console', Icons.terminal_outlined, Icons.terminal),
    _NavDest(AppRoutes.deviceManager, 'Device Mgr', Icons.dns_outlined, Icons.dns),
    _NavDest(AppRoutes.developer, 'Developer', Icons.bug_report_outlined, Icons.bug_report),
    _NavDest(AppRoutes.settings, 'Settings', Icons.settings_outlined, Icons.settings),
  ];

  int _selectedIndex() {
    for (var i = 0; i < _destinations.length; i++) {
      if (_destinations[i].path == location) return i;
    }
    if (location.startsWith('/scan')) return 1;
    if (location.startsWith('/live')) return 2;
    if (location.startsWith('/recordings')) return 3;
    if (location.startsWith('/console')) return 4;
    if (location.startsWith('/device-manager')) return 5;
    if (location.startsWith('/developer')) return 6;
    if (location.startsWith('/settings')) return 7;
    return 0;
  }

  void _onSelect(BuildContext ctx, int idx) {
    ctx.go(_destinations[idx].path);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final expanded = width >= 1200;
    final selected = _selectedIndex();

    if (compact) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) => _onSelect(context, i),
          destinations: _destinations
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: expanded,
            minExtendedWidth: 220,
            selectedIndex: selected,
            onDestinationSelected: (i) => _onSelect(context, i),
            labelType: expanded
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: _BrandMark(extended: expanded),
            ),
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const _RailSeparator(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavDest {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _NavDest(this.path, this.label, this.icon, this.selectedIcon);
}

/// Boundary between the navigation rail and the content area.
///
/// A crisp 1px seam (so the two differently-shaded panels read as separate
/// zones) followed by a short shadow gradient that gives the body the feel of
/// sitting beneath the rail.
class _RailSeparator extends StatelessWidget {
  const _RailSeparator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1, color: scheme.outline),
        Container(
          width: 12,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ProtoCentral brand mark for the NavigationRail's leading slot.
///
/// Collapsed: round badge only (~40×40).
/// Extended: full white ProtoCentral wordmark logo above a distinct "OpenView"
/// app name + version. Minimalist — one brand lockup, one app name.
class _BrandMark extends StatelessWidget {
  final bool extended;
  const _BrandMark({required this.extended});

  static const _logoRound = 'assets/branding/pc-logo-round.png';
  static const _logoFullWhite = 'assets/proto-online-white.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!extended) {
      // Round badge on a theme-aware circular tile (asset has no alpha around
      // the disk, so clip to a circle and float it on a container tile).
      final badge = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: Image.asset(
            _logoRound,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'ProtoCentral',
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: badge,
      );
    }

    // NavigationRail.leading provides an unbounded width slot — give the
    // extended brand mark an explicit width so its children can lay out.
    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Full ProtoCentral logo (white wordmark + badge) for the dark rail.
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                _logoFullWhite,
                width: 176,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'ProtoCentral',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // OpenView — the app name, distinct from the brand wordmark by
            // colour (brand cyan), but using the app's standard UI typeface.
            Text(
              'OpenView',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: 0.5,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'v3.0 alpha',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
