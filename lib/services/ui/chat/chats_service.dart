import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/state/chat_state.dart';
import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
ChatsService get ChatsSvc => GetIt.I<ChatsService>();

class ChatsService {
  static const batchSize = 100;
  int currentCount = 0;
  StreamSubscription? countSub;
  bool headless = false;

  final RxBool hasChats = false.obs;
  Completer<void> loadedAllChats = Completer();
  final RxBool loadedChatBatch = false.obs;
  
  /// Global unread count across all chats
  final RxInt unreadCount = 0.obs;
  
  /// Map of chat states for granular reactivity
  /// Key is the chat GUID, value is the ChatState
  /// The map itself doesn't need to be Rx because the underlying ChatState fields are
  final Map<String, ChatState> chatStates = {};
  
  /// Sorted list of chats maintained for efficient access
  /// Updated on add/update using binary search insertion O(log n + n)
  /// instead of sorting entire list O(n log n) on every access
  final List<Chat> _sortedChats = [];
  
  // ========== Helper Getters (replacing direct chats access) ==========
  
  /// Get all chats as a list (non-reactive), sorted by pin index and latest message date
  /// Returns the pre-sorted list for O(1) access instead of O(n log n) sorting
  List<Chat> get allChats {
    return _sortedChats;
  }
  
  /// Check if chats list is empty
  bool get isEmpty {
    return chatStates.isEmpty;
  }
  
  /// Get number of chats
  int get length {
    return chatStates.length;
  }
  
  /// Find chat by GUID
  Chat? findChatByGuid(String guid) {
    return chatStates[guid]?.chat;
  }
  
  /// Find chat by chat identifier
  Chat? findChatByChatIdentifier(String chatIdentifier) {
    return chatStates.values
        .map((state) => state.chat)
        .firstWhereOrNull((c) => c.chatIdentifier == chatIdentifier);
  }
  
  /// Get chat at specific index (from sorted list)
  Chat? getChatAtIndex(int index) {
    final sortedChats = getSortedChats();
    if (index < 0 || index >= sortedChats.length) return null;
    return sortedChats[index];
  }
  
  /// Get filtered chats (archived, unknown senders, pinned)
  List<Chat> getFilteredChats({
    bool? showArchived,
    bool? showUnknown,
    bool? pinnedOnly,
    bool? excludePinned,
  }) {
    var chats = allChats;
    
    // Apply archived filter
    if (showArchived != null) {
      if (showArchived) {
        chats = chats.where((e) => e.isArchived ?? false).toList();
      } else {
        chats = chats.where((e) => !(e.isArchived ?? false)).toList();
      }
    }
    
    // Apply unknown senders filter
    if (showUnknown != null && SettingsSvc.settings.filterUnknownSenders.value) {
      if (showUnknown) {
        chats = chats.where((e) => !e.isGroup && e.handles.firstOrNull?.contact == null).toList();
      } else {
        chats = chats.where((e) => e.isGroup || (!e.isGroup && e.handles.firstOrNull?.contact != null)).toList();
      }
    }
    
    // Apply pinned filter
    if (pinnedOnly == true) {
      chats = chats.where((e) => e.isPinned ?? false).toList();
    } else if (excludePinned == true) {
      chats = chats.where((e) => !(e.isPinned ?? false)).toList();
    }
    
    return chats;
  }
  
  /// Get only group chats
  List<Chat> get groupChats {
    return allChats.where((c) => c.isGroup).toList();
  }
  
  /// Get pinned chats
  List<Chat> get pinnedChats {
    return getSortedChats().where((c) => (c.pinIndex ?? -1) >= 0).toList()
      ..sort((a, b) => (a.pinIndex ?? 0).compareTo(b.pinIndex ?? 0));
  }
  
  /// Search chats by title
  List<Chat> searchChats(String query) {
    return allChats.where((element) => 
      element.getTitle().toLowerCase().replaceAll(" ", "").contains(query.toLowerCase())
    ).toList();
  }
  
