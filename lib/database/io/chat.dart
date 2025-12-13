import 'dart:async';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:metadata_fetch/metadata_fetch.dart';
// (needed when generating objectbox model code)
// ignore: unnecessary_import
import 'package:objectbox/objectbox.dart';
import 'package:universal_io/io.dart';

@Entity()
class Chat {
  int? id;

  @Index(type: IndexType.value)
  @Unique()
  String guid;

  String? chatIdentifier;
  bool? isArchived;
  String? muteType;
  String? muteArgs;
  bool? isPinned;
  bool? hasUnreadMessage;
  String? title;
  String get properTitle {
    if (SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value) {
      return getTitle();
    }
    title ??= getTitle();
    return title!;
  }

  String? displayName;
  List<Handle> _participants = [];
  List<Handle> get participants {
    if (_participants.isEmpty) {
      getParticipants();
    }
    return _participants;
  }

  bool? autoSendReadReceipts;
  bool? autoSendTypingIndicators;
  String? textFieldText;
  List<String> textFieldAttachments = [];
  Message? _latestMessage;
  Message get latestMessage {
    if (_latestMessage != null) return _latestMessage!;
    _latestMessage = Chat.getMessages(this, limit: 1, getDetails: true).firstOrNull ??
        Message(
          dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
          guid: guid,
        );
    return _latestMessage!;
  }

  Message get dbLatestMessage {
    _latestMessage = Chat.getMessages(this, limit: 1, getDetails: true).firstOrNull ??
        Message(
          dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
          guid: guid,
        );
    return _latestMessage!;
  }

  set latestMessage(Message m) => _latestMessage = m;
  @Property(uid: 526293286661780207)
  DateTime? dbOnlyLatestMessageDate;
  DateTime? dateDeleted;
  int? style;
  bool lockChatName;
  bool lockChatIcon;
  String? lastReadMessageGuid;

  final RxnString _customAvatarPath = RxnString();
  String? get customAvatarPath => _customAvatarPath.value;
  set customAvatarPath(String? s) => _customAvatarPath.value = s;

  final RxnInt _pinIndex = RxnInt();
  int? get pinIndex => _pinIndex.value;
  set pinIndex(int? i) => _pinIndex.value = i;

  @Transient()
  RxDouble sendProgress = 0.0.obs;

  final handles = ToMany<Handle>();

  @Backlink('chat')
  final messages = ToMany<Message>();

  @Transient()
  String? _fakeName;

  @Transient()
  String get fakeName {
    if (_fakeName != null) return _fakeName!;
    _fakeName = faker.lorem.words(properTitle.split(' ').length).join(" ").capitalize;
    return _fakeName!;
  }

  Chat({
    this.id,
    required this.guid,
    this.chatIdentifier,
    this.isArchived = false,
    this.isPinned = false,
    this.muteType,
    this.muteArgs,
    this.hasUnreadMessage = false,
    this.displayName,
    String? customAvatar,
    int? pinnedIndex,
    List<Handle>? participants,
    Message? latestMessage,
    this.autoSendReadReceipts,
    this.autoSendTypingIndicators,
    this.textFieldText,
    this.textFieldAttachments = const [],
    this.dateDeleted,
    this.style,
    this.lockChatName = false,
    this.lockChatIcon = false,
    this.lastReadMessageGuid,
  }) {
    customAvatarPath = customAvatar;
    pinIndex = pinnedIndex;
    if (textFieldAttachments.isEmpty) textFieldAttachments = [];
    _participants = participants ?? [];
    _latestMessage = latestMessage;
  }

  factory Chat.fromMap(Map<String, dynamic> json) {
    final message = json['lastMessage'] != null ? Message.fromMap(json['lastMessage']!.cast<String, Object>()) : null;
    return Chat(
      id: json["ROWID"] ?? json["id"],
      guid: json["guid"],
      chatIdentifier: json["chatIdentifier"],
      isArchived: json['isArchived'] ?? false,
      muteType: json["muteType"],
      muteArgs: json["muteArgs"],
      isPinned: json["isPinned"] ?? false,
      hasUnreadMessage: json["hasUnreadMessage"] ?? false,
      latestMessage: message,
      displayName: json["displayName"],
      customAvatar: json['_customAvatarPath'],
      pinnedIndex: json['_pinIndex'],
      participants:
          (json['participants'] as List? ?? []).map((e) => Handle.fromMap(e!.cast<String, Object>())).toList(),
      autoSendReadReceipts: json["autoSendReadReceipts"],
      autoSendTypingIndicators: json["autoSendTypingIndicators"],
      dateDeleted: parseDate(json["dateDeleted"]),
      style: json["style"],
      lockChatName: json["lockChatName"] ?? false,
      lockChatIcon: json["lockChatIcon"] ?? false,
      lastReadMessageGuid: json["lastReadMessageGuid"],
    );
  }

