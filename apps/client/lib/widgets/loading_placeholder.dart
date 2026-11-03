import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small spinner. With reduced motion, it becomes a still hourglass.
class VeloraSpinner extends StatelessWidget {
  const VeloraSpinner({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    if (VeloraMotion.reduced(context)) {
      return ExcludeSemantics(child: Icon(Icons.hourglass_top, size: size));
    }
    return SizedBox.square(
      dimension: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// A block that stands in for content while it loads. It fades slowly, and
/// holds still with reduced motion. Name what is loading with
/// [VeloraLoadingRegion].
class VeloraSkeleton extends StatefulWidget {
  const VeloraSkeleton({
    super.key,
    this.width,
    this.height,
    this.aspectRatio,
    this.radius = VeloraRadii.sm,
  });

  final double? width;
  final double? height;
  final double? aspectRatio;
  final double radius;

  @override
  State<VeloraSkeleton> createState() => _VeloraSkeletonState();
}

class _VeloraSkeletonState extends State<VeloraSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: 0.55,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VeloraMotion.reduced(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true, period: VeloraMotion.pulse ~/ 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget block = FadeTransition(
      opacity: _controller,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: VeloraColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
    final aspectRatio = widget.aspectRatio;
    return aspectRatio == null
        ? block
        : AspectRatio(aspectRatio: aspectRatio, child: block);
  }
}

/// Gives a group of placeholders one spoken description.
class VeloraLoadingRegion extends StatelessWidget {
  const VeloraLoadingRegion({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(child: child),
    );
  }
}
