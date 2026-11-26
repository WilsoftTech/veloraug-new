import 'dart:async';

import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../screens/pass_screen.dart' show formatUgx, passName;
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'account_billing_screen.dart';
import 'admin_common.dart';
import 'payment_sheet.dart';
import 'revenue_chart.dart';
import 'save_file.dart';

/// Searches wait this long after typing stops.
const Duration billingSearchDelay = Duration(milliseconds: 400);

/// Admin → Subscriptions: the money and the subscribers at a glance, every
/// payment searched and filtered, each subscriber's account, the plans with
/// their prices, and price history.
///
/// Payments left unpaid past the timeout are settled by the server each
/// time this loads: Pesapal is asked, and those not paid are shown expired.
/// Refunds are marked here after being made on Pesapal; free days are given
/// from a subscriber's account.
class SubscriptionsView extends StatefulWidget {
  const SubscriptionsView({super.key});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  BillingMetrics? _metrics;
  List<AdminPassPlan>? _plans;
  List<PlanChangeEntry> _changes = const [];
  AdminException? _failure;
  bool _started = false;
  bool _busy = false;
  final _prices = <String, TextEditingController>{};
  final _forSale = <String, bool>{};
  final _featured = <String, bool>{};

  // Payments.
  List<AdminPayment>? _payments;
  int _paymentTotal = 0;
  String? _state;
  String? _planFilter;
  DateTimeRange? _dates;
  final _paymentSearch = TextEditingController();
  Timer? _paymentDelay;
  bool _loadingMore = false;
  bool _exporting = false;
  int _paymentGeneration = 0;

