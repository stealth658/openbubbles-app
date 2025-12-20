import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/helpers/backend/settings_helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/services/backend/settings/shared_preferences_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
MethodChannelService get MethodChannelSvc => GetIt.I<MethodChannelService>();

class MethodChannelService {
  late final MethodChannel channel;
  bool background = false;
  bool isBubble = false;

  // music theme
  bool isRunning = false;
  Uint8List? previousArt;

  Future<void> init({bool headless = false, bool isBubble = false, BinaryMessenger? binaryMessenger}) async {
    if (kIsWeb || kIsDesktop) return;
    Logger.debug("Initializing MethodChannelService${headless ? " in headless mode" : ""}");

    background = headless;
    this.isBubble = isBubble;
    channel = MethodChannel(
      'com.bluebubbles.messaging',
      const StandardMethodCodec(),
      binaryMessenger);

    // Only send the ready signal if we are in the BackgroundIsolate/UI (not the GlobalIsolate)
    if (binaryMessenger == null) {
      channel.setMethodCallHandler(_callHandler);
      channel.invokeMethod("ready");
    }
    
    if (!kIsWeb && !kIsDesktop && !headless) {
      try {
        if (SettingsSvc.settings.colorsFromMedia.value) {
          await MethodChannelSvc.invokeMethod("start-notification-listener");
        }
        if (!this.isBubble) {
          BackgroundIsolate.initialize();
        }
        // chromeOS = await mcs().invokeMethod("check-chromeos") ?? false;
      } catch (_) {}
    }

    Logger.debug("MethodChannelService initialized");
  }

