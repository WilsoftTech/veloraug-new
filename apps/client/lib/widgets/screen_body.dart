import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Scrollable, width-limited layout shared by every screen, so text stays
/// readable on wide screens and nothing overflows on small ones.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.heading,
    required this.children,
    this.intro,
    this.status,
    this.hero = false,
    this.maxWidth = VeloraLayout.readingWidth,
  });

  final String heading;
  final List<Widget> children;

  /// A sentence or two below the heading.
  final String? intro;

  /// A small element below the intro, such as a status badge.
  final Widget? status;

  /// Gives the heading the larger treatment used on the Home screen.
  final bool hero;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final header = _Header(
      heading: heading,
      intro: intro,
      status: status,
      hero: hero,
    );

    return SingleChildScrollView(
      // Only the sides change with the screen's width, so content starts at
      // the same height on every layout.
      padding: EdgeInsets.symmetric(
        horizontal: VeloraLayout.gutterFor(screenWidth),
        vertical: VeloraSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: VeloraSpacing.lg,
            children: [
              if (hero) _HeroPanel(child: header) else header,
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.heading,
    required this.intro,
    required this.status,
    required this.hero,
  });

  final String heading;
  final String? intro;
  final Widget? status;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intro = this.intro;
    final status = this.status;
    final isCompact =
        MediaQuery.sizeOf(context).width < VeloraLayout.mediumBreakpoint;
    final headingStyle = !hero
        ? theme.textTheme.headlineLarge
        : (isCompact
              ? theme.textTheme.displaySmall
              : theme.textTheme.displayMedium);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(heading, style: headingStyle)),
        if (intro != null) ...[
          const SizedBox(height: VeloraSpacing.sm),
          Text(
            intro,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: VeloraSpacing.md),
          status,
        ],
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final side =
        MediaQuery.sizeOf(context).width < VeloraLayout.mediumBreakpoint
        ? VeloraSpacing.lg
        : VeloraSpacing.xxl;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeloraRadii.lg),
        border: Border.all(color: VeloraColors.outlineSubtle),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [VeloraColors.infoContainer, VeloraColors.surface],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: side,
          vertical: VeloraSpacing.xxl,
        ),
        child: child,
      ),
    );
  }
}