  // Subscribers.
  List<AdminSubscriber>? _subscribers;
  bool _endingSoon = false;
  final _subscriberSearch = TextEditingController();
  Timer? _subscriberDelay;

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
    _paymentDelay?.cancel();
    _subscriberDelay?.cancel();
    _paymentSearch.dispose();
    _subscriberSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      // The overview first: it settles stale payments before they are listed.
      final metrics = await api.billingMetrics();
      final plans = await api.passPlans();
      final changes = await api.planChanges();
      if (!mounted) return;
      setState(() {
        _failure = null;
        _metrics = metrics;
        _plans = plans;
        _changes = changes;
        for (final plan in plans) {
          (_prices[plan.id] ??= TextEditingController()).text =
              plan.priceUgx?.toString() ?? '';
          _forSale[plan.id] = plan.forSale;
          _featured[plan.id] = plan.featured;
        }
      });
      await Future.wait([_loadPayments(), _loadSubscribers()]);
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _loadPayments({bool more = false}) async {
    final api = AdminScope.of(context);
    if (api == null) return;
    final generation = ++_paymentGeneration;
    if (more) setState(() => _loadingMore = true);
    try {
      final page = await api.transactions(
        state: _state,
        planId: _planFilter,
        since: _dates?.start,
        until: _dates?.end,
        search: _paymentSearch.text,
        offset: more ? (_payments?.length ?? 0) : 0,
      );
      if (!mounted || generation != _paymentGeneration) return;
      setState(() {
        _payments = more ? [...?_payments, ...page.payments] : page.payments;
        _paymentTotal = page.total;
        _loadingMore = false;
      });
    } on AdminException catch (error) {
      if (!mounted || generation != _paymentGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminFailureMessage(context.l10n, error))),
      );
    }
  }

  Future<void> _loadSubscribers() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final found = await api.subscribers(
        search: _subscriberSearch.text,
        endingWithinDays: _endingSoon ? 3 : null,
      );
      if (mounted) setState(() => _subscribers = found);
    } on AdminException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(adminFailureMessage(context.l10n, error))),
      );
    }
  }

  void _filterPayments(void Function() change) {
    setState(change);
    _loadPayments();
  }

  Future<void> _chooseDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _dates,
    );
    if (picked != null && mounted) _filterPayments(() => _dates = picked);
  }

  Future<void> _export() async {
    final l = context.l10n;
    setState(() => _exporting = true);
    final text = await runAdmin(
      context,
      (api) => api.transactionsCsv(
        state: _state,
        planId: _planFilter,
        since: _dates?.start,
        until: _dates?.end,
        search: _paymentSearch.text,
      ),
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    if (text == null) return;
    final now = DateTime.now();
    final name =
        'veloraug-payments-${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.csv';
    final saved = await saveTextFile(name, text, 'text/csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? l.paymentsExported(name) : l.exportWebOnly),
      ),
    );
  }

  Future<void> _openPayment(AdminPayment payment) async {
    await showPaymentSheet(context, payment.id);
    if (mounted) await _loadPayments();
  }

  Future<void> _openAccount(AdminSubscriber subscriber) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountBillingScreen(
          userId: subscriber.userId,
          contact: subscriber.contact,
        ),
      ),
    );
    if (mounted) await _load();
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
      intro: l.adminSubscriptionsIntro(metrics.timeoutMinutes),
      maxWidth: VeloraLayout.browseWidth,
      status: VeloraButton(
        label: l.refresh,
        icon: Icons.refresh,
        variant: VeloraButtonVariant.secondary,
        onPressed: _load,
      ),
      children: [
        _overview(l, metrics),
        _paymentsSection(l, plans),
        _subscribersSection(l),
        _plansSection(l, plans),
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

  Widget _overview(AppLocalizations l, BillingMetrics metrics) {
    final rate = metrics.successRate;
    return AdminSection(
      title: l.adminOverview,
      children: [
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          children: [
            _Metric(
              l.metricRevenueToday,
              formatUgx(context, metrics.revenueTodayUgx),
            ),
            _Metric(
              l.metricRevenue7Days,
              formatUgx(context, metrics.revenue7DaysUgx),
            ),
            _Metric(l.metricRevenue, formatUgx(context, metrics.revenueUgx)),
            _Metric(
              l.metricSuccessRate,
              rate == null ? '–' : '${(rate * 100).round()}%',
            ),
            _Metric(l.metricActiveSubscribers, '${metrics.activeSubscribers}'),
            _Metric(l.metricEndingSoon, '${metrics.endingSoon}'),
            _Metric(l.metricPending, '${metrics.pending}'),
            _Metric(l.metricFailed, '${metrics.failed}'),
            _Metric(l.metricRefunded, '${metrics.refunded}'),
            _Metric(l.metricFreeDays, '${metrics.granted}'),
            _Metric(l.metricDevices, '${metrics.devices}'),
            _Metric(l.metricPlaying, '${metrics.playing}'),
          ],
        ),
        if (metrics.byPlan.isNotEmpty)
          Text(
            l.subscribersByPlan(
              metrics.byPlan.map((p) => '${p.$1}: ${p.$2}').join(' · '),
            ),
          ),
        RevenueChart(days: metrics.daily),
      ],
    );
  }

  Widget _paymentsSection(AppLocalizations l, List<AdminPassPlan> plans) {
    final payments = _payments;
    final dates = MaterialLocalizations.of(context);
    final range = _dates;
    return AdminSection(
      title: l.adminPayments,
      children: [
        TextField(
          controller: _paymentSearch,
          onChanged: (_) {
            _paymentDelay?.cancel();
            _paymentDelay = Timer(billingSearchDelay, _loadPayments);
          },
          decoration: InputDecoration(
            labelText: l.searchPayments,
            helperText: l.searchPaymentsHelp,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        Wrap(
          spacing: VeloraSpacing.xs,
          runSpacing: VeloraSpacing.xs,
          children: [
            for (final (state, label) in [
              (null, l.paymentsFilterAll),
              ('pending', l.paymentStateWaiting),
              ('completed', l.paymentStatePaid),
              ('failed', l.paymentStateFailed),
              ('abandoned', l.paymentStateExpired),
              ('reversed', l.paymentStateReversed),
              ('refunded', l.paymentStateRefunded),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _state == state,
                onSelected: (_) => _filterPayments(() => _state = state),
              ),
          ],
        ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _planFilter,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(labelText: l.paymentPlanFilter),
                items: [
                  DropdownMenuItem(child: Text(l.paymentsFilterAll)),
                  for (final plan in plans)
                    DropdownMenuItem(
                      value: plan.id,
                      child: Text(
                        plan.legacy
                            ? passName(l, plan.id, plan.days)
                            : plan.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => _filterPayments(() => _planFilter = id),
              ),
            ),
            VeloraButton(
              label: range == null
                  ? l.paymentDates
                  : l.paymentDatesChosen(
                      dates.formatShortMonthDay(range.start),
                      dates.formatShortMonthDay(range.end),
                    ),
              icon: Icons.date_range,
              variant: VeloraButtonVariant.secondary,
              onPressed: _chooseDates,
            ),
            if (range != null)
              IconButton(
                tooltip: l.clearDates,
                icon: const Icon(Icons.close),
                onPressed: () => _filterPayments(() => _dates = null),
              ),
            VeloraButton(
              label: l.exportCsv,
              icon: Icons.download,
              variant: VeloraButtonVariant.secondary,
              isLoading: _exporting,
              onPressed: _export,
            ),
          ],
        ),
        if (payments == null)
          const Center(child: VeloraSpinner(size: 24))
        else ...[
          Text(l.paymentsCount(_paymentTotal)),
          if (payments.isEmpty) Text(l.paymentsNone),
          for (final payment in payments)
            PaymentTile(
              key: ValueKey('admin-payment-${payment.id}'),
              payment: payment,
              onTap: () => _openPayment(payment),
            ),
          if (payments.length < _paymentTotal)
            Center(
              child: VeloraButton(
                label: l.loadMore(_paymentTotal - payments.length),
                variant: VeloraButtonVariant.secondary,
                isLoading: _loadingMore,
                onPressed: () => _loadPayments(more: true),
              ),
            ),
        ],
      ],
    );
  }

  Widget _subscribersSection(AppLocalizations l) {
    final subscribers = _subscribers;
    final dates = MaterialLocalizations.of(context);
    return AdminSection(
      title: l.adminSubscribers,
      children: [
        TextField(
          controller: _subscriberSearch,
          onChanged: (_) {
            _subscriberDelay?.cancel();
            _subscriberDelay = Timer(billingSearchDelay, _loadSubscribers);
          },
          decoration: InputDecoration(
            labelText: l.searchSubscribers,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: Text(l.endingWithin3Days),
            selected: _endingSoon,
            onSelected: (on) {
              setState(() => _endingSoon = on);
              _loadSubscribers();
            },
          ),
        ),
        if (subscribers == null)
          const Center(child: VeloraSpinner(size: 24))
        else if (subscribers.isEmpty)
          Text(l.subscribersNone)
        else
          for (final subscriber in subscribers)
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAccount(subscriber),
            ),
      ],
    );
  }

  Widget _plansSection(AppLocalizations l, List<AdminPassPlan> plans) {
    return AdminSection(
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
      width: 168,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xxs,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
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
        Flexible(child: Text(label)),
      ],
    );
  }
}
