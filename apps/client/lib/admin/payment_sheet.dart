import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../screens/pass_screen.dart' show formatUgx;
import '../theme/tokens.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import 'account_billing_screen.dart';
import 'admin_common.dart';

/// A payment's state in the admins' words: Waiting, Paid, Failed, Expired,
/// Reversed or Refunded.
(String, StatusTone) paymentState(AppLocalizations l, String state) =>
    switch (state) {
      'started' || 'pending' => (l.paymentStateWaiting, StatusTone.info),
      'completed' => (l.paymentStatePaid, StatusTone.success),
      'failed' => (l.paymentStateFailed, StatusTone.danger),
      'abandoned' => (l.paymentStateExpired, StatusTone.neutral),
      'reversed' => (l.paymentStateReversed, StatusTone.warning),
      'refunded' => (l.paymentStateRefunded, StatusTone.warning),
      _ => (state, StatusTone.neutral),
    };

/// "Wed 26 Nov, 14:05".
String paymentTime(BuildContext context, DateTime at) {
  final local = at.toLocal();
  final m = MaterialLocalizations.of(context);
  return '${m.formatMediumDate(local)}, '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

/// One payment in a list: plan, amount, contact, time and state.
class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment, required this.onTap});

  final AdminPayment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (state, tone) = paymentState(l, payment.state);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VeloraRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xxs,
            children: [
              Text(
                '${payment.planName} · ${formatUgx(context, payment.amountUgx)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                [
                  paymentTime(context, payment.createdAt),
                  ?payment.contact,
                  ?payment.method,
                ].join(' · '),
              ),
              if (payment.reason case final reason?)
                Text(reason, style: Theme.of(context).textTheme.bodySmall),
              StatusBadge(label: state, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens one payment: its facts, its steps, its pass, and what can be done.
/// Answers when it closes.
Future<void> showPaymentSheet(BuildContext context, String paymentId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
      builder: (_) => _PaymentSheet(paymentId: paymentId),
    );

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.paymentId});

  final String paymentId;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  PaymentDetail? _detail;
  AdminException? _failure;
  bool _busy = false;
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
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final detail = await api.paymentDetail(widget.paymentId);
      if (mounted) setState(() => _detail = detail);
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _recheck() async {
    final l = context.l10n;
    setState(() => _busy = true);
    final detail = await runAdmin(
      context,
      (api) => api.recheckPayment(widget.paymentId),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (detail != null) _detail = detail;
    });
    if (detail != null) {
      final (state, _) = paymentState(l, detail.payment.state);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.paymentRechecked(state))));
    }
  }

  Future<void> _refund(AdminPayment payment) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.markRefundedTitle,
      message: l.markRefundedMessage(
        payment.planName,
        formatUgx(context, payment.amountUgx),
        payment.contact ?? payment.userId,
      ),
      action: l.markRefunded,
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final done = await runAdmin(
      context,
      (api) => api.refundPayment(payment.id),
      done: l.paymentRefundedNotice,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (done != null) await _load();
  }

  void _openAccount(AdminPayment payment) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AccountBillingScreen(
          userId: payment.userId,
          contact: payment.contact,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final detail = _detail;
    final failure = _failure;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VeloraSpacing.lg,
          0,
          VeloraSpacing.lg,
          VeloraSpacing.lg,
        ),
        child: failure != null
            ? Text(adminFailureMessage(l, failure))
            : detail == null
            ? Center(
                child: VeloraLoadingRegion(
                  label: l.loading,
                  child: const VeloraSpinner(size: 32),
                ),
              )
            : SingleChildScrollView(child: _body(l, detail)),
      ),
    );
  }

  Widget _body(AppLocalizations l, PaymentDetail detail) {
    final payment = detail.payment;
    final theme = Theme.of(context);
    final (state, tone) = paymentState(l, payment.state);
    final dates = MaterialLocalizations.of(context);
    Widget fact(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: VeloraSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label, style: theme.textTheme.bodySmall),
                ),
                const SizedBox(width: VeloraSpacing.xs),
                Expanded(child: SelectableText(value)),
              ],
            ),
          );
    final pass = detail.pass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        Text(
          '${payment.planName} · ${formatUgx(context, payment.amountUgx)}',
          style: theme.textTheme.titleLarge,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(label: state, tone: tone),
        ),
        Column(
          children: [
            fact(l.paymentContact, payment.contact),
            fact(l.paymentMethod, payment.method),
            fact(l.paymentConfirmationCode, payment.reference),
            fact(l.paymentTrackingId, payment.trackingId),
            fact(l.paymentId, payment.id),
            fact(l.paymentReason, payment.reason),
          ],
        ),
        Text(l.paymentTimeline, style: theme.textTheme.titleSmall),
        for (final step in detail.timeline)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.sm,
            children: [
              Icon(_stepIcon(step.step), size: 20),
              // The time under the step, so a narrow phone has room.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_stepName(l, step.step)),
                    Text(
                      step.at == null
                          ? l.paymentTimeNotRecorded
                          : paymentTime(context, step.at!),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (pass != null)
          Text(
            l.paymentMadePass(
              dates.formatMediumDate(pass.startsAt.toLocal()),
              dates.formatMediumDate(pass.endsAt.toLocal()),
            ),
          ),
        if (payment.state == 'abandoned') Text(l.paymentExpiredHelp),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          children: [
            if (payment.trackingId != null && payment.state != 'refunded')
              VeloraButton(
                label: l.recheckWithPesapal,
                icon: Icons.sync,
                variant: VeloraButtonVariant.secondary,
                isLoading: _busy,
                onPressed: _recheck,
              ),
            if (payment.state == 'completed')
              VeloraButton(
                label: l.markRefunded,
                icon: Icons.undo,
                variant: VeloraButtonVariant.danger,
                onPressed: _busy ? null : () => _refund(payment),
              ),
            VeloraButton(
              label: l.openAccount,
              icon: Icons.person_outline,
              variant: VeloraButtonVariant.tertiary,
              onPressed: () => _openAccount(payment),
            ),
          ],
        ),
        if (payment.state == 'completed') Text(l.refundHowTo),
      ],
    );
  }

  static IconData _stepIcon(String step) => switch (step) {
    'started' => Icons.shopping_cart_outlined,
    'sent' => Icons.send_outlined,
    'completed' => Icons.check_circle_outline,
    'failed' => Icons.error_outline,
    'expired' => Icons.timer_off_outlined,
    'reversed' || 'refunded' => Icons.undo,
    _ => Icons.circle_outlined,
  };

  static String _stepName(AppLocalizations l, String step) => switch (step) {
    'started' => l.stepStarted,
    'sent' => l.stepSent,
    'completed' => l.stepCompleted,
    'failed' => l.stepFailed,
    'expired' => l.stepExpired,
    'reversed' => l.stepReversed,
    'refunded' => l.stepRefunded,
    _ => step,
  };
}
