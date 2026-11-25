import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/pass_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'pesapal_view.dart';

/// "UGX 18,000".
String formatUgx(BuildContext context, int amount) => context.l10n.passPrice(
  NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag())
      .format(amount),
);

/// "19 Nov 2026, 14:05", in the viewer's own time.
String formatPassEnd(BuildContext context, DateTime at) {
  final dates = MaterialLocalizations.of(context);
  final local = at.toLocal();
  return '${dates.formatMediumDate(local)}, '
      '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

/// "19 Nov 2026".
String formatDay(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatMediumDate(at.toLocal());

/// "12 days left", "5 hours left" or "20 minutes left".
String timeLeft(AppLocalizations l, Duration left) {
  if (left.inDays >= 1) return l.timeLeftDays(left.inDays);
  if (left.inHours >= 1) return l.timeLeftHours(left.inHours);
  return l.timeLeftMinutes(left.inMinutes < 1 ? 1 : left.inMinutes);
}

/// A legacy pass's name, Step 10C. The six tiers carry their own names.
String passName(AppLocalizations l, String id, int days) => switch (id) {
  'day' => l.passDay,
  'week' => l.passWeek,
  'month' => l.passMonth,
  _ => l.passDays(days),
};

String passFailureMessage(AppLocalizations l, PassFailure failure) =>
    switch (failure) {
      PassFailure.signedOut => l.passSignInNeeded,
      PassFailure.notFound => l.somethingWentWrong,
      PassFailure.notForSale => l.passNotForSale,
      PassFailure.needsContact => l.phoneNotValid,
      PassFailure.tooMany => l.tooManyAttempts,
      PassFailure.unavailable => l.paymentsUnavailable,
      PassFailure.unreachable => l.unreachable,
      PassFailure.unexpected => l.somethingWentWrong,
    };

// --- Account: My membership --------------------------------------------------

/// The Account tab's "My membership": the plan running now, its dates, time
/// left and allowances, any plan queued after it, and renewing or changing
/// plan. A payment shows as made only once the API has confirmed it with
/// Pesapal, never because the browser came back from Pesapal's page.
class MembershipSection extends StatefulWidget {
  const MembershipSection({
    super.key,
    this.clock = DateTime.now,
    this.titled = true,
  });

  final DateTime Function() clock;

  /// False where the page's own heading already names it.
  final bool titled;

  @override
  State<MembershipSection> createState() => _MembershipSectionState();
}

class _MembershipSectionState extends State<MembershipSection> {
  PassStatus? _status;
  PassFailure? _failure;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final api = PlaybackScope.of(context);
    if (api == null) return;
    setState(() => _failure = null);
    try {
      final status = await api.myPass();
      if (mounted) setState(() => _status = status);
    } on PassException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  Future<void> _choose() async {
    final bought = await BuyPassScreen.open(context);
    if (bought && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (PlaybackScope.of(context) == null) return const SizedBox.shrink();
    final l = context.l10n;
    final status = _status;
    final failure = _failure;
    final Widget body;
    if (failure != null) {
      body = ErrorState(
        title: l.passCouldNotLoad,
        message: passFailureMessage(l, failure),
        onRetry: _load,
      );
    } else if (status == null) {
      body = const _SectionSkeleton(lines: 3);
    } else {
      body = _membership(context, status);
    }
    return AccountCard(
      title: widget.titled ? l.myMembership : null,
      child: body,
    );
  }

  Widget _membership(BuildContext context, PassStatus status) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = VeloraPalette.of(context);
    final current = status.current;
    final badges = Wrap(
      spacing: VeloraSpacing.xs,
      runSpacing: VeloraSpacing.xs,
      children: [
        if (status.active)
          StatusBadge(
            label: l.membershipActive,
            tone: StatusTone.success,
            icon: Icons.check_circle_outline,
          )
        else
          StatusBadge(label: l.membershipNone, tone: StatusTone.neutral),
        if (status.checking)
          StatusBadge(
            label: l.membershipChecking,
            tone: StatusTone.info,
            icon: Icons.hourglass_top,
          ),
      ],
    );
    if (!status.active || current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.sm,
        children: [
          badges,
          Text(l.membershipNoneHelp),
          if (status.checking) Text(l.passChecking),
          VeloraButton(
            label: l.choosePlan,
            icon: Icons.workspace_premium_outlined,
            onPressed: _choose,
          ),
        ],
      );
    }
    final left = current.endsAt.difference(widget.clock().toUtc());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.sm,
      children: [
        badges,
        Text(
          current.planName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          timeLeft(l, left.isNegative ? Duration.zero : left),
          style: theme.textTheme.titleMedium?.copyWith(
            color: palette.accentText,
          ),
        ),
        Wrap(
          spacing: VeloraSpacing.lg,
          runSpacing: VeloraSpacing.xs,
          children: [
            _Fact(
              Icons.event_available_outlined,
              l.membershipStarted(formatDay(context, current.startsAt)),
            ),
            _Fact(
              Icons.event_busy_outlined,
              l.membershipExpires(formatPassEnd(context, current.endsAt)),
            ),
            _Fact(Icons.devices_outlined, l.planDevices(current.maxDevices)),
            _Fact(Icons.tv_outlined, l.planStreams(current.maxStreams)),
          ],
        ),
        for (final next in status.queued)
          _Fact(
            Icons.schedule,
            l.membershipQueued(
              next.planName,
              formatDay(context, next.startsAt),
            ),
          ),
        if (status.checking) Text(l.passChecking),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          children: [
            VeloraButton(
              label: l.renewPlan,
              icon: Icons.autorenew,
              onPressed: _choose,
            ),
            VeloraButton(
              label: l.changePlan,
              icon: Icons.swap_horiz,
              variant: VeloraButtonVariant.secondary,
              onPressed: _choose,
            ),
          ],
        ),
      ],
    );
  }
}