  /// Save a chat to the DB
  Chat save({
    bool updateMuteType = false,
    bool updateMuteArgs = false,
    bool updateIsPinned = false,
    bool updatePinIndex = false,
    bool updateIsArchived = false,
    bool updateHasUnreadMessage = false,
    bool updateAutoSendReadReceipts = false,
    bool updateAutoSendTypingIndicators = false,
    bool updateCustomAvatarPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
  }) {
    if (kIsWeb) return this;
    Database.runInTransaction(TxMode.write, () {
      /// Find an existing, and update the ID to the existing ID if necessary
      Chat? existing = Chat.findOne(guid: guid);
      id = existing?.id ?? id;
      if (!updateMuteType) {
        muteType = existing?.muteType ?? muteType;
      }
      if (!updateMuteArgs) {
        muteArgs = existing?.muteArgs ?? muteArgs;
      }
      if (!updateIsPinned) {
        isPinned = existing?.isPinned ?? isPinned;
      }
      if (!updatePinIndex) {
        pinIndex = existing?.pinIndex ?? pinIndex;
      }
      if (!updateIsArchived) {
        isArchived = existing?.isArchived ?? isArchived;
      }
      if (!updateHasUnreadMessage) {
        hasUnreadMessage = existing?.hasUnreadMessage ?? hasUnreadMessage;
      }
      if (!updateAutoSendReadReceipts) {
        autoSendReadReceipts = existing?.autoSendReadReceipts;
      }
      if (!updateAutoSendTypingIndicators) {
        autoSendTypingIndicators = existing?.autoSendTypingIndicators;
      }
      if (!updateCustomAvatarPath) {
        customAvatarPath = existing?.customAvatarPath ?? customAvatarPath;
      }
      if (!updateTextFieldText) {
        textFieldText = existing?.textFieldText ?? textFieldText;
      }
      if (!updateTextFieldAttachments) {
        textFieldAttachments = existing?.textFieldAttachments ?? textFieldAttachments;
      }
      if (!updateDisplayName) {
        displayName = existing?.displayName ?? displayName;
      }
      if (!updateDateDeleted) {
        dateDeleted = existing?.dateDeleted;
      }
      if (!updateLockChatName) {
        lockChatName = existing?.lockChatName ?? false;
      }
      if (!updateLockChatIcon) {
        lockChatIcon = existing?.lockChatIcon ?? false;
      }
      if (!updateLastReadMessageGuid) {
        lastReadMessageGuid = existing?.lastReadMessageGuid ?? lastReadMessageGuid;
      }

      /// Save the chat and add the participants
      for (int i = 0; i < participants.length; i++) {
        participants[i] = participants[i].save();
        _deduplicateParticipants();
      }
      dbOnlyLatestMessageDate = dbLatestMessage.dateCreated!;
      try {
        id = Database.chats.put(this);
        // make sure to add participant relation if its a new chat
        if (existing == null && participants.isNotEmpty) {
          final toSave = Database.chats.get(id!);
          toSave!.handles.clear();
          toSave.handles.addAll(participants);
          toSave.handles.applyToDb();
        } else if (existing == null && participants.isEmpty) {
          cm.fetchChat(guid);
        }
      } on UniqueViolationException catch (_) {}
    });
    return this;
  }

  /// Save a chat to the DB asynchronously (non-blocking)
  Future<Chat> saveAsync({
    bool updateMuteType = false,
    bool updateMuteArgs = false,
    bool updateIsPinned = false,
    bool updatePinIndex = false,
    bool updateIsArchived = false,
    bool updateHasUnreadMessage = false,
    bool updateAutoSendReadReceipts = false,
    bool updateAutoSendTypingIndicators = false,
    bool updateCustomAvatarPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
  }) async {
    if (kIsWeb) return this;

    await ChatInterface.saveChat(
      guid: guid,
      chatData: toMap(),
      updateFlags: {
        'updateMuteType': updateMuteType,
        'updateMuteArgs': updateMuteArgs,
        'updateIsPinned': updateIsPinned,
        'updatePinIndex': updatePinIndex,
        'updateIsArchived': updateIsArchived,
        'updateHasUnreadMessage': updateHasUnreadMessage,
        'updateAutoSendReadReceipts': updateAutoSendReadReceipts,
        'updateAutoSendTypingIndicators': updateAutoSendTypingIndicators,
        'updateCustomAvatarPath': updateCustomAvatarPath,
        'updateTextFieldText': updateTextFieldText,
        'updateTextFieldAttachments': updateTextFieldAttachments,
        'updateDisplayName': updateDisplayName,
        'updateDateDeleted': updateDateDeleted,
        'updateLockChatName': updateLockChatName,
        'updateLockChatIcon': updateLockChatIcon,
        'updateLastReadMessageGuid': updateLastReadMessageGuid,
      },
    );

    return this;
  }

