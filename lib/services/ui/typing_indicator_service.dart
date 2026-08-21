import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
TypingIndicatorService get TypingIndicatorSvc => GetIt.I<TypingIndicatorService>();

/// Tracks which chat we are currently showing a typing indicator in, so it can
/// be cleared when the app backgrounds.
///
/// OpenBubbles: upstream sends typing indicators from the GlobalIsolate via
/// [ChatInterface] → `ChatActions` → `HttpSvc.chat.startTyping`. That isolate
/// never registers [backend] and has no rustpush native state (see
/// `StartupTasks.initGlobalIsolateServices`), so under rustpush the round-trip
/// would silently no-op. When there is no remote BlueBubbles server we therefore
/// send the typing message from this (UI) isolate through [backend] instead —
/// which is also the only path that can carry the staged iMessage app's icon.
///
/// This service is only registered on the UI isolate.
class TypingIndicatorService extends GetxController {
  Chat? _activeTypingChat;

  bool get isTyping => _activeTypingChat != null;

  Future<void> startTyping(Chat chat, [iMessageAppData? appData]) async {
    _activeTypingChat = chat;
    if (backend.getRemoteService() == null) {
      backend.startedTyping(chat, appData);
      return;
    }
    await ChatInterface.startTyping(chatGuid: chat.guid);
  }

  Future<void> stopTyping(Chat chat) async {
    if (_activeTypingChat?.guid == chat.guid) _activeTypingChat = null;
    if (backend.getRemoteService() == null) {
      backend.stoppedTyping(chat);
      return;
    }
    await ChatInterface.stopTyping(chatGuid: chat.guid);
  }

  /// Stops the active typing indicator for any chat.
  /// Called by LifecycleService before the app backgrounds.
  /// Must complete before GlobalIsolate.drainAndStop() is invoked so the
  /// HTTP request has a chance to succeed.
  Future<void> stopAllTyping() async {
    final chat = _activeTypingChat;
    if (chat == null) return;
    _activeTypingChat = null;
    if (backend.getRemoteService() == null) {
      backend.stoppedTyping(chat);
      return;
    }
    await ChatInterface.stopTyping(chatGuid: chat.guid);
  }

  /// Fire-and-forget wrapper — typing indicators are best effort and must never
  /// take down a keystroke handler or a widget's dispose().
  void startTypingSilent(Chat chat, [iMessageAppData? appData]) {
    startTyping(chat, appData).catchError((e, stack) {
      Logger.warn("Failed to send typing indicator", error: e, trace: stack, tag: "TypingIndicatorService");
    });
  }

  /// See [startTypingSilent].
  void stopTypingSilent(Chat chat) {
    stopTyping(chat).catchError((e, stack) {
      Logger.warn("Failed to clear typing indicator", error: e, trace: stack, tag: "TypingIndicatorService");
    });
  }
}
