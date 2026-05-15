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
    if (location.startsWith('/settings')) return 5;
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
          const VerticalDivider(width: 1),
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

/// ProtoCentral brand mark for the NavigationRail's leading slot.
///
/// Collapsed: round logo only (~40×40).
/// Extended: round logo + "OpenView · v3.0 alpha" wordmark.
class _BrandMark extends StatelessWidget {
  final bool extended;
  const _BrandMark({required this.extended});

  static const _logoRound = 'assets/branding/pc-logo-round.png';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // The asset is RGB (no alpha) with black corners around a pale-blue disk.
    // Clip to a circle so the black corners never show, then wrap in a
    // theme-aware circular tile so the logo has consistent contrast in
    // both light and dark themes:
    //   - dark surface → tile lifts the logo from the dark background
    //   - light surface → tile gives the pale-blue disk visible weight
    final logo = Container(
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

    if (!extended) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: logo,
      );
    }

    // NavigationRail.leading provides an unbounded width slot — give the
    // extended brand mark an explicit width so its Row + Expanded can lay out.
    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            logo,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'OpenView',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    'by ProtoCentral · v3.0 alpha',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
