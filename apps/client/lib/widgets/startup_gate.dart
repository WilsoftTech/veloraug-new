import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../security/app_lock.dart';
import '../theme/tokens.dart';
import 'brand.dart';

/// The longest the app waits, at launch, for the saved sign-in to be read
/// before showing the app anyway. Reading it is usually instant; renewing
/// an expired token can wait on the network, and the app never does.
const Duration startupMaxWait = Duration(seconds: 2);

/// The mark's size on the startup screen, matching web/index.html.
const double startupMarkSize = 96;

/// The ring's size around the mark, matching web/index.html.
const double startupRingSize = 132;

/// Shows the branded startup screen while the saved sign-in and App lock's
/// setting are read, for at most [startupMaxWait], then [child]. Nothing else is waited for:
/// Home, Search and Downloads load on their own and work while the
/// catalogue, the network or storage is slow. There is no minimum time, so
/// a quick start shows the app at once.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.child,
    this.maxWait = startupMaxWait,
  });

  final Widget child;
  final Duration maxWait;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _done = false;
  Timer? _limit;

  @override
  void initState() {
    super.initState();
    _limit = Timer(widget.maxWait, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _limit?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) {
      final auth = AuthScope.of(context);
      final lock = AppLockScope.of(context);
      final restoring = auth != null && auth.status == AuthStatus.restoring;
      final lockPending = lock != null && !lock.loaded;
      if (!restoring && !lockPending) {
        _done = true;
        _limit?.cancel();
      }
    }
    if (_done) return widget.child;
    return const StartupScreen();
  }
}

/// The VeloraUG mark on the app's canvas, with a ring turning around it,
/// as the web page shows before Flutter starts. With reduced motion the
/// ring holds still.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VeloraColors.canvas,
      child: Center(
        child: Semantics(
          label: context.l10n.startingApp,
          liveRegion: true,
          container: true,
          child: const ExcludeSemantics(
            child: SizedBox.square(
              dimension: startupRingSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: BrandRing()),
                  VeloraMark(size: startupMarkSize),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin ring with an accent arc that turns, once every 1.2 seconds. With
/// reduced motion, a still, full ring.
class BrandRing extends StatefulWidget {
  const BrandRing({super.key, this.strokeWidth = 3});

  final double strokeWidth;

  @override
  State<BrandRing> createState() => _BrandRingState();
}

class _BrandRingState extends State<BrandRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VeloraMotion.reduced(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = VeloraMotion.reduced(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            turn: _turn.value,
            still: still,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.turn,
    required this.still,
    required this.strokeWidth,
  });

  final double turn;
  final bool still;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = VeloraColors.outlineSubtle;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    if (still) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = VeloraColors.accentText;
    canvas.drawArc(
      rect,
      turn * 2 * math.pi - math.pi / 2,
      math.pi / 2,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turn != turn || old.still != still || old.strokeWidth != strokeWidth;
}
