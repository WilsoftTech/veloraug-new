import 'package:flutter/foundation.dart';

/// True only in a debug build launched with
/// --dart-define=SHOW_DESIGN_SYSTEM=true.
///
/// This must stay a constant. A release build evaluates it to false while
/// compiling, then removes the showcase code from the output, even when the
/// define is passed. docs/step-03b-report.md records how that was checked.
const bool showcaseEnabled =
    kDebugMode && bool.fromEnvironment('SHOW_DESIGN_SYSTEM');
