import 'package:flutter/material.dart';

import '../api/pass_api.dart';
import '../api/playback_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'pass_screen.dart';

String platformName(AppLocalizations l, String platform) => switch (platform) {
  'web' => l.platformWeb,
  'android' => l.platformAndroid,
  _ => l.platformOther,
};

IconData platformIcon(String platform) => switch (platform) {
  'web' => Icons.laptop_outlined,
  'android' || 'ios' => Icons.phone_android_outlined,
  _ => Icons.devices_other_outlined,
};

/// The Account tab's "My devices": the devices registered to this account,
/// which one is this, when each was last used, removing and renaming, and
/// what is playing now, with a way to stop it.
class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key});

  @override
  State<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<DevicesSection> {
  DeviceList? _devices;
  List<LiveSession> _playing = const [];
  PassFailure? _failure;
  bool _started = false;
  bool _busy = false;

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
      final devices = await api.myDevices();
      final playing = await api.playingNow();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _playing = playing;
      });
    } on PassException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  Future<void> _act(
    Future<void> Function(PlaybackApi api) action,
    String done,
  ) async {
    final api = PlaybackScope.of(context);
    if (api == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await action(api);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on PassException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(passFailureMessage(l, error.failure))),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _remove(RegisteredDevice device) async {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.removeDeviceTitle),
        content: Text(l.removeDeviceMessage(device.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.removeDevice),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _act(
      (api) => api.removeDevice(device.id, current: device.current),
      l.deviceRemovedNotice,
    );
  }

  Future<void> _rename(RegisteredDevice device) async {
    final l = context.l10n;
    final field = TextEditingController(text: device.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.renameDevice),
        content: VeloraTextField(label: l.deviceName, controller: field),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: Text(l.savePlan),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await _act((api) => api.renameDevice(device.id, name), l.deviceRenamed);
  }

  Future<void> _stop(LiveSession session) async {
    final l = context.l10n;
    await _act(
      (api) => api.stopSession(session.id),
      l.sessionStoppedNotice(session.deviceLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlaybackScope.of(context) == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final failure = _failure;
    final devices = _devices;
    final Widget body;
    if (failure != null) {
      body = ErrorState(
        title: l.devicesCouldNotLoad,
        message: passFailureMessage(l, failure),
        onRetry: _load,
      );
    } else if (devices == null) {
      body = VeloraLoadingRegion(
        label: l.loading,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xs,
          children: [VeloraSkeleton(height: 56), VeloraSkeleton(height: 56)],
        ),
      );
    } else {
      final dates = MaterialLocalizations.of(context);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: VeloraSpacing.xs,
        children: [
          if (devices.overLimit)
            Semantics(
              liveRegion: true,
              child: StatusBadge(
                label: l.devicesOverLimit(devices.allowed),
                tone: StatusTone.warning,
                icon: Icons.warning_amber_rounded,
              ),
            )
          else
            Text(l.devicesAllowance(devices.allowed)),
          if (devices.devices.isEmpty) Text(l.devicesNone),
          for (final device in devices.devices)
            ListTile(
              key: ValueKey('device-${device.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(platformIcon(device.platform)),
              title: Wrap(
                spacing: VeloraSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(device.label),
                  if (device.current)
                    StatusBadge(label: l.thisDevice, tone: StatusTone.info),
                ],
              ),
              subtitle: Text(
                '${platformName(l, device.platform)} · '
                '${l.lastActive(dates.formatMediumDate(device.lastActiveAt.toLocal()))}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: l.renameDevice,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _busy ? null : () => _rename(device),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _remove(device),
                    child: Text(l.removeDevice),
                  ),
                ],
              ),
            ),
          if (_playing.isNotEmpty) ...[
            const SizedBox(height: VeloraSpacing.xs),
            Semantics(
              header: true,
              child: Text(l.playingNow, style: theme.textTheme.titleSmall),
            ),
            for (final session in _playing)
              ListTile(
                key: ValueKey('session-${session.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  l.playingOn(
                    session.deviceLabel,
                    TimeOfDay.fromDateTime(session.startedAt.toLocal())
                        .format(context),
                  ),
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _stop(session),
                  child: Text(l.stopPlayback),
                ),
              ),
          ],
          Text(
            l.devicesPolicy,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return AccountCard(title: l.myDevices, child: body);
  }
}

/// The Account tab's "Payments": the viewer's recent payments, as the API
/// has confirmed them with Pesapal.
class PaymentsSection extends StatefulWidget {
  const PaymentsSection({super.key});

  @override
  State<PaymentsSection> createState() => _PaymentsSectionState();
}

class _PaymentsSectionState extends State<PaymentsSection> {
  List<PaymentRecord>? _payments;
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
      final payments = await api.myPayments();
      if (mounted) setState(() => _payments = payments);
    } on PassException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlaybackScope.of(context) == null) return const SizedBox.shrink();
    final l = context.l10n;
    final failure = _failure;
    final payments = _payments;
    final Widget body;
    if (failure != null) {
      body = ErrorState(
        title: l.paymentsCouldNotLoad,
        message: passFailureMessage(l, failure),
        onRetry: _load,
      );
    } else if (payments == null) {
      body = VeloraLoadingRegion(
        label: l.loading,
        child: const VeloraSkeleton(height: 48),
      );
    } else if (payments.isEmpty) {
      body = Text(l.paymentsNone);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final payment in payments)
            ListTile(
              key: ValueKey('payment-${payment.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${payment.planName} · ${formatUgx(context, payment.amountUgx)}',
              ),
              subtitle: Text(
                [
                  formatPassEnd(context, payment.createdAt),
                  if (payment.providerReference case final ref?)
                    l.paymentReference(ref),
                ].join(' · '),
              ),
              trailing: PaymentStateBadge(payment.state),
            ),
        ],
      );
    }
    return AccountCard(title: l.paymentsHeading, child: body);
  }
}

class PaymentStateBadge extends StatelessWidget {
  const PaymentStateBadge(this.state, {super.key});

  final PaymentState state;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (label, tone) = switch (state) {
      PaymentState.completed => (l.paymentStateCompleted, StatusTone.success),
      PaymentState.started ||
      PaymentState.pending => (l.paymentStatePending, StatusTone.info),
      PaymentState.failed => (l.paymentStateFailed, StatusTone.danger),
      PaymentState.reversed => (l.paymentStateReversed, StatusTone.warning),
      PaymentState.abandoned => (l.paymentStateAbandoned, StatusTone.neutral),
    };
    return StatusBadge(label: label, tone: tone);
  }
}

/// My devices on a screen of its own, opened from the player when a
/// device limit stops playback.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const DevicesScreen()));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.manageDevices)),
      body: ScreenBody(
        heading: l.myDevices,
        children: [
          const DevicesSection(),
          Align(
            alignment: Alignment.centerLeft,
            child: VeloraButton(
              label: l.tryAgain,
              icon: Icons.play_arrow,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
