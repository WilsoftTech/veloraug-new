import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The VeloraUG name with its two-stroke V. This is the first version of the
/// identity, awaiting the owner's visual approval.
class VeloraWordmark extends StatelessWidget {
  const VeloraWordmark({super.key, this.markSize = 24});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.25);
    return Semantics(
      label: 'VeloraUG',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: Size.square(markSize), painter: _MarkPainter()),
          const SizedBox(width: VeloraSpacing.xs),
          Flexible(
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'Velora'),
                  TextSpan(
                    text: 'UG',
                    style: TextStyle(color: VeloraColors.accentText),
                  ),
                ],
              ),
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = Path()
      ..moveTo(w * 0.04, h * 0.14)
      ..lineTo(w * 0.32, h * 0.14)
      ..lineTo(w * 0.60, h * 0.88)
      ..lineTo(w * 0.40, h * 0.88)
      ..close();
    final right = Path()
      ..moveTo(w * 0.68, h * 0.14)
      ..lineTo(w * 0.96, h * 0.14)
      ..lineTo(w * 0.66, h * 0.88)
      ..lineTo(w * 0.53, h * 0.54)
      ..close();
    canvas
      ..drawPath(left, Paint()..color = VeloraColors.textPrimary)
      ..drawPath(right, Paint()..color = VeloraColors.accentText);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
