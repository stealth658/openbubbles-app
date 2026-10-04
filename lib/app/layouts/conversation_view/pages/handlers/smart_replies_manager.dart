import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_smart_reply/google_mlkit_smart_reply.dart' hide Message;

/// Manages smart reply generation via ML Kit.
///
/// Responsibilities:
/// - Initialize ML Kit smart reply processor on startup
/// - Add incoming messages to conversation context
/// - Generate reply suggestions when new messages arrive
/// - Clear suggestions when user sends a message
/// - Refresh suggestions when non-user messages arrive
class SmartRepliesManager {
  /// Rolling context window size. ML Kit's own conversation list has no cap, so this
  /// class enforces one to keep suggestions scoped to recent context and to bound
  /// memory growth for chats that stay mounted for a long time (desktop, tablet split-view).
  static const int _maxContextMessages = 5;

  late final SmartReply smartReply;

  final RxList<String> smartReplies = <String>[].obs;

  final List<Message> _context = [];

  SmartRepliesManager() {
    smartReply = SmartReply();
  }

  bool shouldShowSmartReplies(bool messagesEmpty) {
    return !messagesEmpty && smartReplies.isNotEmpty;
  }

  void addMessageToContext(Message message) {
    _context.add(message);
    if (_context.length > _maxContextMessages) {
      _context.removeRange(0, _context.length - _maxContextMessages);
    }
    _rebuildConversation();
  }

  void _rebuildConversation() {
    smartReply.clearConversation();
    for (final message in _context) {
      final text = sanitizeForMlKit(message.fullText);
      if (message.isFromMe ?? false) {
        smartReply.addMessageToConversationFromLocalUser(
          text,
          message.dateCreated!.millisecondsSinceEpoch,
        );
      } else {
        smartReply.addMessageToConversationFromRemoteUser(
          text,
          message.dateCreated!.millisecondsSinceEpoch,
          message.handleRelation.target?.address ?? "participant",
        );
      }
    }
  }

  /// Serialises Gemini requests: a burst of incoming messages must not fan out
  /// into several concurrent on-device inferences for the same chat.
  Future<void>? _geminiInFlight;

  /// Generate smart reply suggestions based on current conversation context.
  /// Call this after adding messages or when new context arrives.
  ///
  /// OpenBubbles: when on-device AI is enabled and the Prompt API is usable,
  /// suggestions come from Gemini Nano, which reads the actual conversation and
  /// writes replies in its tone, instead of ML Kit's small canned-reply model.
  /// ML Kit stays as the fallback for anything Gemini declines or garbles.
  Future<void> generateSuggestions({Chat? chat}) async {
    if (chat != null && GenAi.enabled && GenAi.available('prompt')) {
      final pending = _geminiInFlight;
      if (pending != null) return pending;
      final run = () async {
        try {
          final replies = await GenAi.suggestReplies(chat);
          if (replies.isNotEmpty) {
            smartReplies.value = replies;
            return;
          }
        } catch (e) {
          Logger.warn("Gemini reply suggestions failed, falling back to ML Kit: $e", tag: 'GenAI');
        }
        await _mlKitSuggestions();
      }();
      _geminiInFlight = run;
      try {
        await run;
      } finally {
        _geminiInFlight = null;
      }
      return;
    }
    await _mlKitSuggestions();
  }

  Future<void> _mlKitSuggestions() async {
    try {
      SmartReplySuggestionResult results = await smartReply.suggestReplies();

      if (results.status == SmartReplySuggestionResultStatus.success) {
        smartReplies.value = results.suggestions;
      } else {
        smartReplies.clear();
      }
    } catch (e) {
      // Silently fail if ML Kit is unavailable
    }
  }

  /// Clean up resources (close ML Kit processor).
  void dispose() {
    if (!kIsWeb && !kIsDesktop) {
      smartReply.close();
    }
  }
}
