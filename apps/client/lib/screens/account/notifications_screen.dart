import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/velora_button.dart';
import 'account_pages.dart';
import 'history_screen.dart' show formatWhen;

AccountPage notificationsPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.notificationsTitle,
    builder: (context) => const NotificationsBody(),
  );
}

/// What a notification says, written here from its kind, so nothing the
/// server sends is shown as text.
(IconData, String, String) notificationText(
  AppLocalizations l,
  AppNotification n,
) {
  final plan = n.planName ?? l.yourPlan;
  return switch (n.kind) {
    NotificationKind.paymentCompleted => (
      Icons.check_circle_outline,
      l.noticePaymentCompletedTitle,
      l.noticePaymentCompletedBody(plan),
    ),
    NotificationKind.paymentRefunded => (
      Icons.undo,
      l.noticePaymentRefundedTitle,
      l.noticePaymentRefundedBody(plan),
    ),
    NotificationKind.passEnding => (
      Icons.schedule,
      l.noticePassEndingTitle,
      l.noticePassEndingBody(plan),
    ),
    NotificationKind.passEnded => (
      Icons.event_busy_outlined,
      l.noticePassEndedTitle,
      l.noticePassEndedBody(plan),
    ),
    NotificationKind.deviceRemoved => (
      Icons.phonelink_erase,
      l.noticeDeviceRemovedTitle,
      l.noticeDeviceRemovedBody(n.deviceLabel ?? l.aDevice),
    ),
  };
}

/// The in-app inbox: real events on the viewer's account from the last 90
/// days. It doesn't depend on push notifications.
class NotificationsBody extends StatefulWidget {
  const NotificationsBody({super.key});

  @override
  State<NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends State<NotificationsBody> {
  NotificationInbox? _inbox;
  AccountFailure? _failure;
  bool _marking = false;
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
      _failure = api == null ? AccountFailure.unreachable : null;
      _inbox = null;
    });
    if (api == null) return;
    try {
      final inbox = await api.notifications();
      if (mounted) setState(() => _inbox = inbox);
    } on AccountException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  /// Marks read on the server, then shows it: never read before it is.
  Future<void> _markRead([List<String> ids = const []]) async {
    final api = accountApiOf(context);
    if (api == null || _marking) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _marking = true);
    try {
      await api.markRead(ids);
      final inbox = await api.notifications();
      if (mounted) setState(() => _inbox = inbox);
    } on AccountException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(accountFailureMessage(l, error.failure))),
        );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inbox = _inbox;
    final failure = _failure;
    return RefreshIndicator(
      onRefresh: _load,
      child: ScreenBody(
        heading: l.notificationsTitle,
        intro: l.notificationsIntro,
        status: inbox == null || inbox.unread == 0
            ? null
            : Semantics(
                liveRegion: true,
                child: Text(l.notificationsUnread(inbox.unread)),
              ),
        children: [
          if (failure != null)
            ErrorState(
              title: l.notificationsLoadFailed,
              message: accountFailureMessage(l, failure),
              onRetry: _load,
            )
          else if (inbox == null)
            VeloraLoadingRegion(
              label: l.loading,
              child: const Column(
                spacing: VeloraSpacing.sm,
                children: [
                  VeloraSkeleton(height: 64),
                  VeloraSkeleton(height: 64),
                ],
              ),
            )
          else if (inbox.notifications.isEmpty)
            EmptyState(
              icon: Icons.notifications_none,
              title: l.notificationsEmptyTitle,
              message: l.notificationsEmptyMessage,
            )
          else ...[
            if (inbox.unread > 0)
              Align(
                alignment: Alignment.centerRight,
                child: VeloraButton(
                  label: l.markAllRead,
                  icon: Icons.done_all,
                  variant: VeloraButtonVariant.tertiary,
                  isLoading: _marking,
                  loadingLabel: l.saving,
                  onPressed: () => _markRead(),
                ),
              ),
            Card.outlined(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, n) in inbox.notifications.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _NotificationTile(
                      key: ValueKey(n.id),
                      notification: n,
                      onRead: n.read || _marking
                          ? null
                          : () => _markRead([n.id]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.onRead,
  });

  final AppNotification notification;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final (icon, title, body) = notificationText(l, notification);
    final unread = !notification.read;
    final when = formatWhen(context, notification.at);
    return Semantics(
      label: [if (unread) l.unread, title, body, when].join('. '),
      excludeSemantics: true,
      button: onRead != null,
      onTap: onRead,
      child: ListTile(
        onTap: onRead,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon),
            if (unread)
              const Positioned(
                right: -2,
                top: -2,
                child: CircleAvatar(
                  radius: 4,
                  backgroundColor: VeloraColors.accentText,
                ),
              ),
          ],
        ),
        title: Text(
          title,
          style: unread
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodyMedium,
        ),
        subtitle: Text('$body\n$when'),
        isThreeLine: true,
        trailing: unread
            ? Text(
                l.unread,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: VeloraColors.accentText,
                ),
              )
            : null,
      ),
    );
  }
}
