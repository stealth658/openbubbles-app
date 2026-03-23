import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

extension DateHelpers on DateTime {
  bool isToday() {
    final now = DateTime.now();
    return now.day == day && now.month == month && now.year == year;
  }

  bool isYesterday() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return yesterday.day == day && yesterday.month == month && yesterday.year == year;
  }

  bool isWithin(DateTime other, {int? ms, int? seconds, int? minutes, int? hours, int? days}) {
    Duration diff = difference(other);
    if (ms != null) {
      return diff.inMilliseconds.abs() < ms;
    } else if (seconds != null) {
      return diff.inSeconds.abs() < seconds;
    } else if (minutes != null) {
      return diff.inMinutes.abs() < minutes;
    } else if (hours != null) {
      return diff.inHours.abs() < hours;
    } else if (days != null) {
      return diff.inDays.abs() < days;
    } else {
      throw Exception("No timerange specified!");
    }
  }
}

extension MessageErrorExtension on MessageError {
  static const codes = {
    MessageError.NO_ERROR: 0,
    MessageError.TIMEOUT: 4,
    MessageError.NO_CONNECTION: 1000,
    MessageError.BAD_REQUEST: 1001,
    MessageError.SERVER_ERROR: 1002,
  };

  int get code => codes[this]!;
}

extension ClientMessageErrorExtension on ClientMessageError {
  static const codes = {
    ClientMessageError.clientError: 10001,
    ClientMessageError.badGateway: 10002,
    ClientMessageError.gatewayTimeout: 10003,
    ClientMessageError.connectionRefused: 10004,
    ClientMessageError.notFound: 10005,
  };

  static const friendlyTitles = {
    ClientMessageError.clientError: "Client Error",
    ClientMessageError.badGateway: "Bad Gateway",
    ClientMessageError.gatewayTimeout: "Gateway Timeout",
    ClientMessageError.connectionRefused: "Connection Refused",
    ClientMessageError.notFound: "Not Found",
  };

  int get code => codes[this]!;
  String get friendlyTitle => friendlyTitles[this]!;

  /// Returns the [ClientMessageError] whose code matches [code], or null if
  /// the code belongs to a server-side error.
  static ClientMessageError? fromCode(int code) {
    for (final entry in codes.entries) {
      if (entry.value == code) return entry.key;
    }
    return null;
  }
}

/// Returns a user-facing error message for an incoming server error code.
/// Add specific mappings in the switch statement as needed.
/// Defaults to "iMessage Error" for any unrecognised server code.
String serverErrorMessage(int code) {
  switch (code) {
    // Add specific server error code → message mappings here, e.g.:
    // case 22: return "The recipient is not registered with iMessage.";
    default:
      return "iMessage Error";
  }
}

extension EffectHelper on MessageEffect {
  bool get isBubble =>
      this == MessageEffect.slam ||
      this == MessageEffect.loud ||
      this == MessageEffect.gentle ||
      this == MessageEffect.invisibleInk;
}

/// Used when playing iMessage effects
extension WidgetLocation on GlobalKey {
  Rect? globalPaintBounds(BuildContext context) {
    double difference = context.width - NavigationSvc.width(context);
    final renderObject = currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      final tempRect = renderObject!.paintBounds.shift(offset);
      return Rect.fromLTRB(tempRect.left - difference, tempRect.top, tempRect.right - difference, tempRect.bottom);
    } else {
      return null;
    }
  }
}

/// Used when rendering message widget
extension TextBubbleColumn on List<Widget> {
  List<Widget> conditionalReverse(bool isFromMe) {
    if (isFromMe) return this;
    return reversed.toList();
  }
}

extension NonZero on int? {
  int? get nonZero => (this ?? 0) == 0 ? null : this;
}

extension FriendlySize on double {
  String getFriendlySize({int decimals = 2, bool withSuffix = true}) {
    double size = this / 1024000.0;
    String postfix = "MB";

    if (size < 1) {
      size = size * 1024;
      postfix = "KB";
    } else if (size > 1024) {
      size = size / 1024;
      postfix = "GB";
    }

    return "${size.toStringAsFixed(decimals)}${withSuffix ? " $postfix" : ""}";
  }
}

extension ChatListHelpers on RxList<Chat> {
  /// Helper to return archived chats or all chats depending on the bool passed to it
  /// This helps reduce a vast amount of code in build methods so the widgets can
  /// update without StreamBuilders
  RxList<Chat> archivedHelper(bool archived) {
    if (archived) {
      return where((e) => e.isArchived ?? false).toList().obs;
    } else {
      return where((e) => !(e.isArchived ?? false)).toList().obs;
    }
  }

  RxList<Chat> bigPinHelper(bool pinned) {
    if (pinned) {
      return where((e) => e.isPinned ?? false).toList().obs;
    } else {
      return where((e) => !(e.isPinned ?? false)).toList().obs;
    }
  }

  RxList<Chat> unknownSendersHelper(bool unknown) {
    if (!SettingsSvc.settings.filterUnknownSenders.value) return this;
    if (unknown) {
      return where((e) => !e.isGroup && e.handles.firstOrNull?.contactsV2.isEmpty != false).toList().obs;
    } else {
      return where((e) => e.isGroup || (!e.isGroup && e.handles.firstOrNull?.contactsV2.isNotEmpty == true)).toList().obs;
    }
  }
}

extension PlatformSpecificCapitalize on String {
  String get psCapitalize {
    if (SettingsSvc.settings.skin.value == Skins.iOS) {
      return toUpperCase();
    } else {
      return this;
    }
  }
}

extension LastChars on String {
  String lastChars(int n) => substring(length - n);
}

extension UrlParsing on String {
  bool get hasUrl => urlRegex.hasMatch(this) && !kIsWeb;
}

extension ShortenString on String {
  String shorten(int length) {
    if (this.length <= length) return this;
    return "${substring(0, length)}...";
  }
}

extension FirstWord on String {
  /// Returns the first whitespace-delimited word, or the full string if there is none.
  String get firstWord {
    final spaceIdx = indexOf(' ');
    return spaceIdx == -1 ? this : substring(0, spaceIdx);
  }
}