  /// Get next chat in sorted list (for keyboard navigation)
  Chat? getNextChat(String currentGuid) {
    final sortedChats = getSortedChats();
    final index = sortedChats.indexWhere((e) => e.guid == currentGuid);
    if (index > -1 && index < sortedChats.length - 1) {
      return sortedChats[index + 1];
    }
    return null;
  }
  
  /// Get previous chat in sorted list (for keyboard navigation)
  Chat? getPreviousChat(String currentGuid) {
    final sortedChats = getSortedChats();
    final index = sortedChats.indexWhere((e) => e.guid == currentGuid);
    if (index > 0 && index < sortedChats.length) {
      return sortedChats[index - 1];
    }
    return null;
  }
  
  final List<Handle> webCachedHandles = [];

  void initDbWatchers() {
    if (headless) return;
    if (!kIsWeb) {
      // watch for new chats
      final countQuery = (Database.chats.query(Chat_.dateDeleted.isNull())..order(Chat_.id, flags: Order.descending))
          .watch(triggerImmediately: true);
      countSub = countQuery.listen((event) async {
        if (!SettingsSvc.settings.finishedSetup.value) return;
        final newCount = event.count();
        if (newCount > currentCount && currentCount != 0) {
          final chat = event.findFirst()!;
          if (chat.latestMessage.dateCreated!.millisecondsSinceEpoch == 0) {
            // wait for the chat.addMessage to go through
            await Future.delayed(const Duration(milliseconds: 500));
            // refresh the latest message
            chat.dbLatestMessage;
          }
          await addChat(chat);
        }
        currentCount = newCount;
      });
    } else {
      countSub = WebListeners.newChat.listen((chat) async {
        if (!SettingsSvc.settings.finishedSetup.value) return;
        await addChat(chat);
      });
    }
  }

  Future<void> init({bool force = false, bool headless = false}) async {
    this.headless = headless;
    if ((!force && !SettingsSvc.settings.finishedSetup.value) || headless) return;
    Logger.info("Fetching chats...", tag: "ChatBloc");

    reset();
    
    // Get current count from database or server
    currentCount = Chat.count() ??
        (await HttpSvc.chatCount().catchError((err) {
          Logger.info("Error when fetching chat count!", tag: "ChatBloc");
          return Response(requestOptions: RequestOptions(path: ''));
        }))
            .data['data']['total'] ??
        0;
    
    loadedAllChats = Completer();
    if (currentCount != 0) {
      hasChats.value = true;
    } else {
      loadedChatBatch.value = true;
      initDbWatchers();
      return;
    }

    // Clear existing chats to avoid duplicates on re-init
    if (chatStates.isNotEmpty) {
      chatStates.clear();
      _sortedChats.clear();
    }

    final batches = (currentCount / batchSize).ceil();
    for (int i = 0; i < batches; i++) {
      List<Chat> temp;
      if (kIsWeb) {
        temp = await cm.getChats(withLastMessage: true, limit: batchSize, offset: i * batchSize);
      } else {
        temp = await Chat.getChatsAsync(limit: batchSize, offset: i * batchSize);
      }

      if (kIsWeb) {
        webCachedHandles.addAll(temp.map((e) => e.handles).flattened.toList());
        final ids = webCachedHandles.map((e) => e.address).toSet();
        webCachedHandles.retainWhere((element) => ids.remove(element.address));
      }

      // Insert each chat at the correct position using binary search
      // This maintains proper ordering including pinIndex which DB queries cannot handle
      for (Chat c in temp) {
        if (!headless) {
          cm.createChatController(c, active: cm.activeChat?.chat.guid == c.guid);
        }
        
        // Create ChatState and add to map
        chatStates[c.guid] = ChatState(c);
        _setupChatStateListeners(chatStates[c.guid]!);
        
        // Add to sorted list
        _insertChatSorted(c);
      }
      loadedChatBatch.value = true;
    }

    loadedAllChats.complete();
    Logger.info("Finished fetching chats (${chatStates.length}).", tag: "ChatBloc");
    
    // Initialize watchers AFTER loading all chats to avoid duplicates
    initDbWatchers();

    if (kIsDesktop && Platform.isWindows) {
      /* ----- IMESSAGE:// HANDLER ----- */
      final _appLinks = AppLinks();
      _appLinks.stringLinkStream.listen((String string) async {
        if (!string.startsWith("imessage://")) return;
        final uri = Uri.tryParse(string
            .replaceFirst("imessage://", "imessage:")
            .replaceFirst("&body=", "?body=")
            .replaceFirst(RegExp(r'/$'), ''));
        if (uri == null) return;

        final address = uri.path;
        final handle = Handle.findOne(addressAndService: Tuple2(address, "iMessage"));
        NavigationSvc.closeSettings(Get.context!);
        await NavigationSvc.pushAndRemoveUntil(
          Get.context!,
          ChatCreator(
            initialSelected: [SelectedContact(displayName: handle?.displayName ?? address, address: address)],
            initialText: uri.queryParameters['body'],
          ),
          (route) => route.isFirst,
        );
      });
    }
  }

