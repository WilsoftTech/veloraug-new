import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/l10n.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/velora_button.dart';
import 'account_pages.dart';

AccountPage dangerZonePage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.dangerZoneTitle,
    builder: (context) => const DangerZoneBody(),
  );
}

enum _Step { loading, ready, deleting, failed }

/// Permanently deleting the account. It says what goes and what stays, and
/// needs a tick, a final confirmation and a fresh sign-in as the same
/// person. Until the server can delete accounts, it says so and offers no
/// button. Success is shown only once the server confirms it.
class DangerZoneBody extends StatefulWidget {
  const DangerZoneBody({super.key});

  @override
  State<DangerZoneBody> createState() => _DangerZoneBodyState();
}

class _DangerZoneBodyState extends State<DangerZoneBody> {
  _Step _step = _Step.loading;
  DeletionStatus? _status;
  AccountFailure? _failure;
  String? _error;
  bool _understood = false;
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
    final api = accountApiOf(context);
    setState(() {
      _step = _Step.loading;
      _error = null;
    });
    if (api == null) {
      setState(() {
        _failure = AccountFailure.unreachable;
        _step = _Step.failed;
      });
      return;
    }
    try {
      final status = await api.deletionStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _step = _Step.ready;
      });
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _step = _Step.failed;
      });
    }
  }

  Future<bool> _confirm() async {
    final l = context.l10n;
    final palette = VeloraPalette.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteAccountConfirmTitle),
        content: Text(l.deleteAccountConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.deleteAccountConfirmButton),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final auth = AuthScope.of(context);
    final api = accountApiOf(context);
    if (auth == null || api == null) return;
    if (!await _confirm() || !mounted) return;
    setState(() {
      _step = _Step.deleting;
      _error = null;
    });
    final reauth = await auth.reauthenticate();
    if (!mounted) return;
    if (reauth != ReauthResult.confirmed) {
      setState(() {
        _step = _Step.ready;
        _error = reauth == ReauthResult.differentAccount
            ? l.reauthDifferentAccount
            : l.reauthFailed;
      });
      return;
    }
    try {
      final status = await api.deleteAccount();
      if (!mounted) return;
      if (status.state != DeletionState.completed) {
        setState(() {
          _status = status;
          _step = _Step.ready;
          _error = l.deletionIncompleteMessage;
        });
        return;
      }
      // Confirmed by the server: forget the session on this device.
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await auth.signOut();
      messenger.showSnackBar(SnackBar(content: Text(l.deletionDone)));
      navigator.popUntil((route) => route.isFirst);
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _step = _Step.ready;
        _error = accountFailureMessage(l, error.failure);
        if (error.failure == AccountFailure.incomplete) {
          _status = DeletionStatus(
            available: true,
            state: DeletionState.pending,
            requestedAt: _status?.requestedAt,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = VeloraPalette.of(context);
    final status = _status;
    final explanation = Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.sm,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.deletionWhatGoes,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final line in [
              l.deletionGoesProfile,
              l.deletionGoesHistory,
              l.deletionGoesDevices,
              l.deletionGoesSignIn,
            ])
              _Bullet(line),
            Semantics(
              header: true,
              child: Text(
                l.deletionWhatStays,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final line in [
              l.deletionStaysPayments,
              l.deletionStaysDownloads,
              l.deletionStaysPlan,
            ])
              _Bullet(line),
          ],
        ),
      ),
    );

    final List<Widget> action = switch (_step) {
      _Step.loading => [
        VeloraLoadingRegion(
          label: l.loading,
          child: const VeloraSkeleton(height: 48),
        ),
      ],
      _Step.failed => [
        ErrorState(
          title: l.deletionStatusFailed,
          message: accountFailureMessage(l, _failure!),
          onRetry: _load,
        ),
      ],
      _ when status != null && !status.available => [
        EmptyState(
          icon: Icons.info_outline,
          title: l.deletionUnavailableTitle,
          message: l.deletionUnavailableMessage,
        ),
      ],
      _ => [
        if (status?.state == DeletionState.pending)
          Text(l.deletionPendingHelp, style: theme.textTheme.bodyMedium),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _understood,
          onChanged: _step == _Step.deleting
              ? null
              : (value) => setState(() => _understood = value ?? false),
          title: Text(l.deletionUnderstand),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (_error case final error?)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.danger,
              ),
            ),
          ),
        VeloraButton(
          label: status?.state == DeletionState.pending
              ? l.deletionTryAgain
              : l.deleteAccountButton,
          icon: Icons.delete_forever_outlined,
          variant: VeloraButtonVariant.danger,
          isLoading: _step == _Step.deleting,
          loadingLabel: l.deletingAccount,
          onPressed: _understood ? _delete : null,
        ),
      ],
    };

    return ScreenBody(
      heading: l.dangerZoneTitle,
      intro: l.dangerZoneIntro,
      children: [if (status?.available == true) explanation, ...action],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.xs,
      children: [
        const ExcludeSemantics(child: Text('•')),
        Expanded(child: Text(text)),
      ],
    );
  }
}
