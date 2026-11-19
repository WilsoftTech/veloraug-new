import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/pass_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';

/// "UGX 2,000".
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

String passName(AppLocalizations l, String id, int days) => switch (id) {
  'day' => l.passDay,
  'week' => l.passWeek,
  'month' => l.passMonth,
  _ => l.passDays(days),
};

String passFailureMessage(AppLocalizations l, PassFailure failure) =>
    switch (failure) {
      PassFailure.signedOut => l.passSignInNeeded,
      PassFailure.notForSale => l.passNotForSale,
      PassFailure.needsContact => l.phoneNotValid,
      PassFailure.unavailable => l.paymentsUnavailable,
      PassFailure.unreachable => l.unreachable,
      PassFailure.unexpected => l.somethingWentWrong,
    };

/// The Account tab's "Your pass": whether one is running, and buying one.
class PassSection extends StatefulWidget {
  const PassSection({super.key});

  @override
  State<PassSection> createState() => _PassSectionState();
}

class _PassSectionState extends State<PassSection> {
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

  Future<void> _buy() async {
    final bought = await BuyPassScreen.open(context);
    if (bought && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (PlaybackScope.of(context) == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
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
      body = VeloraLoadingRegion(
        label: l.loading,
        child: const VeloraSpinner(size: 24),
      );
    } else {
      final current = status.currentEndsAt;
      final last = status.endsAt;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.sm,
        children: [
          if (status.active && current != null)
            Text(l.passActiveUntil(formatPassEnd(context, current)))
          else ...[
            Text(l.noPass),
            Text(l.passIntro),
          ],
          if (status.active &&
              last != null &&
              current != null &&
              last.isAfter(current))
            Text(l.passQueuedUntil(formatPassEnd(context, last))),
          if (status.checking) Text(l.passChecking),
          VeloraButton(
            label: status.active ? l.buyAnotherPass : l.buyAPass,
            icon: Icons.confirmation_number_outlined,
            variant: status.active
                ? VeloraButtonVariant.secondary
                : VeloraButtonVariant.primary,
            onPressed: _buy,
          ),
        ],
      );
    }
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            Semantics(
              header: true,
              child: Text(l.yourPass, style: theme.textTheme.titleMedium),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

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

/// Choosing a pass, paying on Pesapal's page, and waiting until the API
/// confirms it. Answers true, when popped, once a pass is ready.
class BuyPassScreen extends StatefulWidget {
  const BuyPassScreen({super.key});

  /// Opens Pesapal's page: a new tab on the web, the browser on Android.
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
  String? _message;
  Checkout? _checkout;
  DateTime? _endsAt;
  Timer? _timer;
  DateTime? _deadline;
  bool _checking = false;
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
    }
  }

  void _fail(String message, {_Phase phase = _Phase.choosing}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _phase = phase;
    });
  }

  Future<void> _buy(PassPlan plan) async {
    final api = _api;
    if (api == null) return;
    final email = _email;
    if (email == null && !(_form.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    setState(() {
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
        _phase = _Phase.waiting;
      });
      _deadline = DateTime.now().add(BuyPassScreen.checkFor);
      await _openPesapal();
      _scheduleCheck();
    } on PassException catch (error) {
      _fail(passFailureMessage(l, error.failure));
    }
  }

  Future<void> _openPesapal() async {
    final checkout = _checkout;
    if (checkout == null) return;
    var opened = false;
    try {
      opened = await BuyPassScreen.openPage(checkout.paymentPage);
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _message = context.l10n.couldNotOpenPesapal);
    }
  }

  void _scheduleCheck() {
    _timer?.cancel();
    _timer = Timer(BuyPassScreen.checkEvery, _check);
  }

  Future<void> _check() async {
    final api = _api;
    final checkout = _checkout;
    if (api == null || checkout == null || _checking || !mounted) return;
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
      case PaymentState.abandoned || PaymentState.reversed:
        _timer?.cancel();
        setState(() => _phase = _Phase.gaveUp);
        return;
      case PaymentState.failed:
        setState(() => _phase = _Phase.failed);
      default:
        if (_phase == _Phase.failed) setState(() => _phase = _Phase.waiting);
    }
    final deadline = _deadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      setState(() => _phase = _Phase.timedOut);
      return;
    }
    _scheduleCheck();
  }

  void _chooseAgain() {
    _timer?.cancel();
    setState(() {
      _checkout = null;
      _message = null;
      _phase = _Phase.choosing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.buyAPass)),
      body: ScreenBody(
        heading: l.choosePass,
        children: [
          ...switch (_phase) {
            _Phase.loading => [
              Center(
                child: VeloraLoadingRegion(
                  label: l.loading,
                  child: const VeloraSpinner(size: 32),
                ),
              ),
            ],
            _Phase.choosing => _choosing(l),
            _Phase.starting => [
              Center(
                child: VeloraLoadingRegion(
                  label: l.startingPayment,
                  child: const VeloraSpinner(size: 32),
                ),
              ),
            ],
            _Phase.waiting => [
              EmptyState(
                icon: Icons.open_in_new,
                title: l.finishPaying,
                message: l.finishPayingHelp,
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
                onRetry: _chooseAgain,
                retryLabel: l.choosePass,
              ),
              _waitingActions(l),
            ],
            _Phase.gaveUp => [
              ErrorState(
                title: l.paymentFailedTitle,
                message: l.paymentGivenUp,
                onRetry: _chooseAgain,
                retryLabel: l.choosePass,
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

  Widget _waitingActions(AppLocalizations l) => Wrap(
    spacing: VeloraSpacing.sm,
    runSpacing: VeloraSpacing.sm,
    alignment: WrapAlignment.center,
    children: [
      VeloraButton(label: l.checkAgain, icon: Icons.refresh, onPressed: _check),
      VeloraButton(
        label: l.openPesapalAgain,
        icon: Icons.open_in_new,
        variant: VeloraButtonVariant.secondary,
        onPressed: _openPesapal,
      ),
      TextButton(onPressed: _chooseAgain, child: Text(l.cancel)),
    ],
  );

  List<Widget> _choosing(AppLocalizations l) {
    if (_plans.isEmpty) {
      return [
        EmptyState(
          icon: Icons.confirmation_number_outlined,
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
    return [
      Text(l.passIntro),
      if (_email == null)
        Form(
          key: _form,
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
      for (final plan in _plans)
        Card.outlined(
          key: ValueKey('plan-${plan.id}'),
          child: ListTile(
            title: Text(passName(l, plan.id, plan.days)),
            subtitle: Text(formatUgx(context, plan.priceUgx)),
            trailing: Tooltip(
              message: l.payWithPesapal,
              child: const Icon(Icons.chevron_right),
            ),
            onTap: () => _buy(plan),
          ),
        ),
    ];
  }
}
