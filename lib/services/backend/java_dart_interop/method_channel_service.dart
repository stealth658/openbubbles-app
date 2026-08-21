import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/services/network/method_channel_actions.dart';
import 'package:bluebubbles/services/backend/java_dart_interop/method_channel_constants.dart';
import 'package:bluebubbles/services/backend/java_dart_interop/method_channel_handlers.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';

// ignore: non_constant_identifier_names
MethodChannelService get MethodChannelSvc => GetIt.I<MethodChannelService>();

class MethodChannelService implements MethodChannelServiceDelegate {
  late final MethodChannel channel;
  late final MethodChannelActions actions;
  late final MethodChannelHandlers _handlers;

  @override
  bool headless = false;
  bool isBubble = false;

  // music theme
  @override
  bool isRunning = false;
  @override
  Uint8List? previousArt;

  /// OpenBubbles: SIM cards reported by the Android side, used for SMS routing.
  final RxList<Map<String, dynamic>> simInfo = <Map<String, dynamic>>[].obs;

  /// Whether this isolate should drop a push copy because another consumer owns it.
  ///
  /// Note what this deliberately does *not* check: whether this isolate's socket is
  /// connected. It usually isn't — `LifecycleService.close()` disconnects on
  /// background — because the hand-off here is to the **headless isolate**, which
  /// never ignores (see the `headless` bail-out above), not to our own socket.
  ///
  /// So resist adding a `socket.connected` condition to make this "safer". It would
  /// flip to `false` for essentially every backgrounded push, and then both this
  /// isolate and the headless one would process the same message. They share only
  /// the database — `_processedGuids` and `_inflightByGuid` in
  /// [IncomingMessageHandler] are per-isolate — so both can pass the
  /// `Message.findOne` existence check before either writes, and both reach the
  /// notification dispatch. If this drop is ever wrong, the fix belongs on the
  /// Android side, in which isolate gets handed the push.
  ///
  /// Contrast [MethodChannelHandlers._handleNewMessage], which drops in favour of
  /// *this* isolate's socket and therefore does have to check `connected`.
  @override
  bool get shouldIgnoreMessage {
    if (headless) return false;
    final hasLifecycle = GetIt.I.isRegistered<LifecycleService>();
    final hasSettings = GetIt.I.isRegistered<SettingsService>();
    if (!hasLifecycle || !hasSettings) return false;
    return !LifecycleSvc.isAlive && SettingsSvc.settings.keepAppAlive.value;
  }

  Future<void> init({bool headless = false, bool isBubble = false, BinaryMessenger? binaryMessenger}) async {
    if (kIsWeb || kIsDesktop) return;
    if (binaryMessenger == null) {
      WidgetsFlutterBinding.ensureInitialized();
    }
    Logger.debug("Initializing MethodChannelService${headless ? " in headless mode" : ""}");

    this.headless = headless;
    this.isBubble = isBubble;

    channel = MethodChannel('com.bluebubbles.messaging', const StandardMethodCodec(), binaryMessenger);
    actions = MethodChannelActions(this);
    _handlers = MethodChannelHandlers(this);

    // Only set a method call handler on direct-engine connections. Isolates
    // using BackgroundIsolateBinaryMessenger should not own a channel handler.
    if (binaryMessenger == null) {
      channel.setMethodCallHandler(_callHandler);
      unawaited(actions.signalReady());
    }

    if (!kIsWeb && !kIsDesktop && !headless) {
      try {
        if (SettingsSvc.settings.colorsFromMedia.value) {
          await actions.startNotificationListener();
        }
        if (!this.isBubble) {
          BackgroundIsolate.initialize();
          // OpenBubbles: register the rustpush CloudKit background sync isolate.
          SyncIsolate.initialize();
        }
        // chromeOS = await mcs().invokeMethod("check-chromeos") ?? false;
      } catch (_) {}
    }

    // Only create notification channels when running on the main engine connection.
    // The GlobalIsolate passes a BackgroundIsolateBinaryMessenger whose reply ports are
    // invalidated by concurrent isolate work, causing a fatal SIGABRT. The DartWorker
    // and the main isolate both pass null (direct engine), so they are safe to call this.
    if (binaryMessenger == null && !headless) unawaited(createAllNotificationChannels());

    Logger.debug("MethodChannelService initialized");
  }

  Future<bool> _callHandler(MethodCall call) async {
    final Map<String, dynamic>? arguments =
        call.arguments is String ? jsonDecode(call.arguments) : call.arguments?.cast<String, Object>();

    // ONLY RETURN Future.value or Future.error
    // Future.value(false) will have the engine retry the call
    // Future.value(true) will have the engine stop trying to call the method

    // OpenBubbles (rustpush) method calls. These have no BlueBubbles-server
    // equivalent, so they are handled here rather than in MethodChannelHandlers.
    final forkResult = await _handleOpenBubblesCall(call, arguments);
    if (forkResult != null) return forkResult;

    // OpenBubbles: replying from a notification touches rustpush state, so make
    // sure the push service has finished initializing before the handler runs.
    if (call.method == MethodChannelInboundMethods.replyChat) {
      await pushService.initFuture;
    }

    return _handlers.handle(call, arguments);
  }

