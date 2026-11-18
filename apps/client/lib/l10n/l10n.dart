import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.watch`: every visible string comes from lib/l10n/app_en.arb.
/// Names of VJs, languages and titles are data, and aren't translated.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
