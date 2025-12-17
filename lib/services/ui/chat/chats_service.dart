import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
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
  final RxList<Chat> chats = <Chat>[].obs;
  
  /// Track individual chat updates for granular reactivity
  /// UI components can observe specific chat GUIDs to only rebuild when that chat changes
  final RxMap<String, int> chatUpdateTrigger = <String, int>{}.obs;
  
  final List<Handle> webCachedHandles = [];

  void initDbWatchers() {
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
    if (!force && !SettingsSvc.settings.finishedSetup.value) return;
    Logger.info("Fetching chats...", tag: "ChatBloc");
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
      return;
    }

    final batches = (currentCount < batchSize) ? batchSize : (currentCount / batchSize).ceil();

    for (int i = 0; i < batches; i++) {
      List<Chat> temp;
      if (kIsWeb) {
        temp = await cm.getChats(withLastMessage: true, limit: batchSize, offset: i * batchSize);
      } else {
        temp = await Chat.getChatsAsync(limit: batchSize, offset: i * batchSize);
      }

      if (kIsWeb) {
        webCachedHandles.addAll(temp.map((e) => e.participants).flattened.toList());
        final ids = webCachedHandles.map((e) => e.address).toSet();
        webCachedHandles.retainWhere((element) => ids.remove(element.address));
      }

      // Insert each chat at the correct position using binary search
      // This maintains proper ordering including pinIndex which DB queries cannot handle
      for (Chat c in temp) {
        if (!headless) {
          cm.createChatController(c, active: cm.activeChat?.chat.guid == c.guid);
        }
        
        // Find correct position and insert (O(log n) + O(n) worst case)
        // More efficient than addAll + full sort (O(n log n))
        final insertIndex = _findInsertionIndex(c);
        chats.insert(insertIndex, c);
      }
      loadedChatBatch.value = true;
    }
    loadedAllChats.complete();
    Logger.info("Finished fetching chats (${chats.length}).", tag: "ChatBloc");

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

  void close() {
    countSub?.cancel();
  }

  /// Find the correct insertion index for a chat based on pin status and latest message date
  /// Uses binary search for O(log n) performance
  int _findInsertionIndex(Chat chat) {
    if (chats.isEmpty) return 0;
    
    int left = 0;
    int right = chats.length;
    
    // Binary search for the correct position
    while (left < right) {
      int mid = (left + right) ~/ 2;
      final comparison = Chat.sort(chat, chats[mid]);
      
      if (comparison < 0) {
        // chat should come before chats[mid]
        right = mid;
      } else {
        // chat should come after chats[mid]
        left = mid + 1;
      }
    }
    
    return left;
  }

  /// Reposition a chat in the list based on its current state
  /// More efficient than full sort - O(n) instead of O(n log n)
  void _repositionChat(Chat chat) {
    final currentIndex = chats.indexWhere((e) => e.guid == chat.guid);
    if (currentIndex == -1) return;
    
    // Remove from current position
    chats.removeAt(currentIndex);
    
    // Find new position and insert
    final newIndex = _findInsertionIndex(chat);
    chats.insert(newIndex, chat);
  }

  /// Public sort method for external callers (for backwards compatibility)
  /// Now performs a full sort - use sparingly, prefer updateChat with repositioning
  void sort() {
    Logger.info('[SORT] Performing full chat sort...', tag: 'ChatBloc');
    final ids = chats.map((e) => e.guid).toSet();
    chats.retainWhere((element) => ids.remove(element.guid));
    chats.sort(Chat.sort);
  }

  bool updateChat(Chat updated, {bool shouldSort = false, bool override = false}) {
    final index = chats.indexWhere((e) => updated.guid == e.guid);
    if (index != -1) {
      final toUpdate = chats[index];
      final merged = override ? updated : updated.merge(toUpdate);
      
      // Only update if actually different to avoid unnecessary rebuilds
      if (merged != toUpdate) {
        chats[index] = merged;
        
        // Trigger granular update for this specific chat
        chatUpdateTrigger[merged.guid] = DateTime.now().millisecondsSinceEpoch;
        
        if (shouldSort) {
          // Use efficient repositioning instead of full sort
          _repositionChat(merged);
        }
      }
    }

    return index != -1;
  }

  Future<void> addChat(Chat toAdd) async {
    // Check if chat already exists
    final existingIndex = chats.indexWhere((e) => e.guid == toAdd.guid);
    if (existingIndex != -1) {
      // Update existing chat instead
      updateChat(toAdd, shouldSort: true, override: true);
      return;
    }
    
    // Find correct insertion position and insert
    final insertIndex = _findInsertionIndex(toAdd);
    chats.insert(insertIndex, toAdd);
    
    if (!headless) {
      cm.createChatController(toAdd);
    }
  }

  void removeChat(Chat toRemove) {
    final index = chats.indexWhere((e) => toRemove.guid == e.guid);
    if (index != -1) {
      chats.removeAt(index);
      chatUpdateTrigger.remove(toRemove.guid);
    }
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
    }
    Database.chats.putMany(_chats);
  }

  void updateChatPinIndex(int oldIndex, int newIndex) {
    final items = chats.bigPinHelper(true);
    final item = items[oldIndex];

    // Remove the item at the old index, and re-add it at the newIndex
    // We dynamically subtract 1 from the new index depending on if the newIndex is > the oldIndex
    items.removeAt(oldIndex);
    items.insert(newIndex + (oldIndex < newIndex ? -1 : 0), item);

    // Move the pinIndex for each of the chats, and save the pinIndex in the DB
    items.forEachIndexed((i, e) {
      e.pinIndex = i;
      e.save(updatePinIndex: true);
    });
    chats.sort(Chat.sort);
  }

  void removePinIndices() {
    // Create a snapshot to avoid concurrent modification during iteration
    final pinnedChats = chats.bigPinHelper(true).where((e) => e.pinIndex != null).toList();
    for (var element in pinnedChats) {
      element.pinIndex = null;
      element.save(updatePinIndex: true);
    }
    chats.sort(Chat.sort);
  }

  Future<void> updateShareTargets() async {
    if (Platform.isAndroid) {
      StartupTasks.waitForUI().then((_) async {
        // Create a snapshot to avoid concurrent modification during iteration
        final chatSnapshot = chats.where((e) => !isNullOrEmpty(e.title)).take(4).toList();
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

  void reset() {
    currentCount = 0;
    hasChats.value = false;
    chats.clear();
    chatUpdateTrigger.clear();
    loadedAllChats = Completer();
    loadedChatBatch.value = false;
    webCachedHandles.clear();

    countSub?.cancel();
    initDbWatchers();
  }
}
