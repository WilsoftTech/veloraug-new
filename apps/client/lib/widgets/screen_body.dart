import 'package:flutter/material.dart';

/// Scrollable, width-limited layout shared by every screen, so text stays
/// readable on wide screens and nothing overflows on small ones.
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.heading, required this.children});

  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w600);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(heading, style: headingStyle),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
