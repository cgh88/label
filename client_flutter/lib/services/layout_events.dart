import 'package:flutter/foundation.dart';

/// Bumped whenever label layout settings (font sizes, visible lines, padding,
/// gap) are changed in the Settings tab, so any open label preview can reload
/// immediately instead of waiting for a tab switch.
final ValueNotifier<int> layoutSettingsRevision = ValueNotifier<int>(0);
