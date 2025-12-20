import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/hydration/chat_hydration.dart';
import 'package:bluebubbles/services/backend/hydration/message_hydration.dart';
import 'package:bluebubbles/services/backend/actions/chat_actions.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class ChatInterface {
  static Future<void> clearNotificationForChat({
    required int chatId,
    required String chatGuid,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
    };

    if (isIsolate) {
      return await ChatActions.clearNotificationForChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.clearNotificationForChat, input: data);
    }
  }

  static Future<void> markChatReadUnread({
    required String chatGuid,
    required bool markAsRead,
    required bool shouldMarkOnServer,
  }) async {
    final Map<String, dynamic> data = {
      'chatGuid': chatGuid,
      'markAsRead': markAsRead,
      'shouldMarkOnServer': shouldMarkOnServer,
    };

    if (isIsolate) {
      return await ChatActions.markChatReadUnread(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.markChatReadUnread, input: data);
    }
  }

  static Future<int?> saveChat({
    required String guid,
    required Map<String, dynamic> chatData,
    required Map<String, bool> updateFlags,
  }) async {
    final data = {
      'guid': guid,
      'chatData': chatData,
      'updateFlags': updateFlags,
    };

    if (isIsolate) {
      return await ChatActions.saveChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<int?>(IsolateRequestType.saveChat, input: data);
    }
  }

  static Future<void> deleteChat({
    required int chatId,
    required List<int> messageIds,
  }) async {
    final data = {
      'chatId': chatId,
      'messageIds': messageIds,
    };

    if (isIsolate) {
      return await ChatActions.deleteChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.deleteChat, input: data);
    }
  }

  static Future<void> softDeleteChat({
    required Map<String, dynamic> chatData,
  }) async {
    final data = {
      'chatData': chatData,
    };

    if (isIsolate) {
      return await ChatActions.softDeleteChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.softDeleteChat, input: data);
    }
  }

  static Future<void> unDeleteChat({
    required Map<String, dynamic> chatData,
  }) async {
    final data = {
      'chatData': chatData,
    };

    if (isIsolate) {
      return await ChatActions.unDeleteChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.unDeleteChat, input: data);
    }
  }

  static Future<Map<String, dynamic>> addMessageToChat({
    required Map<String, dynamic> messageData,
    required Map<String, dynamic> chatData,
    required Map<String, dynamic> latestMessageData,
    required bool checkForMessageText,
  }) async {
    final data = {
      'messageData': messageData,
      'chatData': chatData,
      'latestMessageData': latestMessageData,
      'checkForMessageText': checkForMessageText,
    };

    if (isIsolate) {
      return await ChatActions.addMessageToChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.addMessageToChat, input: data);
    }
  }

  static Future<Map<String, dynamic>> loadSupplementalData({
    required List<String> messageGuids,
  }) async {
    final data = {
      'messageGuids': messageGuids,
    };

    if (isIsolate) {
      return await ChatActions.loadSupplementalData(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.loadSupplementalData, input: data);
    }
  }

  static Future<List<Chat>> syncLatestMessages({
    required List<String> chatGuids,
    required bool toggleUnread,
    bool cacheContactNames = true,
  }) async {
    final data = {
      'chatGuids': chatGuids,
      'toggleUnread': toggleUnread,
    };

    late List<int> chatIds;
    if (isIsolate) {
      chatIds = await ChatActions.syncLatestMessages(data);
    } else {
      chatIds = await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.syncLatestMessages, input: data);
    }

    // Fetch chats by ID using getMany for efficiency
    final chats = Database.chats.getMany(chatIds).whereType<Chat>().toList();
    
    // Hydrate chats (cache contact names only, participants are lazy-loaded)
    await ChatHydration.hydrateAll(
      chats,
      cacheContactNames: cacheContactNames,
    );
    
    return chats;
  }

  static Future<List<Chat>> bulkSyncChats({
    required List<Map<String, dynamic>> chatsData,
    bool cacheContactNames = true,
  }) async {
    final data = {
      'chatsData': chatsData,
    };

    late List<int> chatIds;
    if (isIsolate) {
      chatIds = await ChatActions.bulkSyncChats(data);
    } else {
      chatIds = await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.bulkSyncChats, input: data);
    }

    // Fetch chats by ID using getMany for efficiency
    final chats = Database.chats.getMany(chatIds).whereType<Chat>().toList();
    
    // Hydrate chats (cache contact names only, participants are lazy-loaded)
    await ChatHydration.hydrateAll(
      chats,
      cacheContactNames: cacheContactNames,
    );
    
    return chats;
  }

  static Future<List<Message>> getMessagesAsync({
    required int chatId,
    required String chatGuid,
    required List<Map<String, dynamic>> participantsData,
    int offset = 0,
    int limit = 25,
    bool includeDeleted = false,
    int? searchAround,
    bool hydrateAttachments = true,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
      'participantsData': participantsData,
      'offset': offset,
      'limit': limit,
      'includeDeleted': includeDeleted,
      'searchAround': searchAround,
    };

    late List<Map<String, dynamic>> messagesData;
    if (isIsolate) {
      messagesData = await ChatActions.getMessagesAsync(data);
    } else {
      messagesData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getMessagesAsync, input: data);
    }

    // Deserialize messages from maps
    final messages = messagesData.map((e) => Message.fromMap(e)).toList();
    
    // Hydrate messages with their attachments from the database
    if (hydrateAttachments) {
      MessageHydration.hydrateAll(messages);
    }

    return messages;
  }

  static Future<List<Message>> bulkSyncMessages({
    required Map<String, dynamic> chatData,
    required List<Map<String, dynamic>> messagesData,
    bool hydrateAttachments = true,
  }) async {
    final data = {
      'chatData': chatData,
      'messagesData': messagesData,
    };

    late List<Map<String, dynamic>> resultMessagesData;
    if (isIsolate) {
      resultMessagesData = await ChatActions.bulkSyncMessages(data);
    } else {
      resultMessagesData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSyncMessages, input: data);
    }

    // Deserialize messages from maps
    final messages = resultMessagesData.map((e) => Message.fromMap(e)).toList();
    
    // Hydrate messages with their attachments from the database
    if (hydrateAttachments) {
      MessageHydration.hydrateAll(messages);
    }

    return messages;
  }

  static Future<List<Handle>> getParticipantsAsync({
    required int chatId,
    required String chatGuid,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
    };

    late List<Map<String, dynamic>> participantsData;
    if (isIsolate) {
      participantsData = await ChatActions.getParticipantsAsync(data);
    } else {
      participantsData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getParticipantsAsync, input: data);
    }

    // Deserialize handles from maps
    return participantsData.map((e) => Handle.fromMap(e)).toList();
  }

  static Future<void> clearTranscriptAsync({
    required int chatId,
    required String chatGuid,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
    };

    if (isIsolate) {
      return await ChatActions.clearTranscriptAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.clearTranscriptAsync, input: data);
    }
  }

  static Future<List<Chat>> getChatsAsync({
    int limit = 15,
    int offset = 0,
    List<int> ids = const [],
    bool cacheContactNames = true,
  }) async {
    final data = {
      'limit': limit,
      'offset': offset,
      'ids': ids,
    };

    late List<int> chatIds;
    if (isIsolate) {
      chatIds = await ChatActions.getChatsAsync(data);
    } else {
      chatIds = await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.getChatsAsync, input: data);
    }

    // Fetch chats by ID using getMany for efficiency
    final chats = Database.chats.getMany(chatIds).whereType<Chat>().toList();
    
    // Hydrate chats (cache contact names only, participants are lazy-loaded)
    await ChatHydration.hydrateAll(
      chats,
      cacheContactNames: cacheContactNames,
    );
    
    return chats;
  }
}