/// A card on the Account tab, titled unless the page's heading already
/// names it.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            if (title case final title?)
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: VeloraSpacing.xs,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        Flexible(child: Text(text)),
      ],
    );
  }
}

/// Grey lines while a section loads.
class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return VeloraLoadingRegion(
      label: context.l10n.loading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.xs,
        children: [
          for (var i = 0; i < lines; i++)
            VeloraSkeleton(width: i == 0 ? 120 : 260, height: 16),
        ],
      ),
    );
  }
}

// --- Choosing and paying -----------------------------------------------------

enum _Phase {
  loading,
  choosing,
  starting,
  waiting,
  failed,
  gaveUp,
  timedOut,
  ready,
}

/// Where the viewer pays: Pesapal's page inside the app, Pesapal's page in
/// the browser when they ask for that, or neither once Pesapal has sent them
/// back and the payment is being confirmed.
enum _PayIn { app, browser, returned }

/// Choosing a plan, paying on Pesapal's page inside the app, and waiting
/// until the API confirms it. Answers true, when popped, once a plan is
/// ready.
class BuyPassScreen extends StatefulWidget {
  const BuyPassScreen({super.key});

  /// Pesapal's page inside the app. Tests replace it.
  static PesapalViewBuilder paymentView = platformPesapalView;

  /// Opens Pesapal's page outside the app, when the viewer asks to pay in
  /// their browser instead: a new tab on the web, the browser on Android.
  /// Tests replace it.
  static Future<bool> Function(Uri page) openPage = (page) => launchUrl(
    page,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );

  /// How often the payment is checked while the viewer pays, and for how
  /// long.
  static Duration checkEvery = const Duration(seconds: 3);
  static Duration checkFor = const Duration(minutes: 15);

  static Future<bool> open(BuildContext context) async {
    final bought = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const BuyPassScreen()));
    return bought ?? false;
  }

  @override
  State<BuyPassScreen> createState() => _BuyPassScreenState();
}

class _BuyPassScreenState extends State<BuyPassScreen> {
  _Phase _phase = _Phase.loading;
  List<PassPlan> _plans = const [];
  bool _hasPlan = false;
  String? _message;
  String? _buying;
  Checkout? _checkout;
  _PayIn _payIn = _PayIn.app;
  DateTime? _endsAt;
  Timer? _timer;
  DateTime? _deadline;
  bool _checking = false;

