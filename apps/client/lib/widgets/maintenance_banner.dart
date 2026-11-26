import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// The notice viewers see while admins have turned maintenance on, with
/// their message. Admins see the same in Settings, as a preview.
class MaintenanceBanner extends StatelessWidget {
  const MaintenanceBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        decoration: BoxDecoration(
          color: VeloraColors.warningContainer,
          borderRadius: BorderRadius.circular(VeloraRadii.sm),
          border: Border.all(color: VeloraColors.warning),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.sm,
          children: [
            const Icon(Icons.construction, color: VeloraColors.warning),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: VeloraSpacing.xxs,
                children: [
                  Text(l.maintenanceTitle, style: theme.textTheme.titleSmall),
                  Text(message.isEmpty ? l.maintenanceDefault : message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
