import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter/foundation.dart';

/// Utility class for hydrating Chat objects with contact name caching.
/// Participants/handles are lazy-loaded on demand from the database-attached objects.
class ChatHydration {
  /// Hydrates a single chat by caching contact names for participants.
  /// 
  /// Note: Participants are lazy-loaded from the database automatically when accessed.
  /// This method only caches contact names to avoid repeated lookups.
  /// 
  /// Parameters:
  /// - [chat]: The chat to hydrate
  /// - [cacheContactNames]: Whether to cache contact names for participants (default: true)
  /// 
  /// Returns the hydrated chat
  static Future<Chat> hydrate(
    Chat chat, {
    bool cacheContactNames = true,
  }) async {
    if (kIsWeb) return chat;

    // Cache contact names if requested
    if (cacheContactNames) {
      await _cacheContactNames(chat);
    }
    
    return chat;
  }

  /// Hydrates multiple chats by caching contact names.
  /// 
  /// This is more efficient than calling [hydrate] individually for each chat
  /// as it processes all chats at once.
  /// 
  /// Parameters:
  /// - [chats]: The list of chats to hydrate
  /// - [cacheContactNames]: Whether to cache contact names for participants (default: true)
  /// 
  /// Returns the list of hydrated chats
  static Future<List<Chat>> hydrateAll(
    List<Chat> chats, {
    bool cacheContactNames = true,
  }) async {
    if (kIsWeb || chats.isEmpty) return chats;

    for (final chat in chats) {
      await ChatHydration.hydrate(
        chat,
        cacheContactNames: cacheContactNames,
      );
    }
    
    return chats;
  }

  /// Cache contact names for all participants in a chat
  static Future<void> _cacheContactNames(Chat chat) async {
    Database.runInTransaction(TxMode.read, () {
      for (final handle in chat.handles) {
        final contactCount = handle.contactsV2.length;
        
        // Cache the contact name while we're in the transaction
        if (contactCount > 0) {
          handle.cachedContactName = handle.contactsV2.first.displayName;
        } else {
          handle.cachedContactName = null;
        }
      }
    });
  }
}
