import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Matrix4;
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level print output options shared by every print path
/// (Android TSPL bitmap over Bluetooth, Windows USB/Bluetooth PDF).
///
/// Some label printers / drivers mirror the output left-to-right. Instead of
/// hard-coding a compensation, the user can toggle it in Settings.
class PrintSettings {
  PrintSettings._();

  static const String _prefMirrorHorizontal = 'pref_print_mirror_horizontal';

  /// Notifies listeners (e.g. settings UI) when an option changes.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Whether the printed label should be flipped left-to-right.
  static Future<bool> isMirrorHorizontal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefMirrorHorizontal) ?? false;
    } catch (e) {
      debugPrint('PrintSettings: failed to read mirror option: $e');
      return false;
    }
  }

  static Future<void> setMirrorHorizontal(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMirrorHorizontal, value);
      revision.value++;
    } catch (e) {
      debugPrint('PrintSettings: failed to save mirror option: $e');
    }
  }

  /// Wraps a PDF page body so it is flipped horizontally when [mirror] is on.
  static pw.Widget wrapPdf(pw.Widget child, {required bool mirror}) {
    if (!mirror) return child;
    return pw.Transform(
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      alignment: pw.Alignment.center,
      child: child,
    );
  }
}
