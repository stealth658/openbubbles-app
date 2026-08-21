import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/layouts/findmy/findmy_page.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/shared_streams_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/profile_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/scheduling/scheduled_messages_panel.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/ui/facetime_helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Message;
import 'package:get/get.dart';
import 'package:bluebubbles/services/backend/notifications/desktop_notification.dart';
import 'package:path/path.dart';
import 'package:synchronized/synchronized.dart';
import 'package:timezone/timezone.dart';
import 'package:universal_html/html.dart' hide File, Platform, Navigator, Text;
import 'package:universal_io/io.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
NotificationsService get NotificationsSvc => GetIt.I<NotificationsService>();

class PendingToastItem {
  final String? sender;
  final String text;
  final bool isReaction;
  final bool isGroupEvent;

  String get senderText => sender == null ? text : "$sender: $text";

  PendingToastItem({required this.sender, required this.text, required this.isReaction, required this.isGroupEvent});
}

class NotificationsService {
  static const String NEW_MESSAGE_CHANNEL = "com.bluebubbles.new_messages";
  static const String ERROR_CHANNEL = "com.bluebubbles.errors";
  static const String REMINDER_CHANNEL = "com.bluebubbles.reminders";
  static const String FACETIME_CHANNEL = "com.bluebubbles.incoming_facetimes";
  static const String FOREGROUND_SERVICE_CHANNEL = "com.bluebubbles.foreground_service";
  // OpenBubbles (rustpush) channels
  static const String SHARED_STREAMS_CHANNEL = "com.bluebubbles.sharedstreams";
  static const String SHARED_BEACONS_CHANNEL = "com.bluebubbles.sharedbeacons";
  static const String AUTH_CODES_CHANNEL = "com.bluebubbles.auth_codes";
  static const String SYNC_STATUS_CHANNEL = "com.bluebubbles.sync_status";

  static const String NEW_MESSAGE_TAG = "com.bluebubbles.messaging.NEW_MESSAGE_NOTIFICATION";
  static const String NEW_FACETIME_TAG = "com.bluebubbles.messaging.NEW_FACETIME_NOTIFICATION";

  final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
  StreamSubscription? countSub;
  int currentCount = 0;

  bool headless = false;

  /// For desktop use only
  static int? failedToast;
  static int? aliasesToast;
  static String? aliasesToastText;
  static Map<String, int> facetimeNotifications = {};
  static Map<String, int> activeToasts = {};
  static Map<String, Timer> debounceTimers = {};
  static Map<String, List<PendingToastItem>> pendingMessages = {};
  static final Lock _lock = Lock();
  static Player? _desktopNotificationPlayer;

  static const int maxLines = 4;
  static const int charsPerLineEst = 40;

  /// Windows toast identity. The toast icon is registered under the AUMID but only
  /// resolves when it matches the guid (flutter_local_notifications#2738), so one
  /// value serves as both.
  ///
  /// One value per distributable: the guid doubles as the toast activator CLSID, and a
  /// packaged manifest registration outranks the unpackaged HKCU one, so a shared value
  /// sends actions to the wrong app
  ///
  /// Store value must equal msix_config.toast_activator.clsid (pubspec.yaml), sideload
  /// value --toast-activator-clsid (windows/build.ps1).
  ///
  /// DO NOT CHANGE THESE
  static const String _storeMsixNotificationGuid = '1c09a4af-0327-4a79-a0f3-a1404df74ed1';
  static const String _sideloadMsixNotificationGuid = '68c6675d-9acf-4098-b539-20b5792427b5';
  static const String _exeNotificationGuid = '5963a68d-695e-4b6e-9596-421c0053a055';

  static String get windowsNotificationGuid => isStoreMsix
      ? _storeMsixNotificationGuid
      : isSideloadMsix
          ? _sideloadMsixNotificationGuid
          : _exeNotificationGuid;

  bool get hideContent => SettingsSvc.settings.hideTextPreviews.value;

