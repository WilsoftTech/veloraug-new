import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../api/pass_api.dart';
import '../../api/playback_api.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/loading_placeholder.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/velora_button.dart';
import '../pass_screen.dart';
import 'account_pages.dart';

AccountPage accountStatusPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.accountStatusTitle,
    builder: (context) => const AccountStatusBody(),
  );
}

/// What the systems behind VeloraUG say about the account, each from its
/// own source: the sign-in provider for the email, the API for the plan and
/// any deletion. A value no source can confirm shows as unknown.
class AccountStatusBody extends StatefulWidget {
  const AccountStatusBody({super.key});

  @override
  State<AccountStatusBody> createState() => _AccountStatusBodyState();
}

class _AccountStatusBodyState extends State<AccountStatusBody> {
  PassStatus? _pass;
  bool _passUnknown = false;
  DeletionStatus? _deletion;
  bool _deletionUnknown = false;
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
    final playback = PlaybackScope.of(context);
    final account = accountApiOf(context);
    setState(() {
      _pass = null;
      _deletion = null;
      _passUnknown = playback == null;
      _deletionUnknown = account == null;
    });
    await Future.wait([
      if (playback != null)
        playback.myPass().then(
          (pass) {
            if (mounted) setState(() => _pass = pass);
          },
          onError: (Object _) {
            if (mounted) setState(() => _passUnknown = true);
          },
        ),
      if (account != null)
        account.deletionStatus().then(
          (deletion) {
            if (mounted) setState(() => _deletion = deletion);
          },
          onError: (Object _) {
            if (mounted) setState(() => _deletionUnknown = true);
          },
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = AuthScope.of(context)!;
    final pass = _pass;
    final current = pass?.current;
    final deletion = _deletion;

    final verified = auth.emailVerified;
    final Widget membership;
    if (_passUnknown) {
      membership = StatusBadge(
        label: l.statusUnknown,
        tone: StatusTone.neutral,
      );
    } else if (pass == null) {
      membership = VeloraLoadingRegion(
        label: l.loading,
        child: const VeloraSkeleton(width: 120, height: 20),
      );
    } else if (pass.active && current != null) {
      membership = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.xxs,
        children: [
          StatusBadge(
            label: l.membershipActive,
            tone: StatusTone.success,
            icon: Icons.check_circle_outline,
          ),
          Text(current.planName),
          Text(l.membershipExpires(formatPassEnd(context, current.endsAt))),
          if (pass.queued.isNotEmpty)
            Text(
              l.membershipRenewsUntil(
                formatPassEnd(context, pass.queued.last.endsAt),
              ),
            ),
        ],
      );
    } else {
      membership = StatusBadge(
        label: l.membershipNone,
        tone: StatusTone.neutral,
      );
    }

    return ScreenBody(
      heading: l.accountStatusTitle,
      intro: l.accountStatusIntro,
      children: [
        AccountCard(
          title: l.statusSignIn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xs,
            children: [
              if (auth.email case final email?) Text(email),
              StatusBadge(
                label: switch (verified) {
                  true => l.emailVerified,
                  false => l.emailNotVerified,
                  null => l.emailVerificationUnknown,
                },
                tone: switch (verified) {
                  true => StatusTone.success,
                  false => StatusTone.warning,
                  null => StatusTone.neutral,
                },
              ),
              Text(
                l.statusFromSignIn,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AccountCard(
          title: l.statusMembership,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xs,
            children: [
              membership,
              Text(
                l.statusFromVeloraUG,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_deletionUnknown ||
            (deletion != null && deletion.state != DeletionState.none))
          AccountCard(
            title: l.statusDeletion,
            child: StatusBadge(
              label: _deletionUnknown
                  ? l.statusUnknown
                  : (deletion!.state == DeletionState.pending
                        ? l.deletionPending
                        : l.deletionCompleted),
              tone: _deletionUnknown ? StatusTone.neutral : StatusTone.warning,
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: VeloraButton(
            label: l.refresh,
            icon: Icons.refresh,
            variant: VeloraButtonVariant.secondary,
            onPressed: _load,
          ),
        ),
      ],
    );
  }
}