  /// Change a chat's display name
  Chat changeName(String? name) {
    if (kIsWeb) {
      displayName = name;
      return this;
    }
    displayName = name;
    save(updateDisplayName: true);
    return this;
  }

  /// Get a chat's title
  String getTitle() {
    if (isNullOrEmpty(displayName)) {
      title = getChatCreatorSubtitle();
    } else {
      title = displayName;
    }
    return title!;
  }

  /// Get a chat's title
  String getChatCreatorSubtitle() {
    // generate names for group chats or DMs
    List<String> titles = participants
        .map((e) => e.displayName.trim().split(isGroup && e.contact != null ? " " : String.fromCharCode(65532)).first)
        .toList();
    if (titles.isEmpty) {
      if (chatIdentifier!.startsWith("urn:biz")) {
        return "Business Chat";
      }
      return chatIdentifier!;
    } else if (titles.length == 1) {
      return titles[0];
    } else if (titles.length <= 4) {
      final _title = titles.join(", ");
      int pos = _title.lastIndexOf(", ");
      if (pos != -1) {
        return "${_title.substring(0, pos)} & ${_title.substring(pos + 2)}";
      } else {
        return _title;
      }
    } else {
      final _title = titles.take(3).join(", ");
      return "$_title & ${titles.length - 3} others";
    }
  }

  /// Return whether or not the notification should be muted
  bool shouldMuteNotification(Message? message) {
    /// Filter unknown senders & sender doesn't have a contact, then don't notify
    if (SettingsSvc.settings.filterUnknownSenders.value && participants.length == 1 && participants.first.contact == null) {
      return true;

      /// Check if global text detection is on and notify accordingly
    } else if (SettingsSvc.settings.globalTextDetection.value.isNotEmpty) {
      List<String> text = SettingsSvc.settings.globalTextDetection.value.split(",");
      for (String s in text) {
        if (message?.text?.toLowerCase().contains(s.toLowerCase()) ?? false) {
          return false;
        }
      }
      return true;

      /// Check if muted
    } else if (muteType == "mute") {
      return true;

      /// Check if the sender is muted
    } else if (muteType == "mute_individuals") {
      List<String> individuals = muteArgs!.split(",");
      return individuals.contains(message?.handle?.address ?? "");

      /// Check if the chat is temporarily muted
    } else if (muteType == "temporary_mute") {
      DateTime time = DateTime.parse(muteArgs!);
      bool shouldMute = DateTime.now().toLocal().difference(time).inSeconds.isNegative;
      if (!shouldMute) {
        toggleMute(false);
      }
      return shouldMute;

      /// Check if the chat has specific text detection and notify accordingly
    } else if (muteType == "text_detection") {
      List<String> text = muteArgs!.split(",");
      for (String s in text) {
        if (message?.text?.toLowerCase().contains(s.toLowerCase()) ?? false) {
          return false;
        }
      }
      return true;
    }

    /// If reaction and notify reactions off, then don't notify, otherwise notify
    return !SettingsSvc.settings.notifyReactions.value &&
        ReactionTypes.toList().contains(message?.associatedMessageType ?? "");
  }

