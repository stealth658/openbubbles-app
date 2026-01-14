import 'package:bluebubbles/core/logger/logger.dart';
import 'package:get/get.dart';

/// Coordinator for immediate message updates, bypassing ObjectBox watch latency
///
/// ObjectBox query watches have 100-500ms latency before triggering listeners.
/// This coordinator provides instant update notifications for critical UI updates
/// like reactions, delivery receipts, and message edits.
class MessageUpdateCoordinator extends GetxService {
  // Map of chatGuid -> messageGuid -> update timestamp
  final Map<String, RxMap<String, RxInt>> _updateTriggers = {};

  /// Immediately trigger a UI update for a specific message
  /// This bypasses ObjectBox watch latency for instant reactivity
  void notifyMessageUpdate(String chatGuid, String messageGuid) {
    _updateTriggers[chatGuid] ??= <String, RxInt>{}.obs;
    _updateTriggers[chatGuid]![messageGuid] = DateTime.now().millisecondsSinceEpoch.obs;

    Logger.debug("MessageUpdateCoordinator: Triggered update for message $messageGuid in chat $chatGuid",
        tag: "MessageUpdate");
  }

  /// Get the update trigger observable for a specific message
  /// Returns null if no updates have been triggered for this message
  RxInt? getUpdateTrigger(String chatGuid, String messageGuid) {
    return _updateTriggers[chatGuid]?[messageGuid];
  }

  /// Clear update trigger after processing
  /// This helps prevent memory leaks from accumulating old triggers
  void clearUpdate(String chatGuid, String messageGuid) {
    _updateTriggers[chatGuid]?.remove(messageGuid);
  }

  /// Clear all triggers for a specific chat
  /// Useful when leaving a conversation
  void clearChatUpdates(String chatGuid) {
    _updateTriggers.remove(chatGuid);
    Logger.debug("MessageUpdateCoordinator: Cleared all triggers for chat $chatGuid", tag: "MessageUpdate");
  }

  /// Clear all triggers (useful for cleanup/testing)
  void clearAll() {
    _updateTriggers.clear();
    Logger.debug("MessageUpdateCoordinator: Cleared all triggers", tag: "MessageUpdate");
  }
}

// Global instance accessor
MessageUpdateCoordinator get muc => Get.isRegistered<MessageUpdateCoordinator>()
    ? Get.find<MessageUpdateCoordinator>()
    : Get.put(MessageUpdateCoordinator());
