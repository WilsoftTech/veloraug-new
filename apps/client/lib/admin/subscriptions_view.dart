import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../screens/devices_screen.dart' show platformName;
import '../screens/pass_screen.dart' show formatPassEnd, formatUgx, passName;
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';

/// Admin → Subscriptions, Milestone 10: an overview, the plans with their
/// prices and sale flags, payments (all, failed or reversed), the accounts
/// with an active plan and their devices, and price history.
///
/// The one change to a payment made here is marking a completed one
/// refunded, after it was refunded on Pesapal, which ends its pass. The
/// database refuses the API's editor role anything else.
class SubscriptionsView extends StatefulWidget {
  const SubscriptionsView({super.key});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  BillingMetrics? _metrics;
  List<AdminPassPlan>? _plans;
  List<AdminPayment>? _payments;
  List<AdminSubscriber>? _subscribers;
  List<PlanChangeEntry> _changes = const [];
  String? _paymentFilter;
  AdminException? _failure;
  bool _started = false;
  bool _busy = false;
  final _prices = <String, TextEditingController>{};
  final _forSale = <String, bool>{};
  final _featured = <String, bool>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final field in _prices.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final metrics = await api.billingMetrics();
      final plans = await api.passPlans();
      final payments = await api.billingPayments(state: _paymentFilter);
      final subscribers = await api.subscribers();
      final changes = await api.planChanges();
      if (!mounted) return;
      setState(() {
        _failure = null;
        _metrics = metrics;
        _plans = plans;
        _payments = payments;
        _subscribers = subscribers;
        _changes = changes;
        for (final plan in plans) {
          (_prices[plan.id] ??= TextEditingController()).text =
              plan.priceUgx?.toString() ?? '';
          _forSale[plan.id] = plan.forSale;
          _featured[plan.id] = plan.featured;
        }
      });
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _filter(String? state) async {
    setState(() => _paymentFilter = state);
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final payments = await api.billingPayments(state: state);
      if (mounted) setState(() => _payments = payments);
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  static int? _price(String text) {
    final digits = text.replaceAll(RegExp(r'[\s,]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  Future<void> _savePlan(AdminPassPlan plan) async {
    final l = context.l10n;
    final price = _price(_prices[plan.id]!.text);
    if (price != null && (price < 500 || price > 10000000)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.priceNotValid)));
      return;
    }
    setState(() => _busy = true);
    await runAdmin(
      context,
      (api) => api.updatePlan(
        plan.id,
        priceUgx: price,
        forSale: _forSale[plan.id] ?? false,
        featured: _featured[plan.id] ?? false,
      ),
      done: l.planSaved(plan.displayName),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _markRefunded(AdminPayment payment) async {
    final l = context.l10n;
    final amount = formatUgx(context, payment.amountUgx);
    if (!await confirm(
      context,
      title: l.markRefundedTitle,
      message: l.markRefundedMessage(
        payment.planName,
        amount,
        payment.contact ?? payment.userId,
      ),
      action: l.markRefunded,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await runAdmin(
      context,
      (api) => api.refundPayment(payment.id),
      done: l.paymentRefundedNotice,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _devicesOf(AdminSubscriber subscriber) async {
    final api = AdminScope.of(context);
    if (api == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _DevicesDialog(api: api, subscriber: subscriber),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final failure = _failure;
    final metrics = _metrics;
    final plans = _plans;
    if (failure != null) {
      return ScreenBody(
        heading: l.adminSubscriptions,
        children: [
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          ),
        ],
      );
    }
    if (metrics == null || plans == null) {
      return ScreenBody(
        heading: l.adminSubscriptions,
        children: [
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          ),
        ],
      );
    }
    final dates = MaterialLocalizations.of(context);
    return ScreenBody(
      heading: l.adminSubscriptions,
      maxWidth: VeloraLayout.browseWidth,
      children: [
        AdminSection(
          title: l.adminOverview,
          children: [
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.sm,
              children: [
                _Metric(
                  l.metricActiveSubscribers,
                  '${metrics.activeSubscribers}',
                ),
                _Metric(
                  l.metricRevenue,
                  formatUgx(context, metrics.revenueUgx),
                ),
                _Metric(l.metricPending, '${metrics.pending}'),
                _Metric(l.metricFailed, '${metrics.failed}'),
                _Metric(l.metricReversed, '${metrics.reversed}'),
                _Metric(l.metricRefunded, '${metrics.refunded}'),
                _Metric(l.metricDevices, '${metrics.devices}'),
                _Metric(l.metricPlaying, '${metrics.playing}'),
              ],
            ),
            for (final (name, count) in metrics.byPlan) Text('$name: $count'),
          ],
        ),
        AdminSection(
          title: l.adminPlans,
          children: [
            Text(l.adminPlansIntro),
            for (final plan in plans)
              Card.outlined(
                key: ValueKey('admin-plan-${plan.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(VeloraSpacing.md),
                  child: Wrap(
                    spacing: VeloraSpacing.md,
                    runSpacing: VeloraSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.legacy
                                  ? passName(l, plan.id, plan.days)
                                  : plan.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              plan.legacy
                                  ? l.planLegacy
                                  : l.planSummary(
                                      l.planDays(plan.days),
                                      l.planDevices(plan.maxDevices),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      if (!plan.legacy) ...[
                        SizedBox(
                          width: 180,
                          child: VeloraTextField(
                            key: ValueKey('price-${plan.id}'),
                            label: l.priceUgx(plan.displayName),
                            controller: _prices[plan.id],
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        _Switch(
                          label: l.planOnSale,
                          value: _forSale[plan.id] ?? false,
                          onChanged: (v) => setState(() {
                            _forSale[plan.id] = v;
                            if (!v) _featured[plan.id] = false;
                          }),
                        ),
                        _Switch(
                          label: l.planFeatured,
                          value: _featured[plan.id] ?? false,
                          onChanged: (v) => setState(() {
                            if (v) {
                              _featured.updateAll((_, _) => false);
                              _forSale[plan.id] = true;
                            }
                            _featured[plan.id] = v;
                          }),
                        ),
                        VeloraButton(
                          label: l.savePlan,
                          icon: Icons.save_outlined,
                          isLoading: _busy,
                          onPressed: () => _savePlan(plan),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
        AdminSection(
          title: l.adminPayments,
          children: [
            Wrap(
              spacing: VeloraSpacing.xs,
              children: [
                for (final (state, label) in [
                  (null, l.paymentsFilterAll),
                  ('pending', l.paymentStatePending),
                  ('completed', l.paymentStateCompleted),
                  ('failed', l.paymentStateFailed),
                  ('reversed', l.paymentStateReversed),
                  ('refunded', l.paymentStateRefunded),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _paymentFilter == state,
                    onSelected: (_) => _filter(state),
                  ),
              ],
            ),
            if (_payments case final payments? when payments.isEmpty)
              Text(l.paymentsNone),
            for (final payment in _payments ?? const <AdminPayment>[])
              ListTile(
                key: ValueKey('admin-payment-${payment.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${payment.planName} · ${formatUgx(context, payment.amountUgx)}'
                  '${payment.contact == null ? '' : ' · ${payment.contact}'}',
                ),
                subtitle: Text(
                  [
                    formatPassEnd(context, payment.createdAt),
                    ?payment.method,
                    if (payment.reference case final ref?)
                      l.paymentReference(ref),
                    ?payment.reason,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: VeloraSpacing.xs,
                  children: [
                    if (payment.state == 'completed')
                      TextButton(
                        key: ValueKey('refund-${payment.id}'),
                        onPressed: _busy ? null : () => _markRefunded(payment),
                        child: Text(l.markRefunded),
                      ),
                    StatusBadge(
                      label: payment.state,
                      tone: switch (payment.state) {
                        'completed' => StatusTone.success,
                        'failed' => StatusTone.danger,
                        'reversed' => StatusTone.warning,
                        'pending' || 'started' => StatusTone.info,
                        _ => StatusTone.neutral,
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
        AdminSection(
          title: l.adminSubscribers,
          children: [
            if ((_subscribers ?? const []).isEmpty) Text(l.subscribersNone),
            for (final subscriber in _subscribers ?? const <AdminSubscriber>[])
              ListTile(
                key: ValueKey('subscriber-${subscriber.userId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(subscriber.contact ?? subscriber.userId),
                subtitle: Text(
                  l.subscriberLine(
                    subscriber.planName,
                    dates.formatMediumDate(subscriber.endsAt.toLocal()),
                    '${subscriber.activeDevices}/${subscriber.maxDevices}',
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _devicesOf(subscriber),
                  child: Text(l.adminDevicesOf),
                ),
              ),
          ],
        ),
        if (_changes.isNotEmpty)
          AdminSection(
            title: l.priceHistory,
            children: [
              for (final change in _changes)
                Text(
                  '${dates.formatMediumDate(change.changedAt.toLocal())} · '
                  '${l.priceChange(change.planId, _ugxOrNone(context, change.oldPriceUgx), _ugxOrNone(context, change.newPriceUgx))}',
                ),
            ],
          ),
      ],
    );
  }

  String _ugxOrNone(BuildContext context, int? price) =>
      price == null ? context.l10n.noPrice : formatUgx(context, price);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xxs,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        const SizedBox(width: VeloraSpacing.xxs),
        Text(label),
      ],
    );
  }
}

class _DevicesDialog extends StatefulWidget {
  const _DevicesDialog({required this.api, required this.subscriber});

  final AdminApi api;
  final AdminSubscriber subscriber;

  @override
  State<_DevicesDialog> createState() => _DevicesDialogState();
}

class _DevicesDialogState extends State<_DevicesDialog> {
  List<AdminDevice>? _devices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final devices = await widget.api.devicesOf(widget.subscriber.userId);
      if (mounted) setState(() => _devices = devices);
    } on AdminException {
      if (mounted) setState(() => _devices = const []);
    }
  }

  Future<void> _remove(AdminDevice device) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.removeDeviceTitle,
      message: l.adminRemoveDeviceMessage(device.label),
      action: l.removeDevice,
    )) {
      return;
    }
    if (!mounted) return;
    await runAdmin(
      context,
      (api) => api.removeDeviceOf(widget.subscriber.userId, device.id),
      done: l.deviceRemovedNotice,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dates = MaterialLocalizations.of(context);
    final devices = _devices;
    return AlertDialog(
      title: Text(l.adminDevicesOf),
      content: SizedBox(
        width: 420,
        child: devices == null
            ? VeloraLoadingRegion(
                label: l.loading,
                child: const VeloraSpinner(size: 24),
              )
            : devices.isEmpty
            ? Text(l.devicesNone)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final device in devices)
                    ListTile(
                      title: Text(device.label),
                      subtitle: Text(
                        '${platformName(l, device.platform)} · '
                        '${l.lastActive(dates.formatMediumDate(device.lastActiveAt.toLocal()))}',
                      ),
                      trailing: device.revokedAt == null
                          ? TextButton(
                              onPressed: () => _remove(device),
                              child: Text(l.removeDevice),
                            )
                          : Text(l.deviceRemovedNotice),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
