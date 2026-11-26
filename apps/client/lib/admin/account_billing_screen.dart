import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../screens/devices_screen.dart' show platformName;
import '../screens/pass_screen.dart' show formatUgx;
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'payment_sheet.dart';

/// One account's billing: their passes, payments, free days and devices.
/// Admins give free days here, and remove devices.
class AccountBillingScreen extends StatefulWidget {
  const AccountBillingScreen({super.key, required this.userId, this.contact});

  final String userId;

  /// Masked, as the list showed it: a***@example.com.
  final String? contact;

  @override
  State<AccountBillingScreen> createState() => _AccountBillingScreenState();
}

class _AccountBillingScreenState extends State<AccountBillingScreen> {
  AccountBilling? _account;
  List<AdminPassPlan> _plans = const [];
  AdminException? _failure;
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
      final account = await api.account(widget.userId);
      final plans = await api.passPlans();
      if (!mounted) return;
      setState(() {
        _account = account;
        _plans = [
          for (final p in plans)
            if (!p.legacy) p,
        ];
        _failure = null;
      });
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _give() async {
    final l = context.l10n;
    final given = await showDialog<AdminPass>(
      context: context,
      builder: (_) => _GrantDialog(userId: widget.userId, plans: _plans),
    );
    if (given == null || !mounted) return;
    final dates = MaterialLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.freeDaysGiven(
            dates.formatMediumDate(given.startsAt.toLocal()),
            dates.formatMediumDate(given.endsAt.toLocal()),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _remove(AdminDevice device) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.removeDeviceTitle,
      message: l.adminRemoveDeviceMessage(device.label),
      action: l.removeDevice,
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    await runAdmin(
      context,
      (api) => api.removeDeviceOf(widget.userId, device.id),
      done: l.deviceRemovedNotice,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final account = _account;
    final failure = _failure;
    final title = widget.contact ?? l.accountShort(widget.userId);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: failure != null
            ? ScreenBody(
                heading: title,
                children: [
                  ErrorState(
                    title: l.adminLoadFailed,
                    message: adminFailureMessage(l, failure),
                    onRetry: _load,
                  ),
                ],
              )
            : account == null
            ? Center(
                child: VeloraLoadingRegion(
                  label: l.loading,
                  child: const VeloraSpinner(size: 32),
                ),
              )
            : _body(l, title, account),
      ),
    );
  }

  Widget _body(AppLocalizations l, String title, AccountBilling account) {
    final dates = MaterialLocalizations.of(context);
    final now = DateTime.now();
    String date(DateTime at) => dates.formatMediumDate(at.toLocal());
    return ScreenBody(
      heading: title,
      intro: l.accountIdLine(account.userId),
      maxWidth: VeloraLayout.browseWidth,
      status: VeloraButton(
        label: l.giveFreeDays,
        icon: Icons.card_giftcard,
        onPressed: _plans.isEmpty ? null : _give,
      ),
      children: [
        AdminSection(
          title: l.adminPasses,
          children: [
            if (account.passes.isEmpty) Text(l.passesNone),
            for (final pass in account.passes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(pass.planName),
                subtitle: Text(
                  [
                    l.passFromTo(date(pass.startsAt), date(pass.endsAt)),
                    pass.grantId != null ? l.passGiven : l.passBought,
                  ].join(' · '),
                ),
                trailing: StatusBadge(
                  label: pass.revokedAt != null
                      ? l.passEndedEarly
                      : pass.endsAt.isBefore(now)
                      ? l.passOver
                      : pass.startsAt.isAfter(now)
                      ? l.passQueued
                      : l.passRunning,
                  tone: pass.revokedAt != null
                      ? StatusTone.danger
                      : pass.endsAt.isBefore(now)
                      ? StatusTone.neutral
                      : pass.startsAt.isAfter(now)
                      ? StatusTone.info
                      : StatusTone.success,
                ),
              ),
          ],
        ),
        AdminSection(
          title: l.freeDaysTitle,
          children: [
            if (account.grants.isEmpty) Text(l.freeDaysNone),
            for (final grant in account.grants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.freeDaysLine(grant.days, grant.planName)),
                subtitle: Text(
                  [
                    date(grant.createdAt),
                    grant.reason,
                    if (grant.grantedByEmail case final by?) l.givenBy(by),
                  ].join(' · '),
                ),
              ),
          ],
        ),
        AdminSection(
          title: l.adminPayments,
          children: [
            if (account.payments.isEmpty) Text(l.paymentsNone),
            for (final payment in account.payments)
              PaymentTile(
                key: ValueKey('account-payment-${payment.id}'),
                payment: payment,
                onTap: () async {
                  await showPaymentSheet(context, payment.id);
                  if (mounted) await _load();
                },
              ),
          ],
        ),
        AdminSection(
          title: l.adminDevicesOf,
          children: [
            if (account.devices.isEmpty) Text(l.devicesNone),
            for (final device in account.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.label),
                subtitle: Text(
                  '${platformName(l, device.platform)} · '
                  '${l.lastActive(date(device.lastActiveAt))}',
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
      ],
    );
  }
}

/// Free days: a plan, how many days, and why. Pops with the new pass.
class _GrantDialog extends StatefulWidget {
  const _GrantDialog({required this.userId, required this.plans});

  final String userId;
  final List<AdminPassPlan> plans;

  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  final _form = GlobalKey<FormState>();
  final _days = TextEditingController(text: '7');
  final _reason = TextEditingController();
  late String _plan = widget.plans.first.id;
  bool _saving = false;

  @override
  void dispose() {
    _days.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final given = await runAdmin(
      context,
      (api) => api.grantDays(
        widget.userId,
        planId: _plan,
        days: int.parse(_days.text.trim()),
        reason: _reason.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (given != null) Navigator.of(context).pop(given);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.giveFreeDays),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: VeloraSpacing.sm,
            children: [
              Text(l.giveFreeDaysIntro),
              DropdownButtonFormField<String>(
                initialValue: _plan,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.freeDaysPlan),
                items: [
                  for (final plan in widget.plans)
                    DropdownMenuItem(
                      value: plan.id,
                      child: Text(
                        '${plan.displayName} · ${l.planDevices(plan.maxDevices)}'
                        '${plan.priceUgx == null ? '' : ' · ${formatUgx(context, plan.priceUgx!)}'}',
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _plan = id ?? _plan),
              ),
              VeloraTextField(
                label: l.freeDaysCount,
                controller: _days,
                keyboardType: TextInputType.number,
                validator: (v) => checkNumber(l, v, min: 1, max: 90),
              ),
              VeloraTextField(
                label: l.freeDaysReason,
                helperText: l.freeDaysReasonHelp,
                controller: _reason,
                maxLines: 2,
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.length < 3) return l.required;
                  if (text.length > 300) return l.tooLong(300);
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        VeloraButton(
          label: l.giveFreeDays,
          isLoading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}
