// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/app_info_controller.dart';
import '../../theme/app_spacing.dart';

/// Global status / brand footer shown under every main-content screen.
///
/// Layout (single line, ~28–32 px tall):
///   `OpenView 3.0.0`  ·  `ProtoCentral Electronics`
///
/// Interactions:
/// - **Long-press** the app/version label → copy full version to clipboard.
/// - **Tap** the company name → open https://protocentral.com.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  static final Uri _companyUri = Uri.parse(AppInfoController.companyUrl);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = context.watch<AppInfoController>();
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.2,
      height: 1.1,
    );
    final appStyle = labelStyle?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            // App name + version (long-press to copy).
            Flexible(
              child: Tooltip(
                message: 'Long-press to copy version',
                waitDuration: const Duration(milliseconds: 600),
                child: InkWell(
                  onLongPress: () => _copyVersion(context, info),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: AppInfoController.appName,
                            style: appStyle,
                          ),
                          TextSpan(
                            text: '  ${info.versionLabel}',
                            style: labelStyle,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('·', style: labelStyle),
            ),
            // Company (tap to open website).
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: AppInfoController.companyUrl,
                  waitDuration: const Duration(milliseconds: 600),
                  child: InkWell(
                    onTap: () => _openCompany(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Text(
                        AppInfoController.companyName,
                        style: labelStyle?.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor:
                              scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _copyVersion(
      BuildContext context, AppInfoController info) async {
    final text = info.fullVersionString;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> _openCompany(BuildContext context) async {
    try {
      final ok = await launchUrl(
        _companyUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open protocentral.com'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open link: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
