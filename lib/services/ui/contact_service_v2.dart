import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/interfaces/contact_v2_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/ui/chat/chats_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';

// ignore: non_constant_identifier_names
ContactServiceV2 get ContactsSvcV2 => GetIt.I<ContactServiceV2>();

/// ContactServiceV2 - UI-side service for the new contact architecture
/// This service manages the state and triggers isolate operations
/// Follows the architecture outlined in FR-1.md Section III
class ContactServiceV2 {
  final tag = "ContactServiceV2";

  /// Reactive map to track handle updates by Handle ID
  /// When a handle's contact information changes, we update this map
  /// with a timestamp. UI components can observe specific handle IDs.
  final RxMap<int, int> handleUpdateStatus = RxMap<int, int>();

  /// Whether we have permission to access contacts
  bool _hasContactAccess = false;

  /// Check if we have contact access permission
  Future<bool> get hasContactAccess async {
    if (_hasContactAccess) return true;
    _hasContactAccess = await _canAccessContacts();
    return _hasContactAccess;
  }

  /// Check if we can access contacts
  Future<bool> _canAccessContacts() async {
    if (kIsWeb || kIsDesktop) {
      int versionCode = (await SettingsSvc.getServerDetails()).item4;
      return versionCode >= 42;
    } else {
      return (await Permission.contacts.status).isGranted;
    }
  }

  /// Request contact permission from the user
  Future<bool> requestContactPermission() async {
    if (kIsWeb || kIsDesktop) return false;

    final status = await Permission.contacts.request();
    _hasContactAccess = status.isGranted;

    if (_hasContactAccess) {
      Logger.info('[ContactServiceV2] Contact permission granted');
    } else {
      Logger.warn('[ContactServiceV2] Contact permission denied');
    }

    return _hasContactAccess;
  }

  /// Initialize the contact service
  /// [headless] - If true, skips operations that require UI or user interaction (for isolate usage)
  Future<void> init({bool headless = false}) async {
    Logger.info('[ContactServiceV2] Initializing... (headless: $headless)');
    
    // Skip contact access checks and fetching in headless mode
    // The isolate doesn't need to fetch contacts, it just needs to be ready to process them
    if (headless) {
      Logger.info('[ContactServiceV2] Running in headless mode, skipping contact fetch');
      return;
    }
    
    // Check contact access
    await hasContactAccess;

    // If we have access, always fetch fresh contacts on startup
    // This ensures we pick up any contact changes that happened while the app was closed
    if (_hasContactAccess) {
      Logger.info('[ContactServiceV2] Has contact access, fetching contacts from device');
      await fetchAndMatchContacts();
      Logger.info('[ContactServiceV2] Contact fetch completed');
    } else {
      Logger.info('[ContactServiceV2] No contact access, skipping contact fetch');
    }
  }

  /// Fetch all contacts and match them to handles
  /// This triggers the GlobalIsolate to do the heavy lifting
  /// Returns a list of handle IDs that were affected
  Future<List<int>> fetchAndMatchContacts() async {
    if (!_hasContactAccess) {
      Logger.warn('[ContactServiceV2] Cannot fetch contacts without permission');
      return [];
    }

    try {
      Logger.info('[ContactServiceV2] Starting contact fetch and match...');
      final affectedHandleIds = await ContactV2Interface.fetchAndMatchContactsAsync();
      
      // Notify UI about updated handles
      notifyHandlesUpdated(affectedHandleIds);
      
      Logger.info('[ContactServiceV2] Completed contact fetch and match');
      return affectedHandleIds;
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error fetching and matching contacts', error: e, trace: stack);
      return [];
    }
  }

  /// Check for contact database changes
  /// This is designed to be called periodically by workmanager
  /// Returns true if changes were detected and a re-sync was performed
  Future<bool> checkForContactChanges() async {
    if (!_hasContactAccess) return false;

    try {
      Logger.info('[ContactServiceV2] Checking for contact changes...');
      final hasChanges = await ContactV2Interface.checkContactChangesAsync();
      
      if (hasChanges) {
        Logger.info('[ContactServiceV2] Contact changes detected');
      }
      
      return hasChanges;
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error checking for contact changes', error: e, trace: stack);
      return false;
    }
  }

  /// Manually trigger a contact refresh
  /// This will fetch all contacts and match them to handles
  Future<List<int>> refreshContacts() async {
    if (!_hasContactAccess) {
      Logger.warn('[ContactServiceV2] Cannot refresh contacts without permission');
      return [];
    }

    try {
      Logger.info('[ContactServiceV2] Starting manual contact refresh...');
      final affectedHandleIds = await ContactV2Interface.refreshContactsAsync();
      
      // Notify UI about updated handles
      notifyHandlesUpdated(affectedHandleIds);
      
      Logger.info('[ContactServiceV2] Completed manual contact refresh');
      return affectedHandleIds;
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error refreshing contacts', error: e, trace: stack);
      return [];
    }
  }

  /// Get a ContactV2 for a specific handle ID
  /// This retrieves the contact from the isolate/database
  Future<ContactV2?> getContactForHandle(int handleId) async {
    try {
      final contacts = await ContactV2Interface.getContactsForHandlesAsync(
        handleIds: [handleId],
      );

      if (contacts.isEmpty) return null;
      return ContactV2.fromMap(contacts.first);
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error getting contact for handle $handleId', error: e, trace: stack);
      return null;
    }
  }