  /// Get ChatState for a specific chat GUID
  ChatState? getChatState(String guid) {
    return chatStates[guid];
  }
  
  /// Set up listeners on a ChatState to track unread count changes
  void _setupChatStateListeners(ChatState chatState) {
    // Listen to hasUnreadMessage changes to update global unread count
    chatState.hasUnreadMessage.listen((hasUnread) {
      _recalculateUnreadCount();
    });
  }
  
  /// Recalculate the global unread count based on all chat states
  void _recalculateUnreadCount() {
    final count = chatStates.values.where((state) => state.hasUnreadMessage.value).length;
    if (unreadCount.value != count) {
      unreadCount.value = count;
    }
  }

  void close() {
    countSub?.cancel();
  }

  /// Get sorted chats (pin index first, then by latest message date)
  /// Returns the pre-sorted list - sorting is maintained on add/update
  List<Chat> getSortedChats() {
    return _sortedChats;
  }
  
  /// Find the correct insertion index for a chat using binary search
  /// Returns the index where the chat should be inserted to maintain sort order
  int _findInsertionIndex(Chat chat) {
    int left = 0;
    int right = _sortedChats.length;
    
    while (left < right) {
      final mid = (left + right) ~/ 2;
      final comparison = Chat.sort(chat, _sortedChats[mid]);
      
      if (comparison < 0) {
        right = mid;
      } else {
        left = mid + 1;
      }
    }
    
    return left;
  }
  
  /// Insert a chat into the sorted list at the correct position
  void _insertChatSorted(Chat chat) {
    final index = _findInsertionIndex(chat);
    _sortedChats.insert(index, chat);
  }
  
  /// Reposition a chat in the sorted list (used when chat is updated)
  void _repositionChat(Chat chat) {
    // Remove from current position
    _sortedChats.removeWhere((c) => c.guid == chat.guid);
    // Insert at correct position
    _insertChatSorted(chat);
  }

  /// Public sort method for external callers
  /// Sorting is now implicit in the map structure and accessed via getSortedChats()
  void sort() {
    if (headless) return;
    Logger.info('[SORT] Chat order maintained via sorted list', tag: 'ChatBloc');
    // No-op since sorted list is maintained on add/update
  }

  bool updateChat(Chat updated, {bool override = false}) {
    if (headless) return false;
    final state = chatStates[updated.guid];
    if (state != null) {
      final toUpdate = state.chat;
      final merged = override ? updated : updated.merge(toUpdate);
      
      // Only update if actually different to avoid unnecessary rebuilds
      if (merged != toUpdate) {
        // Update the chat state which will trigger reactive updates
        state.updateFromChat(merged);
        
        // Reposition in sorted list if sort order might have changed
        // (e.g., new message updates latestMessage.dateCreated, or pin status changed)
        _repositionChat(merged);
      }
      return true;
    }

    return false;
  }