  /// A check was asked for while one was running: run another once it ends.
  bool _checkAgain = false;

  /// Pesapal's last try failed while the viewer is on its page here.
  bool _lastTryFailed = false;
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _started = false;

  PlaybackApi? get _api => PlaybackScope.of(context);
  String? get _email => AuthScope.of(context)?.email;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadPlans();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    final api = _api;
    setState(() {
      _phase = _Phase.loading;
      _message = null;
    });
    if (api == null) {
      _fail(context.l10n.paymentsUnavailable);
      return;
    }
    try {
      final plans = await api.passPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _phase = _Phase.choosing;
      });
    } on PassException catch (error) {
      _fail(passFailureMessage(context.l10n, error.failure));
      return;
    }
    // Whether a new plan will queue behind one already running.
    try {
      final status = await api.myPass();
      if (mounted) setState(() => _hasPlan = status.active);
    } on PassException {
      // Not needed to choose.
    }
  }

  void _fail(String message, {_Phase phase = _Phase.choosing}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _phase = phase;
      _buying = null;
    });
  }

  Future<void> _buy(PassPlan plan) async {
    final api = _api;
    if (api == null || _buying != null) return;
    final email = _email;
    if (email == null && !(_form.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    setState(() {
      _buying = plan.id;
      _phase = _Phase.starting;
      _message = null;
    });
    try {
      final checkout = await api.checkout(
        plan.id,
        email: email,
        phone: email == null ? _phone.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _payIn = _PayIn.app;
        _phase = _Phase.waiting;
        _buying = null;
      });
      _deadline = DateTime.now().add(BuyPassScreen.checkFor);
      _scheduleCheck();
    } on PassException catch (error) {
      _fail(passFailureMessage(l, error.failure));
    }
  }

  /// Pesapal's page again, inside the app.
  void _payHere() {
    if (_checkout == null) return;
    setState(() {
      _payIn = _PayIn.app;
      _message = null;
      _lastTryFailed = false;
      _phase = _Phase.waiting;
    });
  }

  /// Pesapal has sent the viewer back: check now, not in a few seconds.
  void _returned() {
    if (!mounted || _phase != _Phase.waiting) return;
    setState(() => _payIn = _PayIn.returned);
    _timer?.cancel();
    _check();
  }

  Future<void> _openPesapal() async {
    final checkout = _checkout;
    if (checkout == null) return;
    setState(() {
      _payIn = _PayIn.browser;
      _message = null;
      if (_phase == _Phase.failed) _phase = _Phase.waiting;
    });
    var opened = false;
    try {
      opened = await BuyPassScreen.openPage(checkout.paymentPage);
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() {
        _payIn = _PayIn.app;
        _message = context.l10n.couldNotOpenPesapal;
      });
    }
  }

  void _scheduleCheck() {
    _timer?.cancel();
    _timer = Timer(BuyPassScreen.checkEvery, _check);
  }

  Future<void> _check() async {
    final api = _api;
    final checkout = _checkout;
    if (api == null || checkout == null || !mounted) return;
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    PaymentCheck? found;
    try {
      found = await api.payment(checkout.paymentId);
    } on PassException {
      found = null;
    } finally {
      _checking = false;
    }
    if (!mounted) return;
    switch (found?.state) {
      case PaymentState.completed:
        _timer?.cancel();
        setState(() {
          _endsAt = found!.passEndsAt;
          _phase = _Phase.ready;
        });
        return;
      case PaymentState.abandoned ||
          PaymentState.reversed ||
          PaymentState.refunded:
        _timer?.cancel();
        setState(() => _phase = _Phase.gaveUp);
        return;
      case PaymentState.failed:
        // On Pesapal's page here, the viewer can try again with the same
        // order: say it failed above the page rather than take it away.
        setState(() {
          if (_payIn == _PayIn.app) {
            _lastTryFailed = true;
          } else {
            _phase = _Phase.failed;
          }
        });
      default:
        if (_phase == _Phase.failed || _lastTryFailed) {
          setState(() {
            _lastTryFailed = false;
            if (_phase == _Phase.failed) _phase = _Phase.waiting;
          });
        }
    }
    final deadline = _deadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      setState(() => _phase = _Phase.timedOut);
      return;
    }
    if (_checkAgain) {
      _checkAgain = false;
      _timer?.cancel();
      unawaited(_check());
    } else {
      _scheduleCheck();
    }
  }

  void _chooseAgain() {
    _timer?.cancel();
    setState(() {
      _checkout = null;
      _message = null;
      _lastTryFailed = false;
      _checkAgain = false;
      _phase = _Phase.choosing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final wide = _phase == _Phase.loading || _phase == _Phase.choosing;
    final paying = _phase == _Phase.waiting || _phase == _Phase.failed;
    return Scaffold(
      appBar: AppBar(title: Text(l.choosePlanTitle)),
      body: ScreenBody(
        heading: paying ? l.payingTitle : l.choosePlanTitle,
        maxWidth: wide ? VeloraLayout.browseWidth : VeloraLayout.readingWidth,
        children: [
          ...switch (_phase) {
            _Phase.loading => [
              Text(l.choosePlanIntro),
              const _PlanGrid.skeleton(),
            ],
            _Phase.choosing || _Phase.starting => _choosing(l),
            _Phase.waiting when _payIn == _PayIn.app => _payingHere(l),
            _Phase.waiting => [
              if (_payIn == _PayIn.browser)
                EmptyState(
                  icon: Icons.open_in_new,
                  title: l.finishPaying,
                  message: l.finishPayingHelp,
                  action: _waitingActions(l),
                )
              else
                EmptyState(
                  icon: Icons.hourglass_top,
                  title: l.checkingPayment,
                  message: l.confirmingPaymentHelp,
                  action: _waitingActions(l),
                ),
              Center(
                child: VeloraLoadingRegion(
                  label: l.checkingPayment,
                  child: const VeloraSpinner(size: 24),
                ),
              ),
            ],
            _Phase.failed => [
              ErrorState(
                title: l.paymentFailedTitle,
                message: l.paymentFailedHelp,
                onRetry: _payHere,
                retryLabel: l.tryPayingAgain,
              ),
              Center(
                child: TextButton(
                  onPressed: _chooseAgain,
                  child: Text(l.choosePlan),
                ),
              ),
            ],
            _Phase.gaveUp => [
              ErrorState(
                title: l.paymentFailedTitle,
                message: l.paymentGivenUp,
                onRetry: _chooseAgain,
                retryLabel: l.choosePlan,
              ),
            ],
            _Phase.timedOut => [
              EmptyState(
                icon: Icons.hourglass_bottom,
                title: l.stillWaitingTitle,
                message: l.stillWaitingHelp,
                action: VeloraButton(
                  label: l.checkAgain,
                  icon: Icons.refresh,
                  onPressed: () {
                    _deadline = DateTime.now().add(BuyPassScreen.checkFor);
                    setState(() => _phase = _Phase.waiting);
                    _check();
                  },
                ),
              ),
            ],
            _Phase.ready => [
              EmptyState(
                icon: Icons.check_circle_outline,
                title: l.passReadyTitle,
                message: switch (_endsAt) {
                  final ends? => l.passReadyUntil(formatPassEnd(context, ends)),
                  null => l.passReadyTitle,
                },
                action: VeloraButton(
                  label: l.carryOnWatching,
                  icon: Icons.play_arrow,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          },
          if (_message case final message?)
            Semantics(liveRegion: true, child: Text(message)),
        ],
      ),
    );
  }

  /// Pesapal's page inside the app, with a way out to the browser should it
  /// not work here. The buttons come first, and the page always leaves a
  /// strip of the screen free: it takes every drag inside it, so a short
  /// screen must still be able to scroll back up to them.
  List<Widget> _payingHere(AppLocalizations l) {
    final checkout = _checkout!;
    final media = MediaQuery.of(context);
    final screen =
        media.size.height - media.padding.vertical - kToolbarHeight;
    final height = (screen - 120).clamp(200.0, 760.0);
    final theme = Theme.of(context);
    return [
      Text(l.payHereHelp),
      if (_lastTryFailed)
        Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(VeloraRadii.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(VeloraSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: VeloraSpacing.xs,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  Expanded(
                    child: Text(
                      l.lastTryFailedHere,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      Wrap(
        spacing: VeloraSpacing.sm,
        runSpacing: VeloraSpacing.sm,
        alignment: WrapAlignment.center,
        children: [
          VeloraButton(
            label: l.payInBrowser,
            icon: Icons.open_in_new,
            variant: VeloraButtonVariant.secondary,
            onPressed: _openPesapal,
          ),
          TextButton(
            onPressed: _chooseAgain,
            child: Text(_lastTryFailed ? l.choosePlan : l.cancel),
          ),
        ],
      ),
      SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VeloraColors.surface,
            border: Border.all(color: VeloraColors.outlineSubtle),
            borderRadius: BorderRadius.circular(VeloraRadii.lg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VeloraRadii.lg),
            child: BuyPassScreen.paymentView(
              context,
              checkout.paymentPage,
              _returned,
            ),
          ),
        ),
      ),
      Row(
        spacing: VeloraSpacing.xs,
        children: [
          Icon(
            Icons.lock_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              l.paymentSecureNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _waitingActions(AppLocalizations l) => Wrap(
    spacing: VeloraSpacing.sm,
    runSpacing: VeloraSpacing.sm,
    alignment: WrapAlignment.center,
    children: [
      VeloraButton(label: l.checkAgain, icon: Icons.refresh, onPressed: _check),
      VeloraButton(
        label: l.payHereAgain,
        icon: Icons.payment,
        variant: VeloraButtonVariant.secondary,
        onPressed: _payHere,
      ),
      if (_payIn == _PayIn.browser)
        TextButton(onPressed: _openPesapal, child: Text(l.openPesapalAgain)),
      TextButton(onPressed: _chooseAgain, child: Text(l.cancel)),
    ],
  );

  List<Widget> _choosing(AppLocalizations l) {
    if (_plans.isEmpty) {
      return [
        EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: l.noPassesForSale,
          message: l.paymentsUnavailable,
          action: VeloraButton(
            label: l.tryAgain,
            icon: Icons.refresh,
            onPressed: _loadPlans,
          ),
        ),
      ];
    }
    final theme = Theme.of(context);
    return [
      Text(l.choosePlanIntro),
      if (_hasPlan) _Note(icon: Icons.schedule, text: l.planQueuedNote),
      if (_email == null)
        Form(
          key: _form,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: VeloraLayout.formWidth),
            child: VeloraTextField(
              label: l.phoneForPayment,
              helperText: l.phoneForPaymentHelp,
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: (value) =>
                  RegExp(r'^\+?[0-9]{9,15}$')
                      .hasMatch((value ?? '').replaceAll(RegExp(r'[\s-]'), ''))
                  ? null
                  : l.phoneNotValid,
            ),
          ),
        ),
      _PlanGrid(
        plans: _plans,
        buying: _buying,
        onBuy: _phase == _Phase.starting ? null : _buy,
      ),
      Row(
        spacing: VeloraSpacing.xs,
        children: [
          Icon(
            Icons.lock_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              l.paymentSecureNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.infoContainer,
        borderRadius: BorderRadius.circular(VeloraRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xs,
          children: [
            Icon(icon, size: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// The plans as cards: three across on a wide screen, two on a tablet, and
/// stacked on a phone. Cards in a row share one height.
class _PlanGrid extends StatelessWidget {
  const _PlanGrid({required this.plans, required this.buying, this.onBuy})
    : skeleton = false;

  const _PlanGrid.skeleton()
    : plans = const [],
      buying = null,
      onBuy = null,
      skeleton = true;

  final List<PassPlan> plans;
  final String? buying;
  final ValueChanged<PassPlan>? onBuy;
  final bool skeleton;

  static int columnsFor(double width) {
    if (width >= 900) return 3;
    if (width >= 560) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final count = skeleton ? 6 : plans.length;
        final cards = [
          for (var i = 0; i < count; i++)
            skeleton
                ? const _PlanSkeleton()
                : PlanCard(
                    key: ValueKey('plan-${plans[i].id}'),
                    plan: plans[i],
                    busy: buying == plans[i].id,
                    onBuy: onBuy == null ? null : () => onBuy!(plans[i]),
                  ),
        ];
        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.md,
          children: [
            for (var start = 0; start < cards.length; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.md,
                  children: [
                    for (var i = start; i < start + columns; i++)
                      Expanded(
                        child: i < cards.length
                            ? cards[i]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
        return skeleton
            ? VeloraLoadingRegion(label: context.l10n.loading, child: grid)
            : grid;
      },
    );
  }
}

class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.sm,
          children: const [
            VeloraSkeleton(width: 120, height: 18),
            VeloraSkeleton(width: 160, height: 32),
            VeloraSkeleton(width: 200, height: 14),
            VeloraSkeleton(width: 180, height: 14),
            SizedBox(height: VeloraSpacing.sm),
            VeloraSkeleton(height: 44),
          ],
        ),
      ),
    );
  }
}

/// One plan: its name, price, length, devices and screens, what every plan
/// includes, and a button to pay. The featured plan is outlined in the
/// accent with a small badge, and nothing more.
class PlanCard extends StatefulWidget {
  const PlanCard({
    super.key,
    required this.plan,
    this.onBuy,
    this.busy = false,
  });

  final PassPlan plan;
  final VoidCallback? onBuy;
  final bool busy;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final plan = widget.plan;
    final price = formatUgx(context, plan.priceUgx);
    final duration = l.planDays(plan.days);
    final featured = plan.featured;
    final lift = _hovered && !VeloraMotion.reduced(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: VeloraMotion.of(context, VeloraMotion.standard),
        curve: VeloraMotion.curve,
        transform: Matrix4.translationValues(0, lift ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: featured ? VeloraColors.surfaceRaised : VeloraColors.surface,
          borderRadius: BorderRadius.circular(VeloraRadii.lg),
          border: Border.all(
            color: featured
                ? VeloraColors.accent
                : (_hovered
                      ? VeloraColors.outline
                      : VeloraColors.outlineSubtle),
            width: featured ? VeloraStroke.focus : VeloraStroke.hairline,
          ),
          boxShadow: lift || featured ? VeloraShadows.raised : null,
        ),
        child: Semantics(
          container: true,
          label: l.planCardLabel(plan.displayName, price, duration),
          child: Padding(
            padding: const EdgeInsets.all(VeloraSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (featured)
                      StatusBadge(
                        label: l.mostPopular,
                        tone: StatusTone.info,
                        icon: Icons.star_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: VeloraSpacing.sm),
                Text(
                  price,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: VeloraColors.textPrimary,
                  ),
                ),
                Text(
                  duration,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: VeloraColors.textSecondary,
                  ),
                ),
                if (plan.description case final text?) ...[
                  const SizedBox(height: VeloraSpacing.xs),
                  Text(text, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: VeloraSpacing.md),
                Divider(color: VeloraColors.outlineSubtle, height: 1),
                const SizedBox(height: VeloraSpacing.md),
                _Benefit(
                  Icons.devices_outlined,
                  l.planDevices(plan.maxDevices),
                ),
                _Benefit(Icons.tv_outlined, l.planStreams(plan.maxStreams)),
                _Benefit(Icons.movie_outlined, l.planBenefitCatalogue),
                _Benefit(Icons.language, l.planBenefitPlatforms),
                _Benefit(Icons.block, l.planBenefitNoRenewal),
                const Spacer(),
                const SizedBox(height: VeloraSpacing.md),
                VeloraButton(
                  label: l.payPlan(price),
                  icon: Icons.lock_outline,
                  expand: true,
                  isLoading: widget.busy,
                  loadingLabel: l.startingPayment,
                  variant: featured
                      ? VeloraButtonVariant.primary
                      : VeloraButtonVariant.secondary,
                  onPressed: widget.onBuy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: VeloraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.xs,
        children: [
          Icon(icon, size: 18, color: palette.accentText),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
