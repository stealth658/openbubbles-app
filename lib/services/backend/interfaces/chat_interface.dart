import 'package:bluebubbles/env.dart';
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

    if (isIsolate()) {
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

    if (isIsolate()) {
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

    if (isIsolate()) {
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

    if (isIsolate()) {
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

    if (isIsolate()) {
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

    if (isIsolate()) {
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

    if (isIsolate()) {
      return await ChatActions.addMessageToChat(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.addMessageToChat, input: data);
    }
  }

  static Future<Map<String, dynamic>> loadSupplementalData({
    required List<String> messageGuids,
    required List<int> messageIds,
  }) async {
    final data = {
      'messageGuids': messageGuids,
      'messageIds': messageIds,
    };

    if (isIsolate()) {
      return await ChatActions.loadSupplementalData(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.loadSupplementalData, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> syncLatestMessages({
    required List<String> chatGuids,
    required bool toggleUnread,
  }) async {
    final data = {
      'chatGuids': chatGuids,
      'toggleUnread': toggleUnread,
    };

    if (isIsolate()) {
      return await ChatActions.syncLatestMessages(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.syncLatestMessages, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> bulkSyncChats({
    required List<Map<String, dynamic>> chatsData,
  }) async {
    final data = {
      'chatsData': chatsData,
    };

    if (isIsolate()) {
      return await ChatActions.bulkSyncChats(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSyncChats, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> getMessagesAsync({
    required int chatId,
    required String chatGuid,
    required List<Map<String, dynamic>> participantsData,
    int offset = 0,
    int limit = 25,
    bool includeDeleted = false,
    int? searchAround,
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

    if (isIsolate()) {
      return await ChatActions.getMessagesAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getMessagesAsync, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> bulkSyncMessages({
    required Map<String, dynamic> chatData,
    required List<Map<String, dynamic>> messagesData,
  }) async {
    final data = {
      'chatData': chatData,
      'messagesData': messagesData,
    };

    if (isIsolate()) {
      return await ChatActions.bulkSyncMessages(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSyncMessages, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> getParticipantsAsync({
    required int chatId,
    required String chatGuid,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
    };

    if (isIsolate()) {
      return await ChatActions.getParticipantsAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getParticipantsAsync, input: data);
    }
  }

  static Future<void> clearTranscriptAsync({
    required int chatId,
    required String chatGuid,
  }) async {
    final data = {
      'chatId': chatId,
      'chatGuid': chatGuid,
    };

    if (isIsolate()) {
      return await ChatActions.clearTranscriptAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.clearTranscriptAsync, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> getChatsAsync({
    int limit = 15,
    int offset = 0,
    List<int> ids = const [],
  }) async {
    final data = {
      'limit': limit,
      'offset': offset,
      'ids': ids,
    };

    if (isIsolate()) {
      return await ChatActions.getChatsAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getChatsAsync, input: data);
    }
  }
}
