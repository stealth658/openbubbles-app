import 'dart:async';

import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_io/io.dart';

/// Diagnoses the "blank space where the keyboard was" state seen after leaving a
/// conversation (2026-10-11): every page is laid out as if the keyboard were still
/// open, although no keyboard is on screen.
///
/// That picture has three possible sources and the app log could not tell them
/// apart, so this compares the two ends directly: the bottom inset the Flutter
/// engine last gave the framework, and what Android reports for the IME right now
/// (see ImeStateHandler.kt).
///
/// * engine inset > 0, Android says IME hidden: the engine kept a stale inset.
///   The window is asked to dispatch its insets again and the outcome is logged.
/// * both > 0: the keyboard (or the IME window) really is still up.
/// * engine inset 0: the framework has the right value and the blank space comes
///   from a widget above the page.
class ImeInsetCheck {
  static const _tag = "ImeInsets";

  static double get _engineBottom =>
      WidgetsBinding.instance.platformDispatcher.views.firstOrNull?.viewInsets.bottom ?? 0;

  /// Called when a conversation closes. Checks once the keyboard's own hide
  /// animation has had time to finish, and once more later.
  static void afterLeavingChat() {
    if (kIsWeb || !Platform.isAndroid) return;
    for (final ms in const [900, 2500]) {
      Timer(Duration(milliseconds: ms), () => unawaited(_check("left chat +${ms}ms")));
    }
  }

  static Future<void> _check(String when) async {
    try {
      final engine = _engineBottom;
      if (engine <= 0) return; // nothing reserved; the normal case, not worth a log line
      // Straight to the channel: MethodChannelSvc.invokeMethod logs every call.
      final native = await MethodChannelSvc.channel.invokeMethod("ime-state");
      if (native is! Map) return;
      final visible = native["visible"] == true;
      final bottom = (native["bottom"] as num?)?.toInt() ?? 0;
      if (visible || bottom > 0) {
        Logger.info("$when: engine inset ${engine.round()}px, Android IME visible=$visible bottom=${bottom}px "
            "(keyboard still up)", tag: _tag);
        return;
      }
      Logger.warn("$when: STALE keyboard inset. Engine holds ${engine.round()}px, Android reports the IME hidden "
          "(bottom 0). Re-dispatching window insets.", tag: _tag);
      await MethodChannelSvc.channel.invokeMethod("ime-state", {"reapply": true});
      await Future.delayed(const Duration(milliseconds: 400));
      Logger.warn("after re-dispatch: engine inset ${_engineBottom.round()}px", tag: _tag);
    } catch (e, s) {
      Logger.warn("check failed", error: e, trace: s, tag: _tag);
    }
  }
}