  Future<void> addChat(Chat toAdd) async {
    if (headless) return;
    // Check if chat already exists
    if (chatStates.containsKey(toAdd.guid)) {
      // Update existing chat instead
      updateChat(toAdd, override: true);
      return;
    }
    
    // Create new ChatState and add to map
    chatStates[toAdd.guid] = ChatState(toAdd);
    _setupChatStateListeners(chatStates[toAdd.guid]!);
    
    // Insert into sorted list at correct position
    _insertChatSorted(toAdd);
    
    if (!headless) {
      cm.createChatController(toAdd);
    }
  }

  void removeChat(Chat toRemove) {
    if (headless) return;
    chatStates.remove(toRemove.guid);
    _sortedChats.removeWhere((c) => c.guid == toRemove.guid);
  }

  void markAllAsRead() {
    final _chats = Database.chats.query(Chat_.hasUnreadMessage.equals(true)).build().find();
    for (Chat c in _chats) {
      c.hasUnreadMessage = false;
      MethodChannelSvc.invokeMethod(
        "delete-notification",
        {
          "notification_id": c.id,
          "tag": NotificationsService.NEW_MESSAGE_TAG
        }
      );
      if (SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.settings.privateMarkChatAsRead.value) {
        HttpSvc.markChatRead(c.guid);
      }
      
      // Update chat state if it exists
      final state = chatStates[c.guid];
      if (state != null) {
        state.hasUnreadMessage.value = false;
      }
    }
    Database.chats.putMany(_chats);
  }

  void updateChatPinIndex(int oldIndex, int newIndex) {
    final chatList = getSortedChats();
    final items = List<Chat>.from(chatList.where((c) => (c.pinIndex ?? -1) >= 0));
    items.sort((a, b) => (a.pinIndex ?? 0).compareTo(b.pinIndex ?? 0));
    
    final item = items[oldIndex];

    // Remove the item at the old index, and re-add it at the newIndex
    // We dynamically subtract 1 from the new index depending on if the newIndex is > the oldIndex
    items.removeAt(oldIndex);
    items.insert(newIndex + (oldIndex < newIndex ? -1 : 0), item);

    // Move the pinIndex for each of the chats, and save the pinIndex in the DB
    items.forEachIndexed((i, e) async {
      e.pinIndex = i;
      await e.saveAsync(updatePinIndex: true);
      
      // Update chat state
      final state = chatStates[e.guid];
      if (state != null) {
        state.pinIndex.value = i;
      }
    });
  }

  void removePinIndices() {
    final chatList = getSortedChats();
    // Create a snapshot to avoid concurrent modification during iteration
    final pinnedChats = List<Chat>.from(chatList.where((c) => (c.pinIndex ?? -1) >= 0 && c.pinIndex != null));
    for (var element in pinnedChats) {
      element.pinIndex = null;
      element.saveAsync(updatePinIndex: true);
      
      // Update chat state
      final state = chatStates[element.guid];
      if (state != null) {
        state.pinIndex.value = null;
      }
    }
  }

  Future<void> updateShareTargets() async {
    if (Platform.isAndroid) {
      StartupTasks.waitForUI().then((_) async {
        // Create a snapshot to avoid concurrent modification during iteration
        final chatList = getSortedChats();
        final chatSnapshot = chatList.where((e) => !isNullOrEmpty(e.title)).take(4).toList();
        for (Chat c in chatSnapshot) {
          await MethodChannelSvc.invokeMethod("push-share-targets", {
            "title": c.title,
            "guid": c.guid,
            "icon": await avatarAsBytes(chat: c, quality: 256),
          });
        }
      });
    }
  }

  void reset({bool reinitWatchers = false}) {
    currentCount = 0;
    hasChats.value = false;
    chatStates.clear();
    _sortedChats.clear();
    loadedAllChats = Completer();
    loadedChatBatch.value = false;
    webCachedHandles.clear();

    countSub?.cancel();
    if (reinitWatchers) {
      initDbWatchers();
    }
  }
}