  /// Handles the rustpush-only method channel calls. Returns `null` when [call]
  /// is not one of them, so the caller can fall through to [MethodChannelHandlers].
  Future<bool?> _handleOpenBubblesCall(MethodCall call, Map<String, dynamic>? arguments) async {
    switch (call.method) {
      case "SMSMsg":
        try {
          if (!SettingsSvc.settings.isSmsRouter.value) return true;
          List<Object?> addresses = call.arguments["recipients"];
          String sender = call.arguments["sender"];
          List<Object?> body = call.arguments["body"];
          int threadId = call.arguments["thread_id"];
          List<Map<String, dynamic>> mapped =
              body.map((e) => (e as Map<Object?, Object?>).cast<String, dynamic>()).toList();
          Chat chat = await Chat.getChatForTel(threadId, addresses.map((e) {
            var map = (e as Map<Object?, Object?>).cast<String, dynamic>();
            return map["address"] as String;
          }).toList());
          // sent from me
          bool fromMe = sender == "me";
          if (fromMe && pushService.disableOutgoingSms) return true;
          if (fromMe) sender = (await chat.ensureHandle()).replaceFirst("tel:", "");

          await chat.deliverSMS(sender, fromMe, mapped);
        } catch (e, s) {
          Logger.error("SMS deliver error", error: e, trace: s);
          rethrow;
        }
        return true;
      case "APNMsg":
        try {
          String pointer = call.arguments["pointer"];
          String retry = call.arguments["retry"];
          Logger.info("got message $pointer $retry");
          await pushService.recievedMsgPointer(pointer, retry);
          Logger.info("finish message $pointer $retry");
        } catch (e, s) {
          Logger.error("APN MSG error", error: e, trace: s);
          rethrow;
        }
        return true;
      case "sim-info":
        try {
          List<Object?> info = call.arguments["info"];
          var address = info.map((e) => (e as Map<Object?, Object?>).cast<String, dynamic>()).toList();
          simInfo.value = address;
        } catch (e, s) {
          Logger.error("SIM info error", error: e, trace: s);
          rethrow;
        }
        return true;
      case "extension-add-message":
        try {
          es.addMessage(arguments!);
          return true;
        } catch (e, s) {
          Logger.error("Add extension error", error: e, trace: s);
          return Future.error(PlatformException(code: "500", message: e.toString()), s);
        }
      case "extension-update-message":
        try {
          await es.updateMessage(arguments!);
          return true;
        } catch (e, s) {
          Logger.error("Extension update error", error: e, trace: s);
          return Future.error(PlatformException(code: "500", message: e.toString()), s);
        }
      case "extension-set-suppress":
        try {
          await es.setSuppress(arguments!);
          return true;
        } catch (e, s) {
          Logger.error("Set suppress error", error: e, trace: s);
          return Future.error(PlatformException(code: "500", message: e.toString()), s);
        }
      default:
        return null;
    }
  }

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    if (kIsWeb || kIsDesktop) return;
    Logger.info("Sending method $method to Kotlin");
    return await channel.invokeMethod(method, arguments);
  }

  /// Not in the NotificationService to avoid circular dependency.
  /// The method channel service handles kotlin messages, which may
  /// invoke actions that use notifications (i.e. new-message events).
  Future<void> createAllNotificationChannels() async {
    await actions.createNotificationChannel(
      channelId: NotificationsService.NEW_MESSAGE_CHANNEL,
      channelName: "New Messages",
      channelDescription: "Displays all received new messages",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.ERROR_CHANNEL,
      channelName: "Errors",
      channelDescription: "Displays message send failures, connection failures, and more",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.REMINDER_CHANNEL,
      channelName: "Message Reminders",
      channelDescription: "Displays message reminders set through the app",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.FACETIME_CHANNEL,
      channelName: "Incoming FaceTimes",
      channelDescription: "Displays incoming FaceTimes detected by the server",
    );
    // OpenBubbles (rustpush) channels
    await actions.createNotificationChannel(
      channelId: NotificationsService.SHARED_STREAMS_CHANNEL,
      channelName: "Shared Albums",
      channelDescription: "Displays invitations and updates for shared albums",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.SHARED_BEACONS_CHANNEL,
      channelName: "Shared Items",
      channelDescription: "Displays invitations and updates for shared items",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.AUTH_CODES_CHANNEL,
      channelName: "Apple Account login requests",
      channelDescription: "Shows Apple Account login requests",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.SYNC_STATUS_CHANNEL,
      channelName: "Sync Status",
      channelDescription: "View the status of iCloud syncing",
    );
    await actions.createNotificationChannel(
      channelId: NotificationsService.FOREGROUND_SERVICE_CHANNEL,
      channelName: "Foreground Service",
      channelDescription:
          "Allows BlueBubbles to stay open in the background for notifications if FCM is not being used",
    );
  }
}