  Future<void> init({bool headless = false}) async {
    this.headless = headless;
    if (!kIsWeb && !headless) {
      if (kIsDesktop) {
        DesktopNotifications.registerMessageInteractionHandler(_handleDesktopMessageInteraction);
      }
      await flnp.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_icon'),
          linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'BlueBubbles',
            appUserModelId: windowsNotificationGuid,
            guid: windowsNotificationGuid,
            iconPath: join(
              dirname(Platform.resolvedExecutable),
              'data',
              'flutter_assets',
              'assets',
              'icon',
              'icon.ico',
            ),
          ),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse? response) {
          if (response == null) return;
          if (kIsDesktop) {
            DesktopNotifications.handleResponse(response);
          } else if (response.payload != null) {
            if (GetIt.I.isRegistered<IntentsService>()) {
              // Fired for a notification tapped while the app was already attached
              // and running, so activeChat is guaranteed to be in sync.
              IntentsSvc.openChat(response.payload, isInitialIntent: false);
            } else {
              Logger.warn('IntentsService not registered, cannot open chat from notification tap');
            }
          }
        },
      );
      if (kIsDesktop) {
        DesktopNotifications.registerPlugin(flnp);
        return;
      }
      final details = await flnp.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp && details.notificationResponse?.payload != null) {
        if (GetIt.I.isRegistered<IntentsService>()) {
          // didNotificationLaunchApp means this tap is what launched the app — the
          // widget tree is starting fresh, so activeChat can't be trusted here.
          IntentsSvc.openChat(details.notificationResponse!.payload!, isInitialIntent: true);
        } else {
          Logger.warn('IntentsService not registered, cannot process notification launch payload');
        }
      }
    }
  }

  void close() {
    countSub?.cancel();
  }

  Future<void> createReminder(Chat? chat, Message? message, DateTime time,
      {String? chatTitle, String? messageText}) async {
    await flnp.zonedSchedule(
      id: Random().nextInt(9998) + 50000,
      title: chatTitle ?? 'Reminder: ${chat!.getTitle()}',
      body: messageText ?? (hideContent ? "iMessage" : message!.getNotificationText()),
      scheduledDate: TZDateTime.from(time, local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          REMINDER_CHANNEL,
          'Reminders',
          channelDescription: 'Message reminder notifications',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: "${time.millisecondsSinceEpoch}",
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// [notifyAnyways] is an OpenBubbles addition: rustpush can be told by the
  /// sender to alert even when the chat would normally be silenced.
  Future<void> createNotification(Chat chat, Message message, {bool notifyAnyways = false}) async {
    if (GetIt.I.isRegistered<LifecycleService>()) {
      await GetIt.I.isReady<LifecycleService>();
    }

    if (chat.shouldMuteNotification(message) || message.isFromMe!) return;
    final isGroup = chat.isGroup;
    final guid = chat.guid;
    final contactName = message.handleRelation.target?.displayName ?? "Unknown";
    final title = isGroup ? (ChatsSvc.getChatState(chat.guid)?.title.value ?? chat.getTitle()) : contactName;
    final text = hideContent ? "iMessage" : message.getNotificationText();
    final isReaction = !isNullOrEmpty(message.associatedMessageGuid);

    if (kIsWeb && Notification.permission == "granted") {
      final chatIcon = await avatarAsBytes(chat: chat, quality: 256);
      final notif =
          Notification(title, body: text, icon: "data:image/png;base64,${base64Encode(chatIcon)}", tag: message.guid);
      notif.onClick.listen((event) async {
        await IntentsSvc.openChat(guid, isInitialIntent: false);
      });
    } else if (kIsDesktop) {
      // Avatar loading is deferred to _buildAndShowToast — don't load it here.
      _lock.synchronized(
          () => showDesktopNotif(text, chat, title, contactName, message, isReaction, message.isGroupEvent));
    } else {
      if (message.guid != null && message.dateCreated != null) {
        if (!GetIt.I.isRegistered<MethodChannelService>()) {
          Logger.warn('MethodChannelService not registered; skipping incoming message notification');
          return;
        }

        final personIcon = (await rootBundle.load("assets/images/person64.png")).buffer.asUint8List();
        Uint8List chatIcon = await avatarAsBytes(chat: chat, quality: 256);
        final isFromMe = message.isFromMe ?? false;
        Uint8List contactIcon = isFromMe
            ? personIcon
            : await avatarAsBytes(
                participantsOverride: !chat.isGroup
                    ? null
                    : chat.handles.where((e) => e.address == message.handleRelation.target?.address).toList(),
                chat: chat,
                quality: 256);
        if (chatIcon.isEmpty) chatIcon = personIcon;
        if (contactIcon.isEmpty) contactIcon = personIcon;

        // Determine if reaction action should be shown (only if Private API is enabled & not a reaction message)
        final bool showReactionAction = SettingsSvc.settings.enablePrivateAPI.value &&
            SettingsSvc.settings.notificationReactionAction.value &&
            message.associatedMessageGuid == null;
        final String reactionType = SettingsSvc.settings.notificationReactionActionType.value;

        await GetIt.I.isReady<MethodChannelService>();
        // OpenBubbles: this mirrors MethodChannelActions.createIncomingMessageNotification
        // but adds the two rustpush-only keys (`contact_uri`, `notify_anyways`).
        await MethodChannelSvc.invokeMethod('create-incoming-message-notification', {
          'channel_id': NEW_MESSAGE_CHANNEL,
          'chat_id': chat.id,
          'chat_guid': guid,
          'chat_is_group': isGroup,
          'chat_title': title,
          'chat_icon': isGroup ? chatIcon : contactIcon,
          'contact_name': contactName,
          'contact_uri': isGroup ? null : chat.getRustHandlesExcludingMine().firstOrNull,
          'notify_anyways': notifyAnyways,
          'contact_avatar': contactIcon,
          'message_guid': message.guid!,
          'message_text': text,
          'message_date': message.dateCreated!.millisecondsSinceEpoch,
          'message_is_from_me': false,
          'show_reaction_action': showReactionAction,
          'reaction_type': reactionType,
        });
      }
    }
  }

  Future<void> tryCreateNewMessageNotification(Message message, Chat chat, {bool notifyAnyways = false}) async {
    if ((message.isFromMe ?? false) || !message.handleRelation.hasValue) {
      if (!(message.isFromMe ?? false) && !message.handleRelation.hasValue) {
        Logger.error(
          'Skipping notification for ${message.guid} in chat ${chat.guid} — '
          'handle relation not resolved (handleId=${message.handleId})',
          tag: 'NotificationsService',
        );
      }
      return;
    }
    if (message.isKeptAudio) return;
    // OpenBubbles: a rustpush CloudKit restore writes a large backlog of
    // messages; none of them should raise a notification.
    if (GetIt.I.isRegistered<ChatsService>() && ChatsSvc.restoring) return;
    if (chat.shouldMuteNotification(message)) return;
    if (!headless && LifecycleSvc.isAlive) {
      if (ChatsSvc.isChatActive(chat.guid)) return;
      if (ChatsSvc.activeChat == null &&
          Get.rawRoute?.settings.name == "/" &&
          !SettingsSvc.settings.notifyOnChatList.value) {
        return;
      }
    }

    await createNotification(chat, message, notifyAnyways: notifyAnyways);
  }

  /// [link], [poster] and the derived caller name are OpenBubbles additions used
  /// by the rustpush FaceTime UI; the BlueBubbles-server path leaves them null.
  Future<void> createIncomingFaceTimeNotification(String? callUuid, String caller, Uint8List? chatIcon, bool isAudio,
      {String? link, String? poster}) async {
    // Set some notification defaults
    String title = caller;
    String text = "${callUuid == null ? "Incoming" : "Answer"} FaceTime ${isAudio ? 'Audio' : 'Video'} Call";
    chatIcon ??= (await rootBundle.load("assets/images/person64.png")).buffer.asUint8List();

    if (kIsWeb && Notification.permission == "granted") {
      final notif =
          Notification(title, body: text, icon: "data:image/png;base64,${base64Encode(chatIcon)}", tag: callUuid);
      if (callUuid != null) {
        notif.onClick.listen((event) async {
          await IntentsSvc.answerFaceTime(callUuid);
        });
      }
    } else if (kIsDesktop) {
      _lock.synchronized(() async => await showPersistentDesktopFaceTimeNotif(callUuid, caller, chatIcon, isAudio));
    } else {
      final numeric = callUuid?.numericOnly();
      // OpenBubbles: mirrors MethodChannelActions.createIncomingFaceTimeNotification
      // plus the rustpush-only `link`, `name` and `poster` keys.
      await MethodChannelSvc.invokeMethod('create-incoming-facetime-notification', {
        'channel_id': FACETIME_CHANNEL,
        'notification_id':
            numeric != null ? int.parse(numeric.substring(0, min(8, numeric.length))) : Random().nextInt(9998) + 1,
        'title': title,
        'body': text,
        'caller_avatar': chatIcon,
        'caller': caller,
        'call_uuid': callUuid,
        'link': link ?? "",
        'name': await _localDisplayName(),
        'poster': poster,
      });
    }
  }

  Future<void> clearFaceTimeNotification(String callUuid) async {
    if (kIsDesktop) {
      await clearDesktopFaceTimeNotif(callUuid);
    } else if (!kIsWeb) {
      final numeric = callUuid.numericOnly();
      MethodChannelSvc.actions.deleteNotification(
        notificationId: int.parse(numeric.substring(0, min(8, numeric.length))),
        tag: NEW_FACETIME_TAG,
      );
    }
  }

  Future<void> showPersistentDesktopFaceTimeNotif(
    String? callUuid,
    String caller,
    Uint8List? avatar,
    bool isAudio,
  ) async {
    final String key = callUuid ?? caller;
    String? path;

    if (avatar != null) {
      Uint8List? _avatar = await clip(avatar, size: 256, circle: true);
      if (_avatar != null) {
        // Create a temp file with the avatar
        path = join(FilesystemSvc.appTempPath, "${randomString(8)}.png");
        await File(path).create(recursive: true);
        await File(path).writeAsBytes(_avatar);
      }
    }

    final int? existing = facetimeNotifications.remove(key);
    if (existing != null) {
      await DesktopNotifications.cancel(existing);
    }

    final int? id = await DesktopNotifications.showFaceTime(
      caller: caller,
      avatarPath: path,
      body: "Incoming FaceTime ${isAudio ? 'Audio' : 'Video'} Call",
      onOpen: () async {
        await showAndFocusWindow();
      },
      onAnswer: callUuid == null
          ? null
          : () async {
              await showAndFocusWindow();
              await IntentsSvc.answerFaceTime(callUuid);
            },
      onDecline: callUuid == null
          ? null
          : () async {
              hideFaceTimeOverlay(callUuid);
              await clearDesktopFaceTimeNotif(key);
            },
    );

    if (id != null) facetimeNotifications[key] = id;
  }

  Future<void> clearDesktopFaceTimeNotif(String callerUuid) async {
    final int? id = facetimeNotifications.remove(callerUuid);
    if (id != null) await DesktopNotifications.cancel(id);
  }

  void showDesktopNotif(
      String text, Chat chat, String title, String contactName, Message message, bool isReaction, bool isGroupEvent) {
    if (kIsDesktop && !SettingsSvc.settings.desktopNotifications.value) return;

    final String guid = chat.guid;

    pendingMessages[guid] ??= [];

    pendingMessages[guid]!.add(PendingToastItem(
        sender: chat.isGroup && !isReaction ? contactName.split(" ").first : null,
        text: text,
        isReaction: isReaction,
        isGroupEvent: isGroupEvent,
    ));

    // Cancel and clean up old timer
    final oldTimer = debounceTimers[guid];
    oldTimer?.cancel();
    debounceTimers[guid] = Timer(
      const Duration(milliseconds: 300),
      () async => await _buildAndShowToast(chat, title, message),
    );
  }

  Future<void> _buildAndShowToast(Chat chat, String title, Message message) async {
    final String guid = chat.guid;
    if (pendingMessages[guid]?.isEmpty ?? true) return;

    int usedLines = 0;
    int numToShow = 0;
    int numMessages = pendingMessages[guid]!.length;

    final int numSenders = pendingMessages[guid]!.map((p) => p.sender).nonNulls.toSet().length;
    for (int i = numMessages - 1; i >= 0; i--) {
      final PendingToastItem item = pendingMessages[guid]![i];
      final String displayText = numSenders > 1 ? item.senderText : item.text;
      final int newLines = _estimateLines(displayText);
      if (usedLines + newLines > maxLines) {
        break;
      }

      usedLines += newLines;
      numToShow += 1;
    }
    if (numToShow == 0) {
      numToShow = 1;
    }

    final int overflowCount = numMessages - numToShow;
    final String body = pendingMessages[guid]!
        .slice(overflowCount)
        .map((PendingToastItem e) => numSenders > 1 ? e.senderText : e.text)
        .join("\n");

    final PendingToastItem lastItem = pendingMessages[guid]!.last;
    final bool multipleMessages = numMessages > 1;

    String displayTitle;
    if (numSenders == 1 && !lastItem.isReaction && !lastItem.isGroupEvent) {
      displayTitle = "$title: ${lastItem.sender}";
    } else {
      displayTitle = title;
    }

    final (String path, bool isTemporaryFile) = await _chatAvatarPath(chat);

    final papi = SettingsSvc.settings.enablePrivateAPI.value;
    final List<int> selectedIndices = SettingsSvc.settings.selectedActionIndices;
    final List<String> actionValues = SettingsSvc.settings.actionList
        .whereIndexed((i, e) => selectedIndices.contains(i))
        .map(
          (action) => action == "Mark Read"
              ? 'mark-read'
              : !lastItem.isReaction && !lastItem.isGroupEvent && papi
              ? action
              : null,
        )
        .nonNulls
        .toList();

    final bool showMarkRead = actionValues.contains('mark-read');
    final List<String> actionLabels = multipleMessages
        ? showMarkRead
              ? ["Mark $numMessages Messages Read"]
              : const []
        : actionValues
              .map((action) => action == 'mark-read' ? 'Mark Read' : ReactionTypes.reactionToEmoji[action]!)
              .toList();
    final List<String> toastActions = multipleMessages && showMarkRead ? const ['mark-read'] : actionValues;
    final DesktopMessageData messageData = DesktopMessageData(
      chatGuid: guid,
      messageGuid: message.guid,
      actions: toastActions,
    );

    final String? attribution = overflowCount > 0
        ? "+$overflowCount earlier message${overflowCount > 1 ? "s" : ""}"
        : null;

    await playDesktopNotificationSound();

    int? existingToast = activeToasts.remove(guid);
    if (existingToast != null && attribution != null) {
      await DesktopNotifications.cancel(existingToast);
      existingToast = null;
    }
    if (existingToast == null) {
      await DesktopNotifications.cancelGroup(guid);
    }

    final int? id = await DesktopNotifications.showMessage(
      group: guid,
      replaceId: existingToast,
      avatarPath: path,
      title: displayTitle,
      body: body,
      attributionText: attribution,
      actionLabels: actionLabels,
      replyInput: SettingsSvc.settings.showReplyField.value,
      silent: SettingsSvc.settings.desktopNotificationSoundPath.value != null,
      messageData: messageData,
    );

    if (id != null) {
      activeToasts[guid] = id;
    }

    // No dismissal callback exists to clean up the temp avatar, so fall back to a delayed delete.
    if (isTemporaryFile) {
      Future.delayed(const Duration(minutes: 1), () => _deleteTempFile(path));
    }
  }

  /// Avatar file for [chat] and whether it's a temp file the caller should delete.
  /// Single-participant chats reuse the ContactV2 avatar file directly; group chats
  /// and custom avatars get a generated composite written to a temp file.
  Future<(String, bool)> _chatAvatarPath(Chat chat) async {
    if (chat.handles.length == 1 && chat.customAvatarPath == null) {
      final contactV2 = chat.handles.first.contactsV2.firstOrNull;
      // A reserved character in the file name means a row written before avatar
      // names were sanitized (macOS contact IDs end in `:ABPerson`). Windows can
      // neither build a file URI for it nor read it back reliably, so regenerate
      // a composite instead of handing the toast a path it will choke on.
      if (contactV2?.avatarPath != null &&
          !hasReservedFileNameChars(basename(contactV2!.avatarPath!)) &&
          await File(contactV2.avatarPath!).exists()) {
        return (contactV2.avatarPath!, false);
      }
    }
    final Uint8List avatar = await avatarAsBytes(chat: chat, quality: 256);
    final String path = join(FilesystemSvc.appTempPath, "${randomString(8)}.png");
    final File avatarFile = File(path);
    await avatarFile.create(recursive: true);
    await avatarFile.writeAsBytes(avatar);
    return (path, true);
  }

  int _estimateLines(String text) {
    return (text.length / charsPerLineEst).ceil() + "\n".allMatches(text).length;
  }

  void _cleanNotificationState(String guid) {
    activeToasts.remove(guid);
  }

  Future<void> _openChat(Chat chat) async {
    if (!ChatsSvc.isChatActive(chat.guid) && Get.context != null) {
      NavigationSvc.pushAndRemoveUntil(Get.context!, ConversationView(chat: chat), (route) => route.isFirst);
    }
  }

  Future<void> _handleDesktopMessageInteraction(DesktopMessageInteraction interaction) async {
    final DesktopMessageData data = interaction.data;
    final Chat? chat = ChatsSvc.findChatByGuid(data.chatGuid) ?? Chat.findOne(guid: data.chatGuid);
    if (chat == null) {
      Logger.warn(
        'Cannot handle desktop notification: chat ${data.chatGuid} no longer exists',
        tag: 'NotificationsService',
      );
      return;
    }

    _cleanNotificationState(data.chatGuid);
    if (interaction.reply != null) {
      final Message reply = Message(
        dateCreated: DateTime.now(),
        handleId: 0,
        text: interaction.reply,
        hasDdResults: true,
      );
      reply.generateTempGuid();
      OutgoingMsgHandler.queue(OutgoingMessage(chat: chat, message: reply));
      return;
    }

    if (interaction.action == 'mark-read') {
      chat.toggleHasUnreadAsync(false);
      EventDispatcher().emit('refresh', null);
      return;
    }

    if (interaction.action != null) {
      final Message? selectedMessage = data.messageGuid == null ? null : Message.findOne(guid: data.messageGuid);
      if (selectedMessage == null) {
        Logger.warn(
          'Cannot react from desktop notification: message ${data.messageGuid} no longer exists',
          tag: 'NotificationsService',
        );
        return;
      }
      final String reaction = interaction.action!;
      final Message reactionMessage = Message(
        associatedMessageGuid: selectedMessage.guid!,
        associatedMessageType: reaction,
        associatedMessagePart: 0,
        dateCreated: DateTime.now(),
        handleId: 0,
      );
      OutgoingMsgHandler.queue(
        OutgoingReaction(chat: chat, message: reactionMessage, selectedMessage: selectedMessage, reaction: reaction),
      );
      return;
    }

    await _openChat(chat);
    await showAndFocusWindow();
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore file deletion errors
    }
  }

  Future<void> playDesktopNotificationSound() async {
    if (SettingsSvc.settings.desktopNotificationSoundPath.value != null) {
      _desktopNotificationPlayer?.dispose();
      final player = Player();
      _desktopNotificationPlayer = player;
      await player.setVolume(SettingsSvc.settings.desktopNotificationSoundVolume.value.toDouble());
      await player.open(Media(SettingsSvc.settings.desktopNotificationSoundPath.value!));
      player.stream.completed.firstWhere((completed) => completed, orElse: () => false).then((_) async {
        await Future.delayed(const Duration(milliseconds: 450));
        if (_desktopNotificationPlayer == player) {
          await player.dispose();
          _desktopNotificationPlayer = null;
        }
      });
    }
  }

  Future<void> createAliasesRemovedNotification(List<String> aliases) async {
    const title = "iMessage alias deregistered!";
    const notifId = -3;
    final text = aliases.length == 1
        ? "${aliases[0]} has been deregistered!"
        : "The following aliases have been deregistered:\n${aliases.join("\n")}";

    if (kIsDesktop) {
      if (aliasesToastText == text) {
        return;
      }
      final int? existing = aliasesToast;
      if (existing != null) {
        await DesktopNotifications.cancel(existing);
      }

      aliasesToastText = text;
      aliasesToast = await DesktopNotifications.showText(
        title: title,
        body: text,
        onOpen: () async {
          aliasesToast = null;
          aliasesToastText = null;
          await showAndFocusWindow();
        },
      );
    } else {
      final notifs = await flnp.getActiveNotifications();

      //Already have this notification
      if (notifs.firstWhereOrNull((n) => n.id == notifId && n.body == text) != null) {
        return;
      }

      await flnp.show(
        id: notifId,
        title: title,
        body: text,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(ERROR_CHANNEL, 'Errors',
            channelDescription: 'Displays message send failures, connection failures, and more',
            priority: Priority.max,
            importance: Importance.max,
            color: HexColor("4990de"),
            ongoing: false,
            onlyAlertOnce: false,
              styleInformation: const BigTextStyleInformation('')),
        ),
      );
    }
  }

  Future<void> createFailedToSend(Chat chat, {bool scheduled = false}) async {
    final title = 'Failed to send${scheduled ? " scheduled" : ""} message';
    final subtitle = scheduled ? 'Tap to open scheduled messages list' : 'Tap to see more details or retry';
    if (kIsDesktop) {
      failedToast = await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          failedToast = null;
          await showAndFocusWindow();
          if (scheduled) {
            Navigator.of(Get.context!).push(
              ThemeSwitcher.buildPageRoute(
                builder: (BuildContext context) {
                  return const ScheduledMessagesPanel();
                },
              ),
            );
          } else {
            bool chatIsOpen = ChatsSvc.activeChat?.chat.guid == chat.guid;
            if (!chatIsOpen) {
            NavigationSvc.pushAndRemoveUntil(
              Get.context!,
              ConversationView(
                chat: chat,
              ),
              (route) => route.isFirst,
            );
            }
          }
        },
      );
      return;
    }
    await flnp.show(
      id: (chat.id! + 75000) * (scheduled ? -1 : 1),
      title: title,
      body: subtitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ERROR_CHANNEL,
          'Errors',
          channelDescription: 'Displays message send failures, connection failures, and more',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: chat.guid + (scheduled ? "-scheduled" : ""),
    );
  }

  Future<void> clearFailedToSend(int id) async {
    if (kIsDesktop) {
      final int? toastId = failedToast;
      failedToast = null;
      if (toastId != null) await DesktopNotifications.cancel(toastId);
      return;
    }
    await flnp.cancel(id: id);
  }


  // ───────────────────────── OpenBubbles (rustpush) ─────────────────────────

  /// The name shown to the callee on an outgoing/incoming FaceTime notification.
  Future<String> _localDisplayName() async {
    if (SettingsSvc.settings.userName.value != "You") return SettingsSvc.settings.userName.value;
    try {
      final handles = await api.getHandles(state: pushService.state!.client);
      return handles.first.replaceFirst("tel:", "").replaceFirst("mailto:", "");
    } catch (e, s) {
      Logger.warn("Failed to resolve local handle for FaceTime", error: e, trace: s, tag: "NotificationsService");
      return SettingsSvc.settings.userName.value;
    }
  }

  /// Shows the "someone is trying to sign in to your Apple Account" prompt.
  Future<void> notifySignInRequest(api.IdmsRequestedSignIn message) async {
    var title = message.aps.alert.title.replaceAll("Apple ID", "Apple Account");
    var subtitle = message.aps.alert.body.replaceAll("Apple ID", "Apple Account");
    try {
      final geocode = await pushService.reverseGeocode(message.akdata.lat, message.akdata.lng);

      String text;
      if (geocode!.administrativeArea != null) {
        final String? city = geocode.locality;
        if (city != null) {
          final String? state = geocode.administrativeArea?.substring(0, 2).toUpperCase();
          final String? country = geocode.isoCountryCode;
          text = state != null ? "$city, $state" : "$city, $country";
        } else {
          text = geocode.administrativeArea ?? geocode.country!;
        }
      } else {
        text = geocode.name!;
      }

      subtitle = subtitle.replaceAll("%loc%", text);
    } catch (e, s) {
      Logger.error("Failed to geocode!", error: e, trace: s);
    }

    if (kIsDesktop) {
      await showDialog(
        context: Get.context!,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Get.theme.colorScheme.properSurface,
          title: Text(title, style: Get.textTheme.titleLarge),
          content: Text(subtitle, style: Get.textTheme.bodyLarge),
          actions: [
            TextButton(
                onPressed: () {
                  api.teardown2Fa(
                      account: pushService.state!.icloudServices!.account, action: "albtn", txnid: message.txnid);
                  Get.back();
                },
                child: Text(message.aps.alert.albtn,
                    style: Get.textTheme.bodyLarge!.copyWith(color: Get.theme.colorScheme.primary))),
            TextButton(
                onPressed: () async {
                  api.teardown2Fa(
                      account: pushService.state!.icloudServices!.account, action: "defbtn", txnid: message.txnid);
                  Get.back();

                  final code = await api.approveCircle(
                      state: pushService.state!.activeCircleSessions,
                      account: pushService.state!.icloudServices!.account,
                      txnid: message.txnid);
                  pushService.authing = true;
                  final context = Get.context!;
                  await showDialog(
                      context: context,
                      builder: (_) {
                        return AlertDialog(
                          actions: [
                            TextButton(
                              child: Text("OK",
                                  style: context.theme.textTheme.bodyLarge!
                                      .copyWith(color: context.theme.colorScheme.primary)),
                              onPressed: () async {
                                Get.back();
                              },
                            ),
                          ],
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Use this code to log into your Apple Account on another device.",
                                  style: context.textTheme.bodyLarge),
                              const SizedBox(height: 30),
                              Text(code.toString().padLeft(6, '0'),
                                  style: context.textTheme.displaySmall
                                      ?.copyWith(color: context.textTheme.bodyLarge?.color, letterSpacing: 20)),
                              const SizedBox(height: 30),
                              Text("Do not share it with anyone. Apple will never call or text you for this code.",
                                  style: context.textTheme.bodyLarge),
                            ],
                          ),
                          title: Text("Verification code", style: context.theme.textTheme.titleLarge),
                          backgroundColor: context.theme.colorScheme.properSurface,
                        );
                      });

                  pushService.authing = false;
                },
                child: Text(message.aps.alert.defbtn,
                    style: Get.textTheme.bodyLarge!.copyWith(color: Get.theme.colorScheme.primary)))
          ],
        ),
      );

      await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          await showAndFocusWindow();
        },
      );
      return;
    }

    await MethodChannelSvc.invokeMethod("apple-account-login", {
      "title": title,
      "body": subtitle,
      "txnid": message.txnid,
      "defbtn": message.aps.alert.defbtn,
      "albtn": message.aps.alert.albtn,
      "sbdy": message.aps.alert.sbdy,
    });
  }

  /// Ongoing "Syncing with iCloud" notification. Pass null to clear it.
  Future<void> createSyncStatusNotification(String? status) async {
    if (kIsDesktop || kIsWeb) return;

    if (status == null) {
      await flnp.cancel(id: -3 - 50);
      return;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      SYNC_STATUS_CHANNEL,
      'Sync Status',
      channelDescription: 'View the status of iCloud syncing.',
      channelShowBadge: false,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      indeterminate: true,
    );

    await flnp.show(
      id: -3 - 50,
      title: 'Syncing with iCloud',
      body: status,
      notificationDetails: const NotificationDetails(android: androidPlatformChannelSpecifics),
      payload: "-53",
    );
  }

  Future<void> createSyncFailed(String status) async {
    if (kIsDesktop || kIsWeb) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      SYNC_STATUS_CHANNEL,
      'Sync Status',
      channelDescription: 'View the status of iCloud syncing.',
      channelShowBadge: false,
      importance: Importance.low,
      priority: Priority.low,
    );

    await flnp.show(
      id: -3 - 50,
      title: 'Syncing with iCloud Failed',
      body: status,
      notificationDetails: const NotificationDetails(android: androidPlatformChannelSpecifics),
    );
  }

  Future<void> createMissedCallNotification(String name, String callUuid) async {
    const text = "Missed FaceTime Call";

    if (kIsDesktop) {
      final int? existing = aliasesToast;
      if (existing != null) await DesktopNotifications.cancel(existing);
      aliasesToast = await DesktopNotifications.showText(
        title: name,
        body: text,
        onOpen: () async {
          aliasesToast = null;
          await showAndFocusWindow();
        },
      );
      return;
    }

    final numeric = callUuid.numericOnly();
    final notifId = int.parse(numeric.substring(0, min(8, numeric.length))) + 2;

    await MethodChannelSvc.invokeMethod("create-missed-facetime-notification", {
      "channel_id": FACETIME_CHANNEL,
      "notification_id": notifId,
      "call_uuid": callUuid,
      "title": name,
    });
  }

  void clearRegisterFailed() {
    if (kIsWeb || kIsDesktop) return;
    if (Platform.isAndroid) {
      MethodChannelSvc.actions.deleteNotification(notificationId: -1 - 50);
    }
  }

  Future<void> createRegisterFailed(bool loggedOut) async {
    final title = loggedOut ? 'Logged out by Apple!' : 'Failed to renew registration!';
    const subtitle = 'You can no longer send or receive iMessages. Tap for more info.';
    if (kIsDesktop) {
      failedToast = await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          failedToast = null;
          await showAndFocusWindow();
          if (SettingsSvc.settings.finishedSetup.value) {
            NavigationSvc.pushLeft(Get.context!, ProfilePanel());
          }
        },
      );
      return;
    }
    await flnp.show(
      id: -1 - 50,
      title: title,
      body: subtitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ERROR_CHANNEL,
          'Errors',
          channelDescription: 'Displays message send failures, connection failures, and more',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: loggedOut ? "" : "-51",
    );
  }

  Future<void> createSubscriptionFailed() async {
    const title = "Your subscription is no longer active!";
    const subtitle = "Your device will be given to someone else soon, and iMessage will no longer be activated.";
    if (kIsDesktop) {
      failedToast = await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          failedToast = null;
          await showAndFocusWindow();
          if (SettingsSvc.settings.finishedSetup.value) {
            NavigationSvc.pushLeft(Get.context!, ProfilePanel());
          }
        },
      );
      return;
    }
    await flnp.show(
      id: -1 - 50,
      title: title,
      body: subtitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ERROR_CHANNEL,
          'Errors',
          channelDescription: 'Displays message send failures, connection failures, and more',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: "-51",
    );
  }

  Future<void> createBeaconInvitation(Handle sender, api.BeaconAttributes attributes) async {
    const title = "A new item has been shared with you!";
    final subtitle = "${sender.displayName} has shared the location of ${attributes.name} with you!";
    if (kIsDesktop) {
      failedToast = await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          failedToast = null;
          await showAndFocusWindow();
          if (SettingsSvc.settings.finishedSetup.value) {
            NavigationSvc.pushLeft(Get.context!, FindMyPage());
          }
        },
      );
      return;
    }
    await flnp.show(
      id: -4 - 50,
      title: title,
      body: subtitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          SHARED_BEACONS_CHANNEL,
          'Shared Items',
          channelDescription: 'Displays invitations and updates for shared items.',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: "-54",
    );
  }

  Future<void> createInvitation(api.SharedAlbum album) async {
    const title = "Shared albums";
    final subtitle = "${album.fullname} invited you to join \"${album.name}\"";
    if (kIsDesktop) {
      failedToast = await DesktopNotifications.showText(
        title: title,
        body: subtitle,
        onOpen: () async {
          failedToast = null;
          await showAndFocusWindow();
          if (SettingsSvc.settings.finishedSetup.value) {
            NavigationSvc.pushLeft(Get.context!, SharedStreamsPanel());
          }
        },
      );
      return;
    }
    await flnp.show(
      id: -2 - 50,
      title: title,
      body: subtitle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          SHARED_STREAMS_CHANNEL,
          'Shared Albums',
          channelDescription: 'Displays invitations and updates for shared albums.',
          priority: Priority.max,
          importance: Importance.max,
          color: HexColor("4990de"),
        ),
      ),
      payload: "-52",
    );
  }

  Future<void> clearDesktopNotificationsForChat(String chatGuid) async {
    await _lock.synchronized(() async {
      final int? toastId = activeToasts[chatGuid];
      if (toastId != null) await DesktopNotifications.cancel(toastId);
      await DesktopNotifications.cancelGroup(chatGuid);
      _cleanNotificationState(chatGuid);
      debounceTimers[chatGuid]?.cancel();
      debounceTimers.remove(chatGuid);
      pendingMessages.remove(chatGuid);
    });
  }
}