  /// Get ContactV2 entities for multiple handle IDs
  Future<List<ContactV2>> getContactsForHandles(List<int> handleIds) async {
    try {
      final contactMaps = await ContactV2Interface.getContactsForHandlesAsync(
        handleIds: handleIds,
      );

      return contactMaps.map((m) => ContactV2.fromMap(m)).toList();
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error getting contacts for handles', error: e, trace: stack);
      return [];
    }
  }

  /// Notify the UI that certain handles have been updated
  /// This updates the handleUpdateStatus map with the current timestamp
  /// UI components observing these handle IDs will rebuild
  void notifyHandlesUpdated(List<int> handleIds) {
    if (handleIds.isEmpty) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final id in handleIds) {
      handleUpdateStatus[id] = timestamp;
    }
    
    // Update chats that have these handles as participants
    // This ensures chat titles and headers reflect the new contact names
    if (!kIsWeb && !kIsDesktop) {
      _updateChatsForHandles(handleIds);
    }
  }
  
  /// Update chats that contain the affected handles
  void _updateChatsForHandles(List<int> handleIds) {
    try {
      // Check if ChatsService is available yet (it might not be during initial startup)
      if (!Get.isRegistered<ChatsService>()) {
        return;
      }
      
      // Find all chats that have any of these handles as participants
      for (final handleId in handleIds) {
        final handle = Database.handles.get(handleId);
        if (handle == null) continue;
        
        // Get all chats this handle participates in
        final chatsWithHandle = Database.chats
            .query(Chat_.dateDeleted.isNull())
            .build()
            .find()
            .where((chat) => chat.handles.any((p) => p.id == handleId))
            .toList();
        
        // Update each chat in the ChatsService to trigger UI updates
        for (final chat in chatsWithHandle) {
          // Force the chat to recalculate its title
          chat.title = null;
          ChatsService chats = Get.find<ChatsService>();
          chats.updateChat(chat, shouldSort: false);
        }
      }
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error updating chats for handles', error: e, trace: stack);
    }
  }

  /// Clear the update status for a specific handle
  void clearHandleUpdateStatus(int handleId) {
    handleUpdateStatus.remove(handleId);
  }

  /// Clear all update statuses
  void clearAllUpdateStatuses() {
    handleUpdateStatus.clear();
  }

  /// Get the timestamp of the last update for a specific handle
  /// Returns null if the handle has never been updated
  int? getLastUpdateTimestamp(int handleId) {
    return handleUpdateStatus[handleId];
  }

  /// Check if a handle has been updated (exists in the update status map)
  bool isHandleUpdated(int handleId) {
    return handleUpdateStatus.containsKey(handleId);
  }

  /// Get a contact by address (email or phone number)
  /// This will search through all contacts to find a match
  Future<ContactV2?> getContact(String address) async {
    try {
      final contactMap = await ContactV2Interface.getContactByAddressAsync(address: address);
      if (contactMap == null) return null;
      return ContactV2.fromMap(contactMap);
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error getting contact by address', error: e, trace: stack);
      return null;
    }
  }

  /// Match a handle to its associated contact
  /// Returns the contact if found, null otherwise
  Future<ContactV2?> matchHandleToContact(Handle handle) async {
    if (!_hasContactAccess) return null;

    try {
      final contact = await getContactForHandle(handle.id!);
      return contact;
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error matching handle to contact', error: e, trace: stack);
      return null;
    }
  }

  /// Get all contacts from the database
  /// Returns a list of all ContactV2 entities
  Future<List<ContactV2>> getAllContacts() async {
    try {
      final contactMaps = await ContactV2Interface.getAllContactsAsync();
      return contactMaps.map((m) => ContactV2.fromMap(m)).toList();
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error getting all contacts', error: e, trace: stack);
      return [];
    }
  }

  /// Fetch network contacts for web/desktop
  /// This fetches contacts from the server instead of the device
  Future<List<ContactV2>> fetchNetworkContacts({Function(String)? logger}) async {
    if (!kIsWeb && !kIsDesktop) {
      Logger.warn('[ContactServiceV2] fetchNetworkContacts is only for web/desktop');
      return [];
    }

    try {
      logger?.call("Fetching contacts from server...");
      final contactMaps = await ContactV2Interface.fetchNetworkContactsAsync();
      logger?.call("Fetched ${contactMaps.length} contacts");
      
      final contacts = contactMaps.map((m) => ContactV2.fromMap(m)).toList();
      
      // Notify about all handles that might have been updated
      final allHandleIds = contacts
          .expand((c) => c.handles)
          .where((h) => h.id != null)
          .map((h) => h.id!)
          .toList();
      
      if (allHandleIds.isNotEmpty) {
        notifyHandlesUpdated(allHandleIds);
      }
      
      return contacts;
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error fetching network contacts', error: e, trace: stack);
      logger?.call("Error fetching contacts: $e");
      return [];
    }
  }

  /// Get avatar data for a contact by ID
  /// Returns the avatar as Uint8List if available
  Future<Uint8List?> getContactAvatar(String nativeContactId) async {
    try {
      return await ContactV2Interface.getContactAvatarAsync(nativeContactId: nativeContactId);
    } catch (e, stack) {
      Logger.error('[ContactServiceV2] Error getting contact avatar', error: e, trace: stack);
      return null;
    }
  }
}
