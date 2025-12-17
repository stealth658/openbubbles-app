import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/message_actions.dart';
import 'package:bluebubbles/services/backend/hydration/message_hydration.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class MessageInterface {
  static Future<List<Message?>> getMessages() async {
    final isolate = GetIt.I<GlobalIsolate>();
    
    final stopwatch = Stopwatch()..start();
    final results = await isolate.send<List<Message?>>(
      IsolateRequestType.getMessages,
      input: null,
    );
    stopwatch.stop();
    
    Logger.info('Fetched ${results.length} messages from CUSTOM ISOLATE in ${stopwatch.elapsedMilliseconds}ms: ${results.map((m) => m?.guid).join(", ")}');

    final stopwatch2 = Stopwatch()..start();
    final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
    final messages = (await Database.messages.query(Message_.dateCreated.greaterThan(oneDayAgo.millisecondsSinceEpoch)).build().findAsync());
    stopwatch2.stop();
    print('Fetched ${messages.length} messages from BUILT IN ISOLATE in ${stopwatch2.elapsedMilliseconds}ms');

    final stopwatch3 = Stopwatch()..start();
    final messages2 = Database.messages.query(Message_.dateCreated.greaterThan(oneDayAgo.millisecondsSinceEpoch)).build().find();
    stopwatch3.stop();
    print('Fetched ${messages2.length} messages from NON ASYNC in ${stopwatch3.elapsedMilliseconds}ms');

    return results;
  }

  static Future<List<Message>> bulkSaveNewMessages({
    required Map<String, dynamic> data,
    bool hydrateAttachments = true,
  }) async {
    late List<Map<String, dynamic>> messagesData;
    if (isIsolate) {
      messagesData = await MessageActions.bulkSaveNewMessages(data);
    } else {
      messagesData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSaveNewMessages, input: data);
    }
    final messages = messagesData.map((e) => Message.fromMap(e)).toList();
    if (hydrateAttachments) {
      MessageHydration.hydrateAll(messages);
    }
    return messages;
  }

  static Future<Map<String, dynamic>> replaceMessage({
    required String? oldGuid,
    required Map<String, dynamic> newMessageData,
  }) async {
    final data = {
      'oldGuid': oldGuid,
      'newMessageData': newMessageData,
    };

    if (isIsolate) {
      return await MessageActions.replaceMessage(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.replaceMessage, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAttachmentsAsync({
    required int messageId,
    required String messageGuid,
  }) async {
    final data = {
      'messageId': messageId,
      'messageGuid': messageGuid,
    };

    if (isIsolate) {
      return await MessageActions.fetchAttachmentsAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.fetchAttachmentsAsync, input: data);
    }
  }

  static Future<Map<String, dynamic>?> getChatAsync({
    required int messageId,
    required String messageGuid,
  }) async {
    final data = {
      'messageId': messageId,
      'messageGuid': messageGuid,
    };

    if (isIsolate) {
      return await MessageActions.getChatAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.getChatAsync, input: data);
    }
  }

  static Future<void> deleteMessage({
    required String guid,
  }) async {
    final data = {
      'guid': guid,
    };

    if (isIsolate) {
      return await MessageActions.deleteMessage(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.deleteMessage, input: data);
    }
  }

  static Future<void> softDeleteMessage({
    required String guid,
  }) async {
    final data = {
      'guid': guid,
    };

    if (isIsolate) {
      return await MessageActions.softDeleteMessage(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.softDeleteMessage, input: data);
    }
  }

  static Future<Map<String, dynamic>> fetchAssociatedMessagesAsync({
    required String messageGuid,
    required int? messageId,
    String? threadOriginatorGuid,
  }) async {
    final data = {
      'messageGuid': messageGuid,
      'messageId': messageId,
      'threadOriginatorGuid': threadOriginatorGuid,
    };

    if (isIsolate) {
      return await MessageActions.fetchAssociatedMessagesAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.fetchAssociatedMessagesAsync, input: data);
    }
  }

  static Future<Message?> saveMessageAsync({
    required Map<String, dynamic> messageData,
    Map<String, dynamic>? chatData,
    required bool updateIsBookmarked,
    bool hydrateAttachments = true,
  }) async {
    final data = {
      'messageData': messageData,
      'chatData': chatData,
      'updateIsBookmarked': updateIsBookmarked,
    };

    late Map<String, dynamic> messageMap;
    if (isIsolate) {
      messageMap = await MessageActions.saveMessageAsync(data);
    } else {
      messageMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveMessageAsync, input: data);
    }
    
    final message = Message.fromMap(messageMap);
    if (hydrateAttachments) {
      MessageHydration.hydrate(message);
    }
    return message;
  }

  static Future<Message?> findOneAsync({
    String? guid,
    String? associatedMessageGuid,
    bool hydrateAttachments = true,
  }) async {
    final data = {
      'guid': guid,
      'associatedMessageGuid': associatedMessageGuid,
    };

    late Map<String, dynamic>? messageMap;
    if (isIsolate) {
      messageMap = await MessageActions.findOneAsync(data);
    } else {
      messageMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneAsync, input: data);
    }
    
    if (messageMap == null) return null;
    
    final message = Message.fromMap(messageMap);
    if (hydrateAttachments) {
      MessageHydration.hydrate(message);
    }
    return message;
  }

  static Future<List<Message>> findAsync({
    String? conditionJson,
    bool hydrateAttachments = true,
  }) async {
    final data = {
      'conditionJson': conditionJson,
    };

    late List<Map<String, dynamic>> messagesData;
    if (isIsolate) {
      messagesData = await MessageActions.findAsync(data);
    } else {
      messagesData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.findAsync, input: data);
    }
    
    final messages = messagesData.map((e) => Message.fromMap(e)).toList();
    if (hydrateAttachments) {
      MessageHydration.hydrateAll(messages);
    }
    return messages;
  }

  /// Bulk add messages - offloads heavy processing to the isolate
  static Future<List<Message>> bulkAddMessages({
    Map<String, dynamic>? chatData,
    required List<Map<String, dynamic>> messagesData,
    bool checkForLatestMessageText = true,
    bool hydrateAttachments = true,
  }) async {
    late List<Map<String, dynamic>> results;
    final data = {
      'chatData': chatData,
      'messagesData': messagesData,
      'checkForLatestMessageText': checkForLatestMessageText,
    };

    if (isIsolate) {
      results = await MessageActions.bulkAddMessages(data);
    } else {
      results = await GetIt.I<GlobalIsolate>()
        .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkAddMessages, input: data);
    }

    final messages = results.map((e) => Message.fromMap(e)).toList();
    if (hydrateAttachments) {
      MessageHydration.hydrateAll(messages);
    }
    return messages;
  }
}