  Future<bool> _callHandler(MethodCall call) async {
    final Map<String, dynamic>? arguments = call.arguments is String ? jsonDecode(call.arguments) : call.arguments?.cast<String, Object>();
    
    // ONLY RETURN Future.value or Future.error
    // Future.value(false) will have the engine retry the call
    // Future.value(true) will have the engine stop trying to call the method
    
    switch (call.method) {
      case "NewServerUrl":
        if (arguments == null) return Future.value(false);
        await Database.waitForInit();

        String address = arguments["server_url"];
        bool updated = await saveNewServerUrl(address, restartSocket: false);
        if (updated && !background) {
          SocketSvc.restartSocket();
        }
        return Future.value(true);
      case "new-message":  // FCM message
        await Database.waitForInit();
        Logger.info("Received new message from MethodChannel");

        // The socket will handle this event if the app is alive and unifiedpush is not enabled
        if (LifecycleSvc.isAlive && (SocketSvc.socket?.connected ?? false) && SettingsSvc.settings.endpointUnifiedPush.value == "") {
          Logger.debug("App is alive, ignoring new message...");
          return Future.value(true);
        } else if (!LifecycleSvc.isAlive && SettingsSvc.settings.keepAppAlive.value) {
          Logger.debug("Ignoring FCM message while app is not alive, but keepAppAlive is enabled");
          return Future.value(true);
        }

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            final item = IncomingItem.fromMap(QueueType.newMessage, payload.data);
            if (LifecycleSvc.isAlive && SettingsSvc.settings.endpointUnifiedPush.value == "") {
              await inq.queue(item);
            } else {
              await ah.handleNewMessage(item.chat, item.message, item.tempGuid);
            }
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "updated-message":
        await Database.waitForInit();
        Logger.info("Received updated message from MethodChannel");

        // The socket will handle this event if the app is alive
        if (LifecycleSvc.isAlive && (SocketSvc.socket?.connected ?? false)) {
          Logger.debug("App is alive, ignoring updated message...");
          return Future.value(true);
        } else if (!LifecycleSvc.isAlive && SettingsSvc.settings.keepAppAlive.value) {
          Logger.debug("Ignoring FCM message while app is not alive, but keepAppAlive is enabled");
          return Future.value(true);
        }

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);

            // Since this is an updated-message event, the message should exist in the DB.
            // So if there is no chat, we can find it from the message guid
            if (payload.data["chats"] == null || payload.data["chats"].isEmpty) {
              Logger.warn("No chat data found, attempting to find chat from message guid...");
              final existingMsg = Message.findOne(guid: payload.data["guid"]);
              if (existingMsg != null && existingMsg.chat.target != null) {
                Logger.debug("Found chat from message guid, adding to payload");
                payload.data['chats'] = [existingMsg.chat.target!.toMap()];
              } else {
                Logger.warn("No chat data found, and unable to find chat from message guid");
                return Future.value(false);
              }
            }

            final item = IncomingItem.fromMap(QueueType.updatedMessage, payload.data);
            if (LifecycleSvc.isAlive) {
              await inq.queue(item);
            } else {
              await ah.handleUpdatedMessage(item.chat, item.message, item.tempGuid);
            }
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "group-name-change":
      case "participant-removed":
      case "participant-added":
      case "participant-left":
        await Database.waitForInit();
        Logger.info("Received ${call.method} from MethodChannel");

        // The socket will handle this event if the app is alive
        if (LifecycleSvc.isAlive && (SocketSvc.socket?.connected ?? false)) {
          Logger.debug("App is alive, ignoring updated message...");
          return Future.value(true);
        } else if (!LifecycleSvc.isAlive && SettingsSvc.settings.keepAppAlive.value) {
          Logger.debug("Ignoring FCM message while app is not alive, but keepAppAlive is enabled");
          return Future.value(true);
        }

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            final item = IncomingItem.fromMap(QueueType.updatedMessage, payload.data);
            await ah.handleNewOrUpdatedChat(item.chat);
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "group-icon-changed":
        await Database.waitForInit();
        Logger.info("Received group icon change from MethodChannel");

        // The socket will handle this event if the app is alive
        if (LifecycleSvc.isAlive && (SocketSvc.socket?.connected ?? false)) {
          Logger.debug("App is alive, ignoring updated message...");
          return Future.value(true);
        } else if (!LifecycleSvc.isAlive && SettingsSvc.settings.keepAppAlive.value) {
          Logger.debug("Ignoring FCM message while app is not alive, but keepAppAlive is enabled");
          return Future.value(true);
        }

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            final guid = payload.data["chats"].first["guid"];
            final chat = Chat.findOne(guid: guid);
            if (chat != null) {
              await Chat.getIcon(chat);
            }
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "scheduled-message-error":
        Logger.info("Received scheduled message error from FCM");
        try {
          Map<String, dynamic>? data = arguments;
          if (data == null) return Future.value(true);
          final payload = ServerPayload.fromJson(data);
          Chat? chat = Chat.findOne(guid: payload.data["payload"]["chatGuid"]);
          if (chat != null) {
            await NotificationsSvc.createFailedToSend(chat, scheduled: true);
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "ReplyChat":
        await Database.waitForInit();
        Logger.info("Received reply to message from Kotlin");
        final Map<String, dynamic>? data = arguments;
        if (data == null) return Future.value(true);

        // check and make sure that we aren't sending a duplicate reply
        final recentReplyGuid = PrefsSvc.i.getString("recent-reply")?.split("/").first;
        final recentReplyText = PrefsSvc.i.getString("recent-reply")?.split("/").last;
        if (recentReplyGuid == data["messageGuid"] && recentReplyText == data["text"]) return Future.value(false);
        await PrefsSvc.i.setString("recent-reply", "${data["messageGuid"]}/${data["text"]}");
        Logger.info("Updated recent reply cache to ${PrefsSvc.i.getString("recent-reply")}");
        Chat? chat = Chat.findOne(guid: data["chatGuid"]);
        if (chat == null) {
          return Future.value(false);
        } else {
          final Completer<void> completer = Completer();
          outq.queue(OutgoingItem(
            type: QueueType.sendMessage,
            completer: completer,
            chat: chat,
            message: Message(
              text: data['text'],
              dateCreated: DateTime.now(),
              hasAttachments: false,
              isFromMe: true,
              handleId: 0,
            ),
            customArgs: {'notifReply': true}
          ));
          await completer.future;
          return Future.value(true);
        }
      case "MarkChatRead":
        if (LifecycleSvc.isAlive) return Future.value(true);
        await Database.waitForInit();
        Logger.info("Received markAsRead from Kotlin");

        try {
          final Map<String, dynamic>? data = arguments;
          if (data != null) {
            Chat? chat = Chat.findOne(guid: data["chatGuid"]);
            if (chat != null) {
              // Don't clear local notifications because tapping Mark as Read should clear the notification automatically
              chat.toggleHasUnreadAsync(false, clearLocalNotifications: false);
              return Future.value(true);
            }
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(false);
      case "chat-read-status-changed":
        if (LifecycleSvc.isAlive) return Future.value(true);
        await Database.waitForInit();
        Logger.info("Received chat status change from FCM");

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            Chat? chat = Chat.findOne(guid: payload.data["chatGuid"]);
            if (chat == null || (payload.data["read"] != true && payload.data["read"] != false)) {
              return Future.value(false);
            } else {
              chat.toggleHasUnreadAsync(!payload.data["read"]!, privateMark: false);
              return Future.value(true);
            }
          } else {
            return Future.value(false);
          }
        } catch (e, s) {
          return Future.error(e, s);
        }
      case "MediaColors":
        await Database.waitForInit();
        if (!SettingsSvc.settings.colorsFromMedia.value) return Future.value(true);

        final Uint8List art = call.arguments["albumArt"];
        if (Get.context != null && (!isRunning || art != previousArt)) {
          ThemeSvc.updateMusicTheme(Get.context!, art);
          isRunning = false;
        }

        return Future.value(true);
      case "incoming-facetime":
        await Database.waitForInit();
        Logger.info("Received legacy incoming facetime from FCM");
        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            await ActionHandler().handleIncomingFaceTimeCallLegacy(payload.data);
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "ft-call-status-changed":
        if (LifecycleSvc.isAlive) return Future.value(true);
        await Database.waitForInit();
        Logger.info("Received facetime call status change from FCM");

        try {
          Map<String, dynamic>? data = arguments;
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            await ActionHandler().handleFaceTimeStatusChange(payload.data);
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "answer-facetime":
        Logger.info("Answering FaceTime call");
        final Map<String, dynamic>? data = arguments;
        if (data == null) return Future.value(true);
        await IntentsSvc.answerFaceTime(data["callUuid"]);
        return Future.value(true);
      case "imessage-aliases-removed":
        Map<String, dynamic>? data = arguments;
        try {
          if (!isNullOrEmpty(data)) {
            final payload = ServerPayload.fromJson(data!);
            Logger.info("Alias(es) removed ${payload.data["aliases"]}");
            await NotificationsSvc.createAliasesRemovedNotification((payload.data["aliases"] as List).cast<String>());
          } else {
            Logger.warn("Aliases removed data empty or null");
          }
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "socket-event":
        Map<String, dynamic>? data = arguments;
        if (data == null) return Future.value(true);

        try {
          final Map<String, dynamic> jsonData = jsonDecode(data['data']);
          await ah.handleEvent(data['event'], jsonData, 'MethodChannel', useQueue: false);
        } catch (e, s) {
          return Future.error(e, s);
        }

        return Future.value(true);
      case "unifiedpush-settings":
        Map<String, dynamic>? data = arguments;
        if (data == null) return false;

        try {
            final String endpoint = data['endpoint'].toString();
            upr.update(endpoint);
        } catch(e, s) {
            return Future.error(e, s);
        }

        return Future.value(true);
      default:
        return Future.value(true);
    }
  }

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    if (kIsWeb || kIsDesktop) return;
    Logger.info("Sending method $method to Kotlin");
    return await channel.invokeMethod(method, arguments);
  }
}