  /// Delete a chat locally. Prefer using softDelete so the chat doesn't come back
  static Future<void> deleteChat(Chat chat) async {
    if (kIsWeb) return;
    // close the convo view page if open and wait for it to be disposed before deleting
    if (cm.activeChat?.chat.guid == chat.guid) {
      NavigationSvc.closeAllConversationView(Get.context!);
      await cm.setAllInactive();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    List<Message> messages = Chat.getMessages(chat);
    await ChatInterface.deleteChat(
      chatId: chat.id!,
      messageIds: messages.map((e) => e.id!).toList(),
    );
  }

  static Future<void> softDelete(Chat chat) async {
    if (kIsWeb) return;
    // close the convo view page if open and wait for it to be disposed before deleting
    if (cm.activeChat?.chat.guid == chat.guid) {
      NavigationSvc.closeAllConversationView(Get.context!);
      await cm.setAllInactive();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await ChatInterface.softDeleteChat(chatData: chat.toMap());
    chat.clearTranscript();
  }

  static Future<void> unDelete(Chat chat) async {
    if (kIsWeb) return;
    await ChatInterface.unDeleteChat(chatData: chat.toMap());
  }

  Chat toggleHasUnread(bool hasUnread,
      {bool force = false, bool clearLocalNotifications = true, bool privateMark = true}) {
    if (kIsDesktop && !hasUnread) {
      NotificationsSvc.clearDesktopNotificationsForChat(guid);
    }

    if (hasUnreadMessage == hasUnread && !force) return this;
    if (!cm.isChatActive(guid) || !hasUnread || force) {
      hasUnreadMessage = hasUnread;
      save(updateHasUnreadMessage: true);
    }
    if (cm.isChatActive(guid) && hasUnread && !force) {
      hasUnread = false;
      clearLocalNotifications = false;
    }

    try {
      if (clearLocalNotifications && !hasUnread) {
        ChatInterface.clearNotificationForChat(
          chatId: id!,
          chatGuid: guid,
        );
      }
      if (privateMark && (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value)) {
        ChatInterface.markChatReadUnread(
          chatGuid: guid,
          markAsRead: !hasUnread,
          shouldMarkOnServer: true,
        );
      }
    } catch (_) {}

    return this;
  }

  Future<Chat> addMessage(Message message,
      {bool changeUnreadStatus = true, bool checkForMessageText = true, bool clearNotificationsIfFromMe = true}) async {
    // If this is a message preview and we don't already have metadata for this, get it
    if (message.fullText.replaceAll("\n", " ").hasUrl &&
        !MetadataHelper.mapIsNotEmpty(message.metadata) &&
        !message.hasApplePayloadData) {
      MetadataHelper.fetchMetadata(message).then((Metadata? meta) async {
        // If the metadata is empty, don't do anything
        if (!MetadataHelper.isNotEmpty(meta)) return;

        // Save the metadata to the object
        message.metadata = meta!.toJson();
      });
    }

    // Save the message using the interface
    Message? latest = latestMessage;
    Message? newMessage;
    bool isNewer = false;

    try {
      final result = await ChatInterface.addMessageToChat(
        messageData: message.toMap(),
        chatData: toMap(),
        latestMessageData: latest.toMap(),
        checkForMessageText: checkForMessageText,
      );

      // Deserialize result
      newMessage = Message.fromMap(result['message'] as Map<String, dynamic>);
      newMessage.id = result['messageId'] as int?;
      isNewer = result['isNewer'] as bool;
    } catch (ex, stacktrace) {
      newMessage = Message.findOne(guid: message.guid);
      if (newMessage == null) {
        Logger
            .error("Failed to add message (GUID: ${message.guid}) to chat (GUID: $guid)", error: ex, trace: stacktrace);
      }
    }

    // Handle post-save operations on main thread
    if (isNewer) {
      _latestMessage = message;
      if (dateDeleted != null) {
        dateDeleted = null;
        await saveAsync(updateDateDeleted: true);
        await ChatsSvc.addChat(this);
      }
      if (isArchived! && !_latestMessage!.isFromMe! && SettingsSvc.settings.unarchiveOnNewMessage.value) {
        toggleArchived(false);
      }
    }

    // Save the chat.
    // This will update the latestMessage info as well as update some
    // other fields that we want to "mimic" from the server
    await saveAsync();

    // If the incoming message was newer than the "last" one, set the unread status accordingly
    if (checkForMessageText && changeUnreadStatus && isNewer) {
      // If the message is from me, mark it unread
      // If the message is not from the same chat as the current chat, mark unread
      if (message.isFromMe! || cm.isChatActive(guid)) {
        // force if the chat is active to ensure private api mark read
        toggleHasUnread(false,
            clearLocalNotifications: clearNotificationsIfFromMe,
            force: cm.isChatActive(guid),
            // only private mark if the chat is active
            privateMark: cm.isChatActive(guid));
      } else if (!cm.isChatActive(guid)) {
        toggleHasUnread(true, privateMark: false);
      }
    }

    // If the message is for adding or removing participants,
    // we need to ensure that all of the chat participants are correct by syncing with the server
    if (message.isParticipantEvent && checkForMessageText) {
      serverSyncParticipants();
    }

    // Return the current chat instance (with updated vals)
    return this;
  }

  void serverSyncParticipants() async {
    // Send message to server to get the participants
    final chat = await cm.fetchChat(guid);
    if (chat != null) {
      chat.save();
    }
  }

  static int? count() {
    return Database.chats.count();
  }

  Future<List<Attachment>> getAttachmentsAsync({bool fetchDeleted = false}) async {
    if (kIsWeb || id == null) return [];

    final stopwatch = Stopwatch()..start();

    /// Query the messages for this chat using ObjectBox's async API
    final messageQuery = (Database.messages.query(fetchDeleted
            ? Message_.dateCreated.notNull().and(Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()))
            : Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull()))
          ..link(Message_.chat, Chat_.id.equals(id!))
          ..order(Message_.dateCreated, flags: Order.descending))
        .build();

    // Execute query in worker isolate
    final messages = await messageQuery.findAsync();
    messageQuery.close();

    if (messages.isEmpty) {
      stopwatch.stop();
      Logger.debug("Fetched 0 messages for chat $guid in ${stopwatch.elapsedMilliseconds} ms");
      return [];
    }

    // Get all message IDs to query attachments
    final messageIds = messages.map((e) => e.id!).toList();

    // Query attachments linked to these messages asynchronously
    final attachmentQuery = (Database.attachments.query(Attachment_.mimeType.notNull())
          ..link(Attachment_.message, Message_.id.oneOf(messageIds)))
        .build();

    final attachments = await attachmentQuery.findAsync();
    attachmentQuery.close();

    // Remove duplicate attachments from the list, just in case
    if (attachments.isNotEmpty) {
      final guids = attachments.map((e) => e.guid).toSet();
      attachments.retainWhere((element) => guids.remove(element.guid));
    }

    stopwatch.stop();
    Logger.debug("Fetched ${attachments.length} attachments for chat $guid in ${stopwatch.elapsedMilliseconds} ms");
    return attachments;
  }

