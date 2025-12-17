import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class ChatActions {
  static Future<void> clearNotificationForChat(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as int;
    
    if (!LifecycleSvc.isBubble) {
      await MethodChannelSvc.invokeMethod(
        "delete-notification",
        {
          "notification_id": chatId,
          "tag": "new_message"
        }
      );
    }
  }

  static Future<void> markChatReadUnread(Map<String, dynamic> data) async {
    final chatGuid = data['chatGuid'] as String;
    final markAsRead = data['markAsRead'] as bool;
    final shouldMarkOnServer = data['shouldMarkOnServer'] as bool;
    
    if (shouldMarkOnServer && SettingsSvc.settings.enablePrivateAPI.value) {
      if (markAsRead) {
        await HttpSvc.markChatRead(chatGuid);
      } else {
        await HttpSvc.markChatUnread(chatGuid);
      }
    }
  }

  static Future<int?> saveChat(Map<String, dynamic> data) async {
    final guid = data['guid'] as String;
    final updateFlags = data['updateFlags'] as Map<String, bool>;
    final chatData = data['chatData'] as Map<String, dynamic>;

    return Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;
      final handleBox = Database.handles;

      /// Find an existing chat
      final query = chatBox.query(Chat_.guid.equals(guid)).build();
      final existing = query.findFirst();
      query.close();

      // Reconstruct the chat object
      final chat = Chat.fromMap(chatData);
      chat.id = existing?.id ?? chat.id;

      if (!updateFlags['updateMuteType']!) {
        chat.muteType = existing?.muteType ?? chat.muteType;
      }
      if (!updateFlags['updateMuteArgs']!) {
        chat.muteArgs = existing?.muteArgs ?? chat.muteArgs;
      }
      if (!updateFlags['updateIsPinned']!) {
        chat.isPinned = existing?.isPinned ?? chat.isPinned;
      }
      if (!updateFlags['updatePinIndex']!) {
        chat.pinIndex = existing?.pinIndex ?? chat.pinIndex;
      }
      if (!updateFlags['updateIsArchived']!) {
        chat.isArchived = existing?.isArchived ?? chat.isArchived;
      }
      if (!updateFlags['updateHasUnreadMessage']!) {
        chat.hasUnreadMessage = existing?.hasUnreadMessage ?? chat.hasUnreadMessage;
      }
      if (!updateFlags['updateAutoSendReadReceipts']!) {
        chat.autoSendReadReceipts = existing?.autoSendReadReceipts;
      }
      if (!updateFlags['updateAutoSendTypingIndicators']!) {
        chat.autoSendTypingIndicators = existing?.autoSendTypingIndicators;
      }
      if (!updateFlags['updateCustomAvatarPath']!) {
        chat.customAvatarPath = existing?.customAvatarPath ?? chat.customAvatarPath;
      }
      if (!updateFlags['updateTextFieldText']!) {
        chat.textFieldText = existing?.textFieldText ?? chat.textFieldText;
      }
      if (!updateFlags['updateTextFieldAttachments']!) {
        chat.textFieldAttachments = existing?.textFieldAttachments ?? chat.textFieldAttachments;
      }
      if (!updateFlags['updateDisplayName']!) {
        chat.displayName = existing?.displayName ?? chat.displayName;
      }
      if (!updateFlags['updateDateDeleted']!) {
        chat.dateDeleted = existing?.dateDeleted;
      }
      if (!updateFlags['updateLockChatName']!) {
        chat.lockChatName = existing?.lockChatName ?? false;
      }
      if (!updateFlags['updateLockChatIcon']!) {
        chat.lockChatIcon = existing?.lockChatIcon ?? false;
      }
      if (!updateFlags['updateLastReadMessageGuid']!) {
        chat.lastReadMessageGuid = existing?.lastReadMessageGuid ?? chat.lastReadMessageGuid;
      }

      /// Save the chat and add the participants
      for (int i = 0; i < chat.participants.length; i++) {
        // Save each participant handle
        final participantQuery = handleBox.query(Handle_.address.equals(chat.participants[i].address)).build();
        final existingHandle = participantQuery.findFirst();
        participantQuery.close();

        if (existingHandle != null) {
          chat.participants[i].id = existingHandle.id;
        }
        chat.participants[i].id = handleBox.put(chat.participants[i]);
      }

      try {
        chat.id = chatBox.put(chat);
        // make sure to add participant relation if its a new chat
        if (existing == null && chat.participants.isNotEmpty) {
          final toSave = chatBox.get(chat.id!);
          toSave!.handles.clear();
          toSave.handles.addAll(chat.participants);
          toSave.handles.applyToDb();
        }
      } on UniqueViolationException catch (_) {}

      return chat.id;
    });
  }

  static Future<void> deleteChat(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as int;
    final messageIds = (data['messageIds'] as List).cast<int>();

    Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;
      final messageBox = Database.messages;

      /// Remove all references of chat and its messages
      chatBox.remove(chatId);
      messageBox.removeMany(messageIds);
    });
  }

  static Future<void> softDeleteChat(Map<String, dynamic> data) async {
    final chatData = data['chatData'] as Map<String, dynamic>;
    final inputChat = Chat.fromMap(chatData);

    Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;

      // Find the chat in the database
      final query = chatBox.query(Chat_.guid.equals(inputChat.guid)).build();
      query.limit = 1;
      final dbChat = query.findFirst();
      query.close();

      if (dbChat != null) {
        dbChat.dateDeleted = DateTime.now().toUtc();
        dbChat.hasUnreadMessage = false;
        chatBox.put(dbChat);
      }
    });
  }

  static Future<void> unDeleteChat(Map<String, dynamic> data) async {
    final chatData = data['chatData'] as Map<String, dynamic>;
    final inputChat = Chat.fromMap(chatData);

    Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;

      // Find the chat in the database
      final query = chatBox.query(Chat_.guid.equals(inputChat.guid)).build();
      query.limit = 1;
      final dbChat = query.findFirst();
      query.close();

      if (dbChat != null) {
        dbChat.dateDeleted = null;
        chatBox.put(dbChat);
      }
    });
  }

  static Future<Map<String, dynamic>> addMessageToChat(Map<String, dynamic> data) async {
    final messageData = data['messageData'] as Map<String, dynamic>;
    final chatData = data['chatData'] as Map<String, dynamic>;
    final latestMessageData = data['latestMessageData'] as Map<String, dynamic>;
    final checkForMessageText = data['checkForMessageText'] as bool;

    return Database.runInTransaction(TxMode.write, () {
      final messageBox = Database.messages;
      final attachmentBox = Database.attachments;
      final handleBox = Database.handles;
      final chatBox = Database.chats;

      // Deserialize inputs
      final inputMessage = Message.fromMap(messageData);
      final inputChat = Chat.fromMap(chatData);
      final inputLatest = Message.fromMap(latestMessageData);

      // Find existing message
      final msgQuery = messageBox.query(Message_.guid.equals(inputMessage.guid ?? '')).build();
      msgQuery.limit = 1;
      Message? existing = msgQuery.findFirst();
      msgQuery.close();

      if (existing != null) {
        inputMessage.id = existing.id;
        inputMessage.text ??= existing.text;
      }

      // Save the handle if needed
      if (inputMessage.handle == null && inputMessage.handleId != null) {
        final handleQuery = handleBox.query(Handle_.originalROWID.equals(inputMessage.handleId!)).build();
        handleQuery.limit = 1;
        inputMessage.handle = handleQuery.findFirst();
        handleQuery.close();
      }

      // Handle associated messages (reactions)
      if (inputMessage.associatedMessageType != null && inputMessage.associatedMessageGuid != null) {
        final assocQuery = messageBox.query(Message_.guid.equals(inputMessage.associatedMessageGuid!)).build();
        assocQuery.limit = 1;
        final associatedMessage = assocQuery.findFirst();
        assocQuery.close();

        if (associatedMessage != null) {
          associatedMessage.hasReactions = true;
          messageBox.put(associatedMessage);
        }
      } else if (!inputMessage.hasReactions) {
        final reactionQuery =
            messageBox.query(Message_.associatedMessageGuid.equals(inputMessage.guid ?? '')).build();
        reactionQuery.limit = 1;
        final reaction = reactionQuery.findFirst();
        reactionQuery.close();

        if (reaction != null) {
          inputMessage.hasReactions = true;
        }
      }

      // Link chat to message
      final chatQuery = chatBox.query(Chat_.guid.equals(inputChat.guid)).build();
      chatQuery.limit = 1;
      final dbChat = chatQuery.findFirst();
      chatQuery.close();

      if (dbChat != null) {
        inputMessage.chat.target = dbChat;
      }

      // Save the message
      int? messageId;
      try {
        messageId = messageBox.put(inputMessage);
        inputMessage.id = messageId;
      } on UniqueViolationException catch (_) {
        // If unique violation, try to find the message again
        final retryQuery = messageBox.query(Message_.guid.equals(inputMessage.guid ?? '')).build();
        retryQuery.limit = 1;
        final retryResult = retryQuery.findFirst();
        retryQuery.close();
        inputMessage.id = retryResult?.id;
        messageId = retryResult?.id;
      }

      // Save attachments
      print('[addMessageToChat] Saving ${inputMessage.attachments.length} attachments for message ${inputMessage.guid} (ID: $messageId)');
      for (Attachment? attachment in inputMessage.attachments) {
        if (attachment == null) continue;

        print('[addMessageToChat] Processing attachment ${attachment.guid}');
        
        // Find existing attachment
        final attachQuery = attachmentBox.query(Attachment_.guid.equals(attachment.guid ?? '')).build();
        attachQuery.limit = 1;
        final existingAttach = attachQuery.findFirst();
        attachQuery.close();

        if (existingAttach != null) {
          attachment.id = existingAttach.id;
          print('[addMessageToChat] Found existing attachment with ID ${existingAttach.id}');
        } else {
          print('[addMessageToChat] New attachment, will create');
        }

        // Link message to attachment
        if (messageId != null) {
          attachment.message.target = inputMessage;
          print('[addMessageToChat] Linked attachment ${attachment.guid} to message ${inputMessage.guid} (ID: $messageId)');
        } else {
          print('[addMessageToChat] WARNING: No messageId to link attachment to!');
        }

        try {
          final attachmentId = attachmentBox.put(attachment);
          print('[addMessageToChat] Saved attachment ${attachment.guid} with ID $attachmentId, message link: ${attachment.message.target?.id}');
        } on UniqueViolationException catch (_) {
          print('[addMessageToChat] UniqueViolationException for attachment ${attachment.guid}');
        }
      }
      
      // Verify attachments were saved
      if (messageId != null && inputMessage.attachments.isNotEmpty) {
        final verifyQuery = (attachmentBox.query(Attachment_.id.notNull())
              ..link(Attachment_.message, Message_.id.equals(messageId)))
            .build();
        final savedAttachments = verifyQuery.find();
        verifyQuery.close();
        print('[addMessageToChat] VERIFICATION: Found ${savedAttachments.length} attachments linked to message $messageId in DB');
      }

      // Calculate if message is newer
      bool isNewerInIsolate = false;
      if ((messageId != null || kIsWeb) && checkForMessageText) {
        isNewerInIsolate = inputMessage.dateCreated!.isAfter(inputLatest.dateCreated!) ||
            (inputMessage.guid != inputLatest.guid && inputMessage.dateCreated == inputLatest.dateCreated);
      }

      return <String, dynamic>{
        'message': Map<String, dynamic>.from(inputMessage.toMap()),
        'messageId': messageId,
        'isNewer': isNewerInIsolate,
      };
    });
  }

  static Future<Map<String, dynamic>> loadSupplementalData(Map<String, dynamic> data) async {
    final messageGuids = (data['messageGuids'] as List).cast<String>();

    return Database.runInTransaction(TxMode.read, () {
      final messageBox = Database.messages;
      final attachmentBox = Database.attachments;

      // Query reactions
      final reactionsQuery = (messageBox.query(Message_.associatedMessageGuid.oneOf(messageGuids))
            ..order(Message_.originalROWID))
          .build();
      final reactions = reactionsQuery.find();
      reactionsQuery.close();

      // Query sticker attachments for reactions
      final stickerMessageIds =
          reactions.where((m) => m.associatedMessageType == "sticker").map((m) => m.id!).toList();

      final stickerAttachments = <Attachment>[];
      if (stickerMessageIds.isNotEmpty) {
        final stickerQuery = (attachmentBox.query(Attachment_.mimeType.notNull())
              ..link(Attachment_.message, Message_.id.oneOf(stickerMessageIds)))
            .build();
        stickerAttachments.addAll(stickerQuery.find());
        stickerQuery.close();
      }

      // Build sticker attachment map
      final stickerAttachmentMap = <int, List<Attachment>>{};
      for (final attachment in stickerAttachments) {
        final messageId = attachment.message.target?.id;
        if (messageId != null) {
          stickerAttachmentMap.putIfAbsent(messageId, () => []).add(attachment);
        }
      }

      // Assign sticker attachments to reaction messages
      for (final reaction in reactions) {
        if (reaction.associatedMessageType == "sticker") {
          reaction.attachments = stickerAttachmentMap[reaction.id] ?? [];
        }
      }

      return <String, dynamic>{
        'reactions': reactions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(),
      };
    });
  }

  static Future<List<Map<String, dynamic>>> syncLatestMessages(Map<String, dynamic> data) async {
    final chatGuids = (data['chatGuids'] as List).cast<String>();
    final toggleUnread = data['toggleUnread'] as bool;

    return Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;
      final messageBox = Database.messages;

      // Get the latest versions of the chats
      final chatQuery = chatBox.query(Chat_.guid.oneOf(chatGuids)).build();
      List<Chat> existingChats = chatQuery.find();
      chatQuery.close();

      if (existingChats.isEmpty) return <Map<String, dynamic>>[];

      // Pull the latest message for all of the chats
      List<int> chatIds = existingChats.map((e) => e.id!).toList();
      List<Chat> updatedChats = [];

      for (int chatId in chatIds) {
        // Fetch latest message for the chat
        final latestMsgQuery = (messageBox.query(Message_.dateCreated.notNull())
              ..link(Message_.chat, Chat_.id.equals(chatId))
              ..order(Message_.dateCreated, flags: Order.descending))
            .build();
        latestMsgQuery.limit = 1;
        final latestMessages = latestMsgQuery.find();
        latestMsgQuery.close();

        Message? latestMessage = latestMessages.firstOrNull;
        if (latestMessage?.handle == null && latestMessage?.handleId != null && latestMessage?.handleId != 0) {
          final handleQuery = Database.handles.query(Handle_.originalROWID.equals(latestMessage!.handleId!)).build();
          handleQuery.limit = 1;
          latestMessage.handle = handleQuery.findFirst();
          handleQuery.close();
        }

        Chat current = existingChats.firstWhere((element) => element.id == chatId);

        // Try and update the last message info
        bool didUpdate = _tryUpdateLastMessage(current, latestMessage, toggleUnread);
        if (didUpdate) {
          updatedChats.add(current);
        }
      }

      // If we have updates to make, apply them
      if (updatedChats.isNotEmpty) {
        chatBox.putMany(updatedChats, mode: PutMode.update);
      }

      return existingChats.map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }

  static bool _tryUpdateLastMessage(Chat chat, Message? lastMessage, bool toggleUnread) {
    // If we don't even have a last message, return false
    if (lastMessage == null || lastMessage.dateCreated == null) return false;

    bool didUpdate = false;
    bool checkMessageText = false;

    int currentMs = chat.latestMessage.dateCreated!.millisecondsSinceEpoch;
    int lastMs = lastMessage.dateCreated!.millisecondsSinceEpoch;
    if (currentMs <= lastMs) {
      didUpdate = true;

      if (currentMs == lastMs) {
        checkMessageText = true;
      }
    }

    // If we plan to update the message, but the dates are the same,
    if (didUpdate && checkMessageText) {
      if (MessageHelper.getNotificationText(chat.latestMessage) == MessageHelper.getNotificationText(lastMessage)) {
        didUpdate = false;
      }
    }

    // If we still want to update the info, do so
    if (didUpdate) {
      chat.latestMessage = lastMessage;

      // Mark the chat as unread if we updated the last message & it's not from us
      if (toggleUnread && !(lastMessage.isFromMe ?? false)) {
        chat.toggleHasUnread(true);
      }
    }

    return didUpdate;
  }

  static Future<List<Map<String, dynamic>>> bulkSyncChats(Map<String, dynamic> data) async {
    final chatsData = (data['chatsData'] as List).cast<Map<String, dynamic>>();

    return Database.runInTransaction(TxMode.write, () {
      final chatBox = Database.chats;
      final handleBox = Database.handles;

      // Deserialize input chats
      final inputChats = chatsData.map((e) => Chat.fromMap(e)).toList();
      final inputChatGuids = inputChats.map((element) => element.guid).toList();

      // 0. Create map for the chats and handles to save
      Map<String, Handle> handlesToSave = {};
      Map<String, List<String>> chatHandles = {};
      Map<String, Chat> chatsToSave = {};
      for (final chat in inputChats) {
        chatsToSave[chat.guid] = chat;
        for (final p in chat.participants) {
          if (!handlesToSave.containsKey(p.uniqueAddressAndService)) {
            handlesToSave[p.uniqueAddressAndService] = p;
          }

          if (!chatHandles.containsKey(chat.guid)) {
            chatHandles[chat.guid] = [];
          }

          if (!chatHandles[chat.guid]!.contains(p.uniqueAddressAndService)) {
            chatHandles[chat.guid]?.add(p.uniqueAddressAndService);
          }
        }
      }

      // 1. Check for existing handles and save new ones
      List<Handle> inputHandles = handlesToSave.values.toList();
      List<String> inputHandleAddressesAndServices =
          inputHandles.map((element) => element.uniqueAddressAndService).toList();
      final handleQuery =
          handleBox.query(Handle_.uniqueAddressAndService.oneOf(inputHandleAddressesAndServices)).build();
      List<String> existingHandleAddressesAndServices =
          handleQuery.find().map((e) => e.uniqueAddressAndService).toList();
      handleQuery.close();
      inputHandles = inputHandles
          .where((element) => !existingHandleAddressesAndServices.contains(element.uniqueAddressAndService))
          .toList();
      handleBox.putMany(inputHandles);

      // 2. Fetch all inserted/existing handles based on input
      final handleQuery2 =
          handleBox.query(Handle_.uniqueAddressAndService.oneOf(inputHandleAddressesAndServices)).build();
      List<Handle> handles = handleQuery2.find().toList();
      handleQuery2.close();

      // 3. Create map of inserted/existing handles
      Map<String, Handle> handleMap = {};
      for (final h in handles) {
        handleMap[h.uniqueAddressAndService] = h;
      }

      // 4. Check for existing chats and save new ones
      final chatQuery = chatBox.query(Chat_.guid.oneOf(inputChatGuids)).build();
      List<String> existingChatGuids = chatQuery.find().map((e) => e.guid).toList();
      chatQuery.close();
      final newChats = inputChats.where((element) => !existingChatGuids.contains(element.guid)).toList();
      chatBox.putMany(newChats);

      // 5. Fetch all inserted/existing chats based on input
      final chatQuery2 = chatBox.query(Chat_.guid.oneOf(inputChatGuids)).build();
      List<Chat> resultChats = chatQuery2.find().toList();
      chatQuery2.close();

      // 6. Create map of inserted/existing chats
      Map<String, Chat> chatMap = {};
      for (final c in resultChats) {
        chatMap[c.guid] = c;
      }

      // 7. Loop over chat -> participants map and relate all the participants to the chats
      for (final item in chatHandles.entries) {
        final chat = chatMap[item.key];
        if (chat == null) continue;
        final participants = item.value.map((e) => handleMap[e]).nonNulls.toList();
        if (participants.isNotEmpty) {
          chat.handles.clear();
          chat.handles.addAll(participants);
          chat.handles.applyToDb();
          // Populate participants by calling getParticipants() to ensure proper serialization
          chat.getParticipants();
        }
      }

      // 8. Save & return updated chats
      chatBox.putMany(resultChats);
      return resultChats.map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }

  static Future<List<Map<String, dynamic>>> getMessagesAsync(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as int;
    final participantsData = (data['participantsData'] as List).cast<Map<String, dynamic>>();
    final offset = data['offset'] as int? ?? 0;
    final limit = data['limit'] as int? ?? 25;
    final includeDeleted = data['includeDeleted'] as bool? ?? false;
    final searchAround = data['searchAround'] as int?;

    return Database.runInTransaction(TxMode.read, () {
      final participants = participantsData.map((e) => Handle.fromMap(e)).toList();
      final messageBox = Database.messages;
      final messages = <Message>[];

      if (searchAround == null) {
        final query = (messageBox.query(includeDeleted
          ? Message_.dateCreated.notNull().and(Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()))
          : Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull()))
              ..link(Message_.chat, Chat_.id.equals(chatId))
              ..order(Message_.dateCreated, flags: Order.descending))
            .build();
        query
          ..limit = limit
          ..offset = offset;
        messages.addAll(query.find());
        query.close();
      } else {
        final beforeQuery = (messageBox.query(Message_.dateCreated.lessThan(searchAround).and(includeDeleted
                ? Message_.dateCreated.notNull().and(Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()))
                : Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull())))
              ..link(Message_.chat, Chat_.id.equals(chatId))
              ..order(Message_.dateCreated, flags: Order.descending))
            .build();
        beforeQuery.limit = limit;
        messages.addAll(beforeQuery.find());
        beforeQuery.close();

        final afterQuery = (messageBox.query(Message_.dateCreated.greaterThan(searchAround).and(includeDeleted
                ? Message_.dateCreated.notNull().and(Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()))
                : Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull())))
              ..link(Message_.chat, Chat_.id.equals(chatId))
              ..order(Message_.dateCreated))
            .build();
        afterQuery.limit = limit;
        messages.addAll(afterQuery.find());
        afterQuery.close();
      }

      // Handle matching
      for (int i = 0; i < messages.length; i++) {
        Message message = messages[i];
        if (participants.isNotEmpty && !message.isFromMe! && message.handleId != null && message.handleId != 0) {
          Handle? handle =
              participants.firstWhereOrNull((e) => e.originalROWID == message.handleId) ?? message.getHandle();
          if (handle == null && message.originalROWID != null) {
            messages.remove(message);
            i--;
          } else {
            message.handle = handle;
          }
        }
      }

      // Access dbAttachments to trigger lazy-load for each message
      for (final message in messages) {
        // Simply accessing dbAttachments will trigger the load from DB
        final _ = message.dbAttachments.length; // Forces the load
        
        // Now populate the attachments field from dbAttachments
        if (message.hasAttachments) {
          message.attachments = List<Attachment>.from(message.dbAttachments);
        }
      }

      // // Query attachments for messages
      // // Note: We query attachments separately because ToMany relationships are lazy-loaded
      // // and we need to populate the 'attachments' field (not dbAttachments) for serialization
      // final attachmentBox = Database.attachments;
      // final messageIds = messages.map((e) => e.id!).toList();
      
      // if (messageIds.isNotEmpty) {
      //   final attachmentQuery = (attachmentBox.query(Attachment_.id.notNull())
      //         ..link(Attachment_.message, Message_.id.oneOf(messageIds)))
      //       .build();
      //   final attachments = attachmentQuery.find();
      //   attachmentQuery.close();

      //   // Build attachment map by message ID
      //   final attachmentMap = <int, List<Attachment>>{};
      //   for (final attachment in attachments) {
      //     final messageId = attachment.message.target?.id;
      //     if (messageId != null) {
      //       attachmentMap.putIfAbsent(messageId, () => []).add(attachment);
      //     }
      //   }

      //   // IMPORTANT: Populate the 'attachments' field for serialization
      //   // Do NOT modify 'dbAttachments' here - it represents the persisted DB relationship
      //   // and should only be modified when actually saving/updating messages in the DB
      //   for (final message in messages) {
      //     final messageAttachments = attachmentMap[message.id];
      //     if (messageAttachments != null && messageAttachments.isNotEmpty) {
      //       message.attachments = messageAttachments;
      //     }
      //   }
      // }

      return messages.map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }

  static Future<List<Map<String, dynamic>>> bulkSyncMessages(Map<String, dynamic> data) async {
    final chatData = data['chatData'] as Map<String, dynamic>;
    final messagesData = (data['messagesData'] as List).cast<Map<String, dynamic>>();

    return Database.runInTransaction(TxMode.write, () {
      final inputChat = Chat.fromMap(chatData);
      final inputMessages = messagesData.map((e) => Message.fromMap(e)).toList();

      final chatQuery = Database.chats.query(Chat_.guid.equals(inputChat.guid)).build();
      final dbChat = chatQuery.findFirst();
      chatQuery.close();
      if (dbChat == null) return <Map<String, dynamic>>[];

      // Gather handles from chat and cache them
      Map<String, Handle> handlesCache = {};
      for (var participant in dbChat.handles) {
        String addr = participant.uniqueAddressAndService;
        if (handlesCache.containsKey(addr)) continue;
        handlesCache[addr] = participant;
      }

      // For each message, match the handles & replace the old reference
      for (Message message in inputMessages) {
        message.handle ??= handlesCache.values.firstWhereOrNull((e) => e.originalROWID == message.handleId);
      }

      // Extract & cache the attachments
      Map<String, Attachment> attachmentCache = {};
      for (var msg in inputMessages) {
        if (msg.attachments.isEmpty) continue;
        for (Attachment? attachment in msg.attachments) {
          if (attachment == null) continue;
          attachmentCache[attachment.guid!] = attachment;
        }
      }

      // Sync the attachments & insert IDs into cache
      final syncedAttachments = _syncAttachmentsInTransaction(attachmentCache.values.toList());
      for (var attachment in syncedAttachments) {
        if (!attachmentCache.containsKey(attachment.guid)) continue;
        attachmentCache[attachment.guid!] = attachment;
      }

      // Sync the messages & insert synced attachments
      final syncedMessages = _syncMessagesInTransaction(dbChat, inputMessages);
      for (var message in syncedMessages) {
        // Update related attachments with synced versions
        for (var attachment in message.attachments) {
          if (attachment == null) continue;
          Attachment? cached = attachmentCache[attachment.guid];
          if (cached == null) continue;
          attachment = cached;
        }

        // Update the relational attachments
        message.dbAttachments.addAll(message.attachments.where((element) => element != null).map((e) => e!).toList());
      }

      // Invoke a final put call to sync the relational data
      for (Message m in syncedMessages) {
        try {
          // CRITICAL: Preserve dbAttachments ToMany relationship before put
          final attachmentsToPreserve = List<Attachment>.from(m.dbAttachments);
          
          Database.messages.put(m);
          
          // Restore and apply attachments after put
          if (attachmentsToPreserve.isNotEmpty) {
            m.dbAttachments.clear();
            m.dbAttachments.addAll(attachmentsToPreserve);
            m.dbAttachments.applyToDb();
          }
        } catch (_) {}
      }

      return syncedMessages.map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }

  static List<Attachment> _syncAttachmentsInTransaction(List<Attachment> attachments) {
    final attachmentBox = Database.attachments;
    List<String> inputAttachmentGuids = attachments.map((element) => element.guid!).toList();

    final query = attachmentBox.query(Attachment_.guid.oneOf(inputAttachmentGuids)).build();
    List<Attachment> existingAttachments = query.find();
    query.close();
    List<String> existingAttachmentGuids = existingAttachments.map((e) => e.guid!).toList();

    List<Attachment> newAttachments =
        attachments.where((element) => !existingAttachmentGuids.contains(element.guid)).toList();
    attachmentBox.putMany(newAttachments);

    if (existingAttachments.isNotEmpty) {
      int mods = 0;
      for (var i = 0; i < existingAttachments.length; i++) {
        Attachment? newAttachment = attachments.firstWhereOrNull((e) => e.guid == existingAttachments[i].guid);
        if (newAttachment == null) continue;
        existingAttachments[i] = Attachment.merge(newAttachment, existingAttachments[i]);
        mods += 1;
      }

      if (mods > 0) {
        attachmentBox.putMany(existingAttachments);
      }
    }

    final query2 = attachmentBox.query(Attachment_.guid.oneOf(inputAttachmentGuids)).build();
    List<Attachment> syncedAttachments = query2.find().toList();
    query2.close();

    for (var i = 0; i < attachments.length; i++) {
      Attachment? synced = syncedAttachments.firstWhereOrNull((e) => e.guid == attachments[i].guid);
      if (synced == null) continue;
      attachments[i] = Attachment.merge(attachments[i], synced);
    }

    return attachments;
  }

  static List<Message> _syncMessagesInTransaction(Chat c, List<Message> messages) {
    final messageBox = Database.messages;
    List<String> inputMessageGuids = messages.map((element) => element.guid!).toList();

    final query = messageBox.query(Message_.guid.oneOf(inputMessageGuids)).build();
    List<Message> existingMessages = query.find();
    query.close();
    List<String> existingMessageGuids = existingMessages.map((e) => e.guid!).toList();

    List<Message> newMessages = messages.where((element) => !existingMessageGuids.contains(element.guid)).toList();
    messageBox.putMany(newMessages);

    if (existingMessages.isNotEmpty) {
      int mods = 0;
      for (var i = 0; i < existingMessages.length; i++) {
        Message? newMessage = messages.firstWhereOrNull((e) => e.guid == existingMessages[i].guid);
        if (newMessage == null) continue;
        existingMessages[i] = Message.merge(newMessage, existingMessages[i]);
        mods += 1;
      }

      if (mods > 0) {
        // CRITICAL: Preserve dbAttachments ToMany relationships before putMany
        final attachmentPreservation = <String, List<Attachment>>{};
        for (final msg in existingMessages) {
          if (msg.dbAttachments.isNotEmpty) {
            attachmentPreservation[msg.guid!] = List<Attachment>.from(msg.dbAttachments);
          }
        }
        
        messageBox.putMany(existingMessages, mode: PutMode.update);
        
        // Restore attachments after putMany
        for (final msg in existingMessages) {
          if (attachmentPreservation.containsKey(msg.guid)) {
            msg.dbAttachments.clear();
            msg.dbAttachments.addAll(attachmentPreservation[msg.guid]!);
            msg.dbAttachments.applyToDb();
          }
        }
      }
    }

    final query2 = messageBox.query(Message_.guid.oneOf(inputMessageGuids)).build();
    List<Message> syncedMessages = query2.find().toList();
    query2.close();

    for (var i = 0; i < messages.length; i++) {
      Message? synced = syncedMessages.firstWhereOrNull((e) => e.guid == messages[i].guid);
      if (synced == null) continue;
      messages[i] = Message.merge(messages[i], synced);
      messages[i].chat.target = c;
    }

    // CRITICAL: Preserve dbAttachments ToMany relationships before putMany
    final attachmentPreservation = <String, List<Attachment>>{};
    for (final msg in messages) {
      if (msg.dbAttachments.isNotEmpty) {
        attachmentPreservation[msg.guid!] = List<Attachment>.from(msg.dbAttachments);
      }
    }

    messageBox.putMany(messages, mode: PutMode.update);

    // Restore attachments after putMany
    for (final msg in messages) {
      if (attachmentPreservation.containsKey(msg.guid)) {
        msg.dbAttachments.clear();
        msg.dbAttachments.addAll(attachmentPreservation[msg.guid]!);
        msg.dbAttachments.applyToDb();
      }
    }
    
    return messages;
  }

  static Future<List<Map<String, dynamic>>> getParticipantsAsync(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as int;

    return Database.runInTransaction(TxMode.read, () {
      final query = Database.chats.query(Chat_.id.equals(chatId)).build();
      final chat = query.findFirst();
      query.close();

      if (chat == null) return <Map<String, dynamic>>[];

      return List<Handle>.from(chat.handles).map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }

  static Future<void> clearTranscriptAsync(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as int;

    Database.runInTransaction(TxMode.write, () {
      final query = Database.chats.query(Chat_.id.equals(chatId)).build();
      final chat = query.findFirst();
      query.close();

      if (chat == null) return;

      final toDelete = List<Message>.from(chat.messages);
      for (Message element in toDelete) {
        element.dateDeleted = DateTime.now().toUtc();
      }
      Database.messages.putMany(toDelete);
    });
  }

  static Future<List<Map<String, dynamic>>> getChatsAsync(Map<String, dynamic> data) async {
    final limit = data['limit'] as int? ?? 15;
    final offset = data['offset'] as int? ?? 0;
    final ids = (data['ids'] as List?)?.cast<int>() ?? const <int>[];

    return Database.runInTransaction(TxMode.read, () {
      final chatBox = Database.chats;
      late final QueryBuilder<Chat> queryBuilder;

      // If IDs are provided, query by IDs. Otherwise, query non-deleted chats
      if (ids.isNotEmpty) {
        queryBuilder = chatBox.query(Chat_.id.oneOf(ids));
      } else {
        queryBuilder = chatBox.query(Chat_.dateDeleted.isNull());
      }

      // Build the query with limit and offset
      // Note: No ordering at DB level - ChatService handles proper ordering
      // including pinIndex which DB cannot efficiently order by
      final query = queryBuilder.build()
        ..limit = limit
        ..offset = offset;

      // Execute the query
      final chats = query.find();
      query.close();

      // Load participants for each chat and serialize
      for (Chat c in chats) {
        // Call getParticipants to load and deduplicate handles
        c.getParticipants();
      }

      // Return serialized chats with proper type casting
      return chats.map((e) => Map<String, dynamic>.from(e.toMap())).toList();
    });
  }
}