  /// Gets messages synchronously - DO NOT use in performance-sensitive areas,
  /// otherwise prefer [getMessagesAsync]
  static List<Message> getMessages(Chat chat,
      {int offset = 0, int limit = 25, bool includeDeleted = false, bool getDetails = false}) {
    if (kIsWeb || chat.id == null) return [];
    return Database.runInTransaction(TxMode.read, () {
      final query = (Database.messages.query(includeDeleted
              ? Message_.dateCreated.notNull().and(Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()))
              : Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull()))
            ..link(Message_.chat, Chat_.id.equals(chat.id!))
            ..order(Message_.dateCreated, flags: Order.descending))
          .build();
      query
        ..limit = limit
        ..offset = offset;
      final messages = query.find();
      query.close();
      for (int i = 0; i < messages.length; i++) {
        Message message = messages[i];
        if (chat.participants.isNotEmpty && !message.isFromMe! && message.handleId != null && message.handleId != 0) {
          Handle? handle =
              chat.participants.firstWhereOrNull((e) => e.originalROWID == message.handleId) ?? message.getHandle();
          if (handle == null) {
            messages.remove(message);
            i--;
          } else {
            message.handle = handle;
          }
        }
      }
      // fetch attachments and reactions if requested
      if (getDetails) {
        final messageGuids = messages.map((e) => e.guid!).toList();
        final associatedMessagesQuery = (Database.messages.query(Message_.associatedMessageGuid.oneOf(messageGuids))
              ..order(Message_.originalROWID))
            .build();
        List<Message> associatedMessages = associatedMessagesQuery.find();
        associatedMessagesQuery.close();
        associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);
        for (Message m in messages) {
          m.attachments = List<Attachment>.from(m.dbAttachments);
          m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
        }
      }
      return messages;
    });
  }

  /// Fetch messages asynchronously with progressive loading
  /// Returns messages immediately, then loads reactions/attachments in background
  static Future<List<Message>> getMessagesAsync(Chat chat,
      {int offset = 0,
      int limit = 25,
      bool includeDeleted = false,
      int? searchAround,
      Function? onSupplementalDataLoaded}) async {
    if (kIsWeb || chat.id == null) return [];

    final totalStopwatch = Stopwatch()..start();

    // PHASE 1: Quick message query using interface/actions pattern
    final messagesData = await ChatInterface.getMessagesAsync(
      chatId: chat.id!,
      chatGuid: chat.guid,
      participantsData: chat.participants.map((e) => e.toMap()).toList(),
      offset: offset,
      limit: limit,
      includeDeleted: includeDeleted,
      searchAround: searchAround,
    );

    final messages = messagesData.map((e) => Message.fromMap(e)).toList();

    Logger.debug(
        "[getMessagesAsync] Phase 1 - Messages only: ${totalStopwatch.elapsedMilliseconds}ms (${messages.length} messages)");

    if (messages.isEmpty) {
      return messages;
    }

    // PHASE 2: Load supplemental data in background (non-blocking)
    final messageGuids = messages.map((e) => e.guid!).toList();
    final messageIds = messages.map((e) => e.id!).toList();

    // Don't await - let this run in background and call callback when done
    _loadSupplementalDataAsync(messages, messageGuids, messageIds, totalStopwatch, onSupplementalDataLoaded);

    totalStopwatch.stop();
    Logger.debug("[getMessagesAsync] RETURNED (Phase 1 complete): ${totalStopwatch.elapsedMilliseconds}ms");

    // Return messages immediately (reactions/attachments will be added later)
    return messages;
  }

  /// Load reactions and attachments in background and append to messages
  static Future<void> _loadSupplementalDataAsync(
    List<Message> messages,
    List<String> messageGuids,
    List<int> messageIds,
    Stopwatch totalStopwatch,
    Function? onComplete,
  ) async {
    final supplementalStopwatch = Stopwatch()..start();

    try {
      final result = await ChatInterface.loadSupplementalData(
        messageGuids: messageGuids,
        messageIds: messageIds,
      );

      Logger.debug("[getMessagesAsync] Phase 2 - Supplemental query: ${supplementalStopwatch.elapsedMilliseconds}ms");

      // Deserialize on main thread
      var associatedMessages =
          (result['reactions'] as List).map((e) => Message.fromMap(e as Map<String, dynamic>)).toList();
      final allAttachments =
          (result['attachments'] as List).map((e) => Attachment.fromMap(e as Map<String, dynamic>)).toList();

      // Normalize reactions
      associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);

      // Build attachment map
      final attachmentMap = <int, List<Attachment>>{};
      for (final attachment in allAttachments) {
        final messageId = attachment.message.target?.id;
        if (messageId != null) {
          attachmentMap.putIfAbsent(messageId, () => []).add(attachment);
        }
      }

      // Append attachments and reactions to original messages
      for (Message m in associatedMessages) {
        if (m.associatedMessageType == "sticker") {
          m.attachments = attachmentMap[m.id] ?? [];
        }
      }

      for (Message m in messages) {
        m.attachments = attachmentMap[m.id] ?? [];
        m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
      }

      supplementalStopwatch.stop();
      Logger.debug(
          "[getMessagesAsync] Phase 2 - COMPLETE: ${supplementalStopwatch.elapsedMilliseconds}ms (${associatedMessages.length} reactions, ${allAttachments.length} attachments)");

      // Notify caller that supplemental data has been loaded
      if (onComplete != null) {
        onComplete();
      }
    } catch (ex, stacktrace) {
      Logger.error("Failed to load supplemental data for messages", error: ex, trace: stacktrace);
    }
  }

  Chat getParticipants() {
    if (kIsWeb || id == null) return this;
    Database.runInTransaction(TxMode.read, () {
      /// Find the handles themselves
      _participants = List<Handle>.from(handles);
    });

    _deduplicateParticipants();
    return this;
  }

  Future<Chat> getParticipantsAsync() async {
    if (kIsWeb || id == null) return this;

    final participantsData = await ChatInterface.getParticipantsAsync(
      chatId: id!,
      chatGuid: guid,
    );

    _participants = participantsData.map((e) => Handle.fromMap(e)).toList();
    _deduplicateParticipants();
    return this;
  }

  void webSyncParticipants() {}

  void _deduplicateParticipants() {
    if (_participants.isEmpty) return;
    final ids = _participants.map((e) => e.uniqueAddressAndService).toSet();
    _participants.retainWhere((element) => ids.remove(element.uniqueAddressAndService));
  }

  Chat togglePin(bool isPinned) {
    if (id == null) return this;
    this.isPinned = isPinned;
    _pinIndex.value = null;
    save(updateIsPinned: true, updatePinIndex: true);
    ChatsSvc.updateChat(this);
    ChatsSvc.sort();
    return this;
  }

  Chat toggleMute(bool isMuted) {
    if (id == null) return this;
    muteType = isMuted ? "mute" : null;
    muteArgs = null;
    save(updateMuteType: true, updateMuteArgs: true);
    return this;
  }

  Future<Chat> toggleArchived(bool isArchived) async {
    if (id == null) return this;
    isPinned = false;
    this.isArchived = isArchived;
    await saveAsync(updateIsPinned: true, updateIsArchived: true);
    ChatsSvc.updateChat(this);
    ChatsSvc.sort();
    return this;
  }

  Chat toggleAutoRead(bool? autoSendReadReceipts) {
    if (id == null) return this;
    this.autoSendReadReceipts = autoSendReadReceipts;
    save(updateAutoSendReadReceipts: true);
    if (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value) {
      HttpSvc.markChatRead(guid);
    }
    return this;
  }

  Chat toggleAutoType(bool? autoSendTypingIndicators) {
    if (id == null) return this;
    this.autoSendTypingIndicators = autoSendTypingIndicators;
    save(updateAutoSendTypingIndicators: true);
    if (!(autoSendTypingIndicators ?? SettingsSvc.settings.privateSendTypingIndicators.value)) {
      SocketSvc.sendMessage("stopped-typing", {"chatGuid": guid});
    }
    return this;
  }

  /// Finds a chat - only use this method on Flutter Web!!!
  static Future<Chat?> findOneWeb({String? guid, String? chatIdentifier}) async {
    return null;
  }

  /// Finds a chat - DO NOT use this method on Flutter Web!! Prefer [findOneWeb]
  /// instead!!
  static Chat? findOne({String? guid, String? chatIdentifier}) {
    if (guid != null) {
      final query = Database.chats.query(Chat_.guid.equals(guid)).build();
      final result = query.findFirst();
      query.close();
      return result;
    } else if (chatIdentifier != null) {
      final query = Database.chats.query(Chat_.chatIdentifier.equals(chatIdentifier)).build();
      final result = query.findFirst();
      query.close();
      return result;
    }
    return null;
  }

  static Future<List<Chat>> getChatsAsync({int limit = 15, int offset = 0, List<int> ids = const []}) async {
    if (kIsWeb) throw Exception("Use socket to get chats on Web!");

    final result = await ChatInterface.getChatsAsync(
      limit: limit,
      offset: offset,
      ids: ids,
    );

    // Deserialize and generate titles on the main thread
    final chats = result.map((e) => Chat.fromMap(e)).toList();
    
    // Generate titles on the main thread (lightweight operation)
    for (Chat c in chats) {
      c.title = c.getTitle();
    }

    return chats;
  }

  static Future<List<Chat>> syncLatestMessages(List<Chat> chats, bool toggleUnread) async {
    if (kIsWeb) throw Exception("Use socket to sync the last message on Web!");
    if (chats.isEmpty) return chats;

    final inputGuids = chats.map((e) => e.guid).toList();

    final result = await ChatInterface.syncLatestMessages(
      chatGuids: inputGuids,
      toggleUnread: toggleUnread,
    );

    return result.map((e) => Chat.fromMap(e)).toList();
  }

  static Future<List<Chat>> bulkSyncChats(List<Chat> chats) async {
    if (kIsWeb) throw Exception("Web does not support saving chats!");
    if (chats.isEmpty) return [];

    final result = await ChatInterface.bulkSyncChats(
      chatsData: chats.map((e) => e.toMap()).toList(),
    );

    return result.map((e) => Chat.fromMap(e)).toList();
  }

  static Future<List<Message>> bulkSyncMessages(Chat chat, List<Message> messages) async {
    if (kIsWeb) throw Exception("Web does not support saving messages!");
    if (messages.isEmpty) return [];

    final result = await ChatInterface.bulkSyncMessages(
      chatData: chat.toMap(),
      messagesData: messages.map((e) => e.toMap()).toList(),
    );

    return result.map((e) => Message.fromMap(e)).toList();
  }

  void clearTranscript() {
    if (kIsWeb) return;
    Database.runInTransaction(TxMode.write, () {
      final toDelete = List<Message>.from(messages);
      for (Message element in toDelete) {
        element.dateDeleted = DateTime.now().toUtc();
      }
      Database.messages.putMany(toDelete);
    });
  }

  Future<void> clearTranscriptAsync() async {
    if (kIsWeb || id == null) return;

    await ChatInterface.clearTranscriptAsync(
      chatId: id!,
      chatGuid: guid,
    );
  }

  bool get isTextForwarding => guid.startsWith("SMS");

  bool get isSMS => false;

  bool get isIMessage => !isTextForwarding && !isSMS;

  bool get isGroup => participants.length > 1 || style == 43;

  Chat merge(Chat other) {
    id ??= other.id;
    _customAvatarPath.value ??= other._customAvatarPath.value;
    _pinIndex.value ??= other._pinIndex.value;
    autoSendReadReceipts ??= other.autoSendReadReceipts;
    autoSendTypingIndicators ??= other.autoSendTypingIndicators;
    textFieldText ??= other.textFieldText;
    if (textFieldAttachments.isEmpty) {
      textFieldAttachments.addAll(other.textFieldAttachments);
    }
    chatIdentifier ??= other.chatIdentifier;
    displayName ??= other.displayName;
    if (handles.isEmpty) {
      handles.addAll(other.handles);
    }
    hasUnreadMessage ??= other.hasUnreadMessage;
    isArchived ??= other.isArchived;
    isPinned ??= other.isPinned;
    _latestMessage ??= other.latestMessage;
    muteArgs ??= other.muteArgs;
    title ??= other.title;
    dateDeleted ??= other.dateDeleted;
    style ??= other.style;
    return this;
  }

  static int sort(Chat? a, Chat? b) {
    // If they both are pinned & ordered, reflect the order
    if (a!.isPinned! && b!.isPinned! && a.pinIndex != null && b.pinIndex != null) {
      return a.pinIndex!.compareTo(b.pinIndex!);
    }

    // If b is pinned & ordered, but a isn't either pinned or ordered, return accordingly
    if (b!.isPinned! && b.pinIndex != null && (!a.isPinned! || a.pinIndex == null)) return 1;
    // If a is pinned & ordered, but b isn't either pinned or ordered, return accordingly
    if (a.isPinned! && a.pinIndex != null && (!b.isPinned! || b.pinIndex == null)) return -1;

    // Compare when one is pinned and the other isn't
    if (!a.isPinned! && b.isPinned!) return 1;
    if (a.isPinned! && !b.isPinned!) return -1;

    // Compare the last message dates
    return -(a.latestMessage.dateCreated)!.compareTo(b.latestMessage.dateCreated!);
  }

  static Future<void> getIcon(Chat c, {bool force = false}) async {
    if (!force && c.lockChatIcon) return;
    final response = await HttpSvc.getChatIcon(c.guid).catchError((err, stack) async {
      Logger.error("Failed to get chat icon for chat ${c.getTitle()}", error: err, trace: stack);
      return Response(statusCode: 500, requestOptions: RequestOptions(path: ""));
    });
    if (response.statusCode != 200 || isNullOrEmpty(response.data)) {
      if (c.customAvatarPath != null) {
        await File(c.customAvatarPath!).delete(recursive: true);
        c.customAvatarPath = null;
        c.save(updateCustomAvatarPath: true);
      }
    } else {
      Logger.debug("Got chat icon for chat ${c.getTitle()}");
      File file = File(
          "${FilesystemSvc.appDocDir.path}/avatars/${c.guid.characters.where((char) => char.isAlphabetOnly || char.isNumericOnly).join()}/avatar-${response.data.length}.jpg");
      if (!(await file.exists())) {
        await file.create(recursive: true);
      }
      if (c.customAvatarPath != null) {
        await file.delete();
      }
      await file.writeAsBytes(response.data);
      c.customAvatarPath = file.path;
      c.save(updateCustomAvatarPath: true);
    }
  }

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "guid": guid,
        "chatIdentifier": chatIdentifier,
        "isArchived": isArchived!,
        "muteType": muteType,
        "muteArgs": muteArgs,
        "isPinned": isPinned!,
        "displayName": displayName,
        "participants": participants.map((item) => item.toMap()).toList(),
        "hasUnreadMessage": hasUnreadMessage!,
        "_customAvatarPath": _customAvatarPath.value,
        "_pinIndex": _pinIndex.value,
        "autoSendReadReceipts": autoSendReadReceipts,
        "autoSendTypingIndicators": autoSendTypingIndicators,
        "dateDeleted": dateDeleted?.millisecondsSinceEpoch,
        "style": style,
        "lockChatName": lockChatName,
        "lockChatIcon": lockChatIcon,
        "lastReadMessageGuid": lastReadMessageGuid,
      };
}
