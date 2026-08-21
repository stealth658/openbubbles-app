import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:dio/dio.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey, MessageSaveResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:mime_type/mime_type.dart';
// (needed when generating objectbox model code)
// ignore: unnecessary_import
import 'package:objectbox/objectbox.dart';
import 'package:supercharged/supercharged.dart';
import 'package:universal_io/io.dart';

// NOTE: the GetChatAttachments / GetMessages / AddMessages / GetChats AsyncTask
// classes that used to live here were removed upstream -- that work now happens
// in lib/services/backend/actions/*_actions.dart behind the isolate interfaces.
// The two rustpush "zen mode" helpers below are OpenBubbles-only and are kept.

Future<String> getZenKey(String key) async {
  return await MethodChannelSvc.invokeMethod("zen-mode-uuid", { "key": key });
}

Future<api.StatusKitPersonalConfig> configForMask(int mask) async {
  bool isStarredContact = ((mask >> 0) & 1) == 1;
  bool isPriority = ((mask >> 1) & 1) == 1;
  

  return api.StatusKitPersonalConfig(allowedModes: [
    if (isStarredContact)
    await getZenKey("starred"),
    if (isPriority)
    await getZenKey("priority"),
    if (isStarredContact || isPriority)
    await getZenKey("starred_priority"),
  ]);
}

/// OpenBubbles-only: SharedPreferences key holding the CloudKit record ids of
/// chats deleted locally but not yet deleted from iCloud by rustpush.
const String kChatDeletionIdsKey = "chatDeletionIds-1";

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
  /// OpenBubbles-only: cached [getTitle] result.
  String? title;

  /// OpenBubbles-only: the conversation name rustpush reports over APNs.
  String? apnTitle;

  String get properTitle {
    if (SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value) {
      return getTitle();
    }
    title ??= getTitle();
    return title!;
  }

  String? displayName;
  bool? autoSendReadReceipts;
  bool? autoSendTypingIndicators;
  String? textFieldText;
  String? textFieldAnnotations;
  List<String> textFieldAttachments = [];

  /// ObjectBox ToOne relation to the latest message for O(1) lookup.
  /// Keep [dbOnlyLatestMessageDate] in sync via [setLatestMessage].
  final dbLatestMessage = ToOne<Message>();

  @Property(uid: 526293286661780207)
  DateTime? dbOnlyLatestMessageDate;

  /// Update the latest-message relation and its sort-key in one step.
  /// Persists both fields to the DB asynchronously (fire-and-forget).
  void setLatestMessage(Message m) {
    dbLatestMessage.target = m;
    dbOnlyLatestMessageDate = m.dateCreated;
    unawaited(saveAsync(updateLatestMessage: true));
  }

  DateTime? dateDeleted;
  int? style;
  bool lockChatName;
  bool lockChatIcon;
  String? lastReadMessageGuid;
  String? customThemeLight;
  String? customThemeDark;

  /// [ChatWallpaperType.name] - "none" (default/absent), "image", or "dynamic".
  /// Read via `ChatWallpaperType.fromName(chat.wallpaperType)`.
  @Property(uid: 699362128358203439)
  String? wallpaperType;

  /// [DynamicWallpaperDefinition.id] of the selected dynamic wallpaper, when
  /// [wallpaperType] is "dynamic". Null otherwise.
  @Property(uid: 3728602269935984680)
  String? dynamicWallpaperId;

  /// JSON-encoded config map for [dynamicWallpaperId], via [WallpaperConfigCodec].
  @Property(uid: 738307263391205523)
  String? dynamicWallpaperConfig;

  // ---- OpenBubbles (rustpush / iCloud sync) columns ----
  int? groupVersion;

  Uint8List? cloudData;
  String? ckRecordId;
  String? cloudGuid;
  bool ckSyncState = false;
  String? photoAttachmentGuid;

  Message get sendLastMessage {
    var messages = Chat.getMessages(this, limit: 10, getDetails: true);
    return messages.firstWhereOrNull((msg) =>
            msg.stagingGuid != null ||
            (msg.guid != null && !msg.guid!.contains("temp") && !msg.guid!.contains("error"))) ??
        Message(
          dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
          guid: guid,
        );
  }

  final RxnString _customAvatarPath = RxnString();
  String? get customAvatarPath => _customAvatarPath.value;
  set customAvatarPath(String? s) => _customAvatarPath.value = s;

  final RxnString _customBackgroundPath = RxnString();
  String? get customBackgroundPath => _customBackgroundPath.value;
  set customBackgroundPath(String? s) => _customBackgroundPath.value = s;

  final RxnInt _pinIndex = RxnInt();
  int? get pinIndex => _pinIndex.value;
  set pinIndex(int? i) => _pinIndex.value = i;

  @Transient()
  RxDouble sendProgress = 0.0.obs;

  void handlesChanged() {
    var cachedChat = cvc(this).chat;
    cachedChat.handles = handles; // someone can't keep their objects in sync...
    cachedChat.participants = [];
  }

  List<String> guidRefs = [];
  var handles = ToMany<Handle>();

  String? usingHandle;
  bool isRpSms;
  int? telephonyId;
  bool? shareZenMode;
  bool notifsSilenced = false;
  int? zenModeIsShared;
  DateTime? dateNotifiedAnyways;
  bool? senderIsKnown;
  // true means this is a routing stub; we only hold SMS bridging information, not messages
  bool isRoutingStub = false;

  String? transcriptPosterPath;
  int transcriptBackgroundVersion = 1;

  // Do not use this field directly, use the `participants` getter (or the
  // `handles` ToMany relation) instead. This backing list is only ever
  // populated explicitly, for serialization/deserialization purposes.
  @Transient()
  List<Handle> _participants = [];

  /// Upstream replaced the fork's lazy `_participants` getter with a plain
  /// transient list that nothing populates when a chat is read back out of the
  /// database. The fork reads this on every rustpush send, read receipt,
  /// rename and typing indicator, so fall back to the `handles` relation
  /// whenever the transient list has not been filled in explicitly.
  List<Handle> get participants {
    if (_participants.isEmpty) {
      final fromRelation = _deduplicateHandles(handles.toList());
      // Don't cache an empty result - `handles` may simply not be loaded yet.
      if (fromRelation.isNotEmpty) _participants = fromRelation;
    }
    return _participants;
  }

  /// Kept so `createChat` / `Chat.fromMap` / `Chat.save()` can still push an
  /// explicit participant list onto a (possibly refetched) chat object.
  set participants(List<Handle> value) => _participants = _deduplicateHandles(value);

  static List<Handle> _deduplicateHandles(List<Handle> input) {
    final seen = <String>{};
    return List<Handle>.from(input).where((e) => seen.add(e.uniqueAddressAndService)).toList();
  }

  @Backlink('chat')
  final messages = ToMany<Message>();

  @Backlink('chats')
  final customGroups = ToMany<CustomGroup>();

  @Transient()
  String? _fakeName;

  @Transient()
  String get fakeName {
    if (_fakeName != null) return _fakeName!;
    final color = faker.color.color();
    final animal = faker.animal.name();
    _fakeName = "${color.capitalize} ${animal.capitalize}";
    return _fakeName!;
  }

  Chat({
    this.id,
    required this.guid,
    this.chatIdentifier, // how is this different from GUID?
    this.isArchived = false,
    this.isPinned = false,
    this.muteType,
    this.muteArgs,
    this.hasUnreadMessage = false,
    this.displayName,
    String? customAvatar,
    String? customBackground,
    int? pinnedIndex,
    Message? latestMessage,
    List<Handle> participants = const [],
    this.autoSendReadReceipts,
    this.autoSendTypingIndicators,
    this.textFieldText,
    this.textFieldAnnotations,
    this.textFieldAttachments = const [],
    this.dateDeleted,
    this.style,
    this.lockChatName = false,
    this.lockChatIcon = false,
    this.lastReadMessageGuid,
    this.customThemeLight,
    this.customThemeDark,
    this.wallpaperType,
    this.dynamicWallpaperId,
    this.dynamicWallpaperConfig,
    this.usingHandle,
    this.isRpSms = false,
    this.telephonyId,
    this.shareZenMode,
    this.notifsSilenced = false,
    this.dateNotifiedAnyways,
    this.zenModeIsShared,
    this.senderIsKnown = true,
    this.isRoutingStub = false,
    List<String>? guidRefs,
  }) : guidRefs = guidRefs ?? [guid] {
    this.participants = participants;
    customAvatarPath = customAvatar;
    customBackgroundPath = customBackground;
    pinIndex = pinnedIndex;
    if (textFieldAttachments.isEmpty) textFieldAttachments = [];
    if (latestMessage != null) dbOnlyLatestMessageDate ??= latestMessage.dateCreated;
  }

  factory Chat.fromMap(Map<String, dynamic> json) {
    final message = json['lastMessage'] != null ? Message.fromMap(json['lastMessage']!.cast<String, Object>()) : null;
    return Chat(
      id: json["ROWID"] ?? json["id"],
      guid: json["guid"],
      chatIdentifier: json["chatIdentifier"],
      participants:
          (json['participants'] as List? ?? []).map((e) => Handle.fromMap(e!.cast<String, Object>())).toList(),
      isArchived: json['isArchived'] ?? false,
      muteType: json["muteType"],
      muteArgs: json["muteArgs"],
      isPinned: json["isPinned"] ?? false,
      hasUnreadMessage: json["hasUnreadMessage"] ?? false,
      latestMessage: message,
      displayName: json["displayName"],
      customAvatar: json['_customAvatarPath'],
      customBackground: json['_customBackgroundPath'],
      pinnedIndex: json['_pinIndex'],
      autoSendReadReceipts: json["autoSendReadReceipts"],
      autoSendTypingIndicators: json["autoSendTypingIndicators"],
      dateDeleted: parseDate(json["dateDeleted"]),
      style: json["style"],
      lockChatName: json["lockChatName"] ?? false,
      lockChatIcon: json["lockChatIcon"] ?? false,
      lastReadMessageGuid: json["lastReadMessageGuid"],
      customThemeLight: json["customThemeLight"],
      customThemeDark: json["customThemeDark"],
      wallpaperType: json["wallpaperType"],
      dynamicWallpaperId: json["dynamicWallpaperId"],
      dynamicWallpaperConfig: json["dynamicWallpaperConfig"],
      textFieldText: json["textFieldText"],
      textFieldAttachments: (json["textFieldAttachments"] as List?)?.cast<String>() ?? const [],
      usingHandle: json["usingHandle"],
      isRpSms: json["isRpSms"] ?? false,
      guidRefs: json["guidRefs"]?.cast<String>() ?? [],
      telephonyId: json["telephonyId"],
      shareZenMode: json["shareZenMode"],
      notifsSilenced: json["notifsSilenced"] ?? false,
      zenModeIsShared: json["zenModeIsShared"],
      dateNotifiedAnyways: parseDate(json["dateNotifiedAnyways"]),
      isRoutingStub: json["isRoutingStub"] ?? false,
    );
  }

  Future<String> ensureHandle() async {
    if (usingHandle != null && isRpSms) {
      var acceptableHandles = [];
      if (isRoutingStub) {
        acceptableHandles = await api.getMyPhoneHandles(state: pushService.state!.client);
      } else {
        acceptableHandles = SettingsSvc.settings.smsForwardingTargets.keys.toList();
      }
      if (!acceptableHandles.contains(usingHandle)) {
        usingHandle = null;
      }
    }
    if (usingHandle == null) {
      if (isRpSms) {
        if (isRoutingStub) {
          usingHandle = (await api.getMyPhoneHandles(state: pushService.state!.client))[0];
        } else {
          usingHandle = SettingsSvc.settings.smsForwardingTargets.keys.firstOrNull!;
        }
        save(updateUsingHandle: true);
      } else {
        usingHandle = await (backend as RustPushBackend).getDefaultHandle();
        save(updateUsingHandle: true);
      }
    }
    return usingHandle!;
  }

  // return true if we should route this conversation as a router
  Future<bool> shouldRoute() async {
    var handles = await api.getMyPhoneHandles(state: pushService.state!.client);
    return handles.contains(await ensureHandle());
  }

  void removeProfilePhoto() {
    try {
      File file = File(customAvatarPath!);
      file.delete();
    } catch (_) {}
    customAvatarPath = null;
  }

  /// Save a chat to the DB, synchronously, on the calling isolate.
  ///
  /// OpenBubbles keeps this alongside upstream's [saveAsync]: a lot of fork code
  /// (rustpush service, SMS routing, zen mode, iCloud sync) needs a chat row
  /// written and its `id` available immediately, and it has to persist the
  /// rustpush-only columns that `ChatInterface.saveChat` knows nothing about.
  ///
  /// Prefer [saveAsync] for anything that only touches upstream fields.
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
    bool updateCustomBackgroundPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAnnotations = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
    bool updateLatestMessage = false,
    bool updateCustomThemes = false,
    bool updateWallpaperSettings = false,
    bool updateGroupVersion = false,
    bool updateUsingHandle = false,
    bool updateIsSms = false,
    bool updateAPNTitle = false,
    bool updateGuidRefs = false,
    bool updateTelephonyId = false,
    bool updateNotifsSilenced = false,
    bool updateZenModeIsShared = false,
    bool updateShareZenMode = false,
    bool updateDateNotifiedAnyways = false,
    bool updateSenderIsKnown = false,
    bool updateTranscriptPosterPath = false,
    bool updateTranscriptBackgroundVersion = false,
    bool updateCkRecordId = false,
    bool updateCkSyncState = false,
    bool updateAttachmentGuid = false,
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
      cloudData = existing?.cloudData ?? cloudData;
      cloudGuid = existing?.cloudGuid ?? cloudGuid;
      if (!updateCkRecordId) {
        ckRecordId = existing?.ckRecordId ?? ckRecordId;
      }
      if (!updateCkSyncState) {
        ckSyncState = existing?.ckSyncState ?? ckSyncState;
      }
      if (!updateAttachmentGuid) {
        photoAttachmentGuid = existing?.photoAttachmentGuid ?? photoAttachmentGuid;
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
      if (!updateTextFieldAnnotations) {
        textFieldAnnotations = existing?.textFieldAnnotations ?? textFieldAnnotations;
      }
      if (!updateAPNTitle) {
        apnTitle = existing?.apnTitle ?? apnTitle;
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
      if (!updateGroupVersion) {
        groupVersion = existing?.groupVersion ?? groupVersion;
      }
      if (!updateUsingHandle) {
        usingHandle = existing?.usingHandle ?? usingHandle;
      }
      if (!updateIsSms) {
        isRpSms = existing?.isRpSms ?? isRpSms;
      }
      if (!updateGuidRefs) {
        guidRefs = existing?.guidRefs ?? guidRefs;
      }
      if (!updateTelephonyId) {
        telephonyId = existing?.telephonyId ?? telephonyId;
      }
      if (!updateNotifsSilenced) {
        notifsSilenced = existing?.notifsSilenced ?? notifsSilenced;
      }
      if (!updateZenModeIsShared) {
        zenModeIsShared = existing?.zenModeIsShared ?? zenModeIsShared;
      }
      if (!updateShareZenMode) {
        shareZenMode = existing?.shareZenMode ?? shareZenMode;
      }
      if (!updateDateNotifiedAnyways) {
        dateNotifiedAnyways = existing?.dateNotifiedAnyways ?? dateNotifiedAnyways;
      }
      if (!updateSenderIsKnown) {
        senderIsKnown = existing?.senderIsKnown ?? senderIsKnown;
      }
      if (!updateTranscriptPosterPath) {
        transcriptPosterPath = existing?.transcriptPosterPath ?? transcriptPosterPath;
      }
      if (!updateTranscriptBackgroundVersion) {
        transcriptBackgroundVersion = existing?.transcriptBackgroundVersion ?? transcriptBackgroundVersion;
      }
      if (!updateCustomBackgroundPath) {
        customBackgroundPath = existing?.customBackgroundPath ?? customBackgroundPath;
      }
      if (!updateCustomThemes) {
        customThemeLight = existing?.customThemeLight ?? customThemeLight;
        customThemeDark = existing?.customThemeDark ?? customThemeDark;
      }
      if (!updateWallpaperSettings) {
        wallpaperType = existing?.wallpaperType ?? wallpaperType;
        dynamicWallpaperId = existing?.dynamicWallpaperId ?? dynamicWallpaperId;
        dynamicWallpaperConfig = existing?.dynamicWallpaperConfig ?? dynamicWallpaperConfig;
      }
      if (!updateLatestMessage) {
        if (!dbLatestMessage.hasValue && (existing?.dbLatestMessage.hasValue ?? false)) {
          dbLatestMessage.targetId = existing!.dbLatestMessage.targetId;
        }
        dbOnlyLatestMessageDate = existing?.dbOnlyLatestMessageDate ?? dbOnlyLatestMessageDate;
      }
      dbOnlyLatestMessageDate ??= dbLatestMessage.target?.dateCreated;

      /// Save the chat and add the participants
      for (int i = 0; i < participants.length; i++) {
        participants[i] = participants[i].save();
      }
      try {
        id = Database.chats.put(this);
        // make sure to add participant relation if its a new chat
        if (existing == null && participants.isNotEmpty) {
          final toSave = Database.chats.get(id!);
          toSave!.handles.clear();
          toSave.handles.addAll(participants);
          toSave.handles.applyToDb();
        } else if (existing == null && participants.isEmpty) {
          unawaited(ChatsSvc.fetchChat(guid));
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
    bool updateCustomBackgroundPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAnnotations = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
    bool updateLatestMessage = false,
    bool updateCustomThemes = false,
    bool updateWallpaperSettings = false,
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
        'updateCustomBackgroundPath': updateCustomBackgroundPath,
        'updateTextFieldText': updateTextFieldText,
        'updateTextFieldAttachments': updateTextFieldAttachments,
        'updateDisplayName': updateDisplayName,
        'updateDateDeleted': updateDateDeleted,
        'updateLockChatName': updateLockChatName,
        'updateLockChatIcon': updateLockChatIcon,
        'updateLastReadMessageGuid': updateLastReadMessageGuid,
        'updateLatestMessage': updateLatestMessage,
        'updateCustomThemes': updateCustomThemes,
        'updateWallpaperSettings': updateWallpaperSettings,
      },
    );

    return this;
  }

  Future<int> getPersonalConfig() async {
    if (participants.length > 1 || participants.isEmpty || !Platform.isAndroid) return 0;

    // Pre-merge this read `participants.first.contact!.id` off the old Contact
    // model. ContactV2 stores the address-book id as `nativeContactId`.
    final nativeContactId = participants.first.contactsV2.firstWhereOrNull((c) => c.isNative)?.nativeContactId;
    if (nativeContactId == null) return 0;

    bool isStarredContact = await MethodChannelSvc.invokeMethod("is-conversation-exempt", {
      "mode": "star",
      "contactId": int.tryParse(nativeContactId) ?? 0,
    });

    bool isPriority = await MethodChannelSvc.invokeMethod("is-conversation-exempt", {
      "mode": "priority",
      "guid": guid
    });

    int configMask = 
      ((isStarredContact ? 1 : 0) << 0) |
      ((isPriority ? 1 : 0) << 1);

    return configMask;
  }

  void fixZenModeShared() async {
    if (!SettingsSvc.settings.enableShareZen.value) return;
    // `contact?.isShared == false` on the old Contact model meant "this is a
    // real address-book contact, not an Apple contact-sharing suggestion".
    // ContactV2's equivalent is `isNative`.
    bool wantsZenMode =
        (shareZenMode ?? true) && (participants.firstOrNull?.contactsV2.any((c) => c.isNative) ?? false);
    var config = wantsZenMode ? await getPersonalConfig() : null;
    if (config == zenModeIsShared) return;
    var statuskit = pushService.state?.icloudServices?.statuskitClient;
    if (statuskit == null) return;

    if (wantsZenMode) {
      await api.inviteToChannel(status: statuskit, handle: await ensureHandle(), to: {
        getRustHandlesExcludingMine()[0]: await configForMask(config!)
      });
      zenModeIsShared = config;
      save(updateZenModeIsShared: true);
    } else {
      // okay, sooo
      // get everyone who *is* allowed to have my status updates
      final query = Database.chats.query(Chat_.zenModeIsShared.notNull().and(Chat_.dbOnlyLatestMessageDate.greaterThanDate(DateTime.now().subtract(const Duration(days: 7))))).build();
      final results = query.find();
      query.close();
      
      Map<String, Map<String, api.StatusKitPersonalConfig>> sendMap = {};
      for (var result in results) {
        if (result.guid == guid) continue; // no longer share us
        var handle = await result.ensureHandle();
        sendMap.putIfAbsent(handle, () => {});
        sendMap[handle]![result.getRustHandlesExcludingMine()[0]] = await configForMask(result.zenModeIsShared!);
      }
      
      await api.resetChannelKeys(status: statuskit);
      for (var handle in sendMap.entries) {
        await api.inviteToChannel(status: statuskit, handle: handle.key, to: handle.value);
      }
      zenModeIsShared = null;
      save(updateZenModeIsShared: true);

      // these people sadly fall off
      final o = Database.chats.query(Chat_.zenModeIsShared.notNull().and(Chat_.dbOnlyLatestMessageDate.lessThanDate(DateTime.now().subtract(const Duration(days: 7))))).build();
      final older = o.find();
      o.close();
      for (var item in older) {
        item.zenModeIsShared = null;
      }
      Database.chats.putMany(older);
    }
  }

  /// Upstream moved the Attachment DB writes onto the isolate (`deleteAsync` /
  /// `saveAsync`), so this is async now — callers should await it before
  /// persisting the chat row.
  Future<void> updateAttachmentGuid(String guid) async {
    if (customAvatarPath == null) {
      if (photoAttachmentGuid != null) {
        await Attachment.deleteAsync(photoAttachmentGuid!);
      }
      photoAttachmentGuid = null;
    } else {
      if (photoAttachmentGuid != null) {
        await Attachment.deleteAsync(photoAttachmentGuid!);
      }
      photoAttachmentGuid = "${guid}_0";
      var data = Attachment(
        guid: photoAttachmentGuid,
        isOutgoing: true,
        transferName: "GroupPhotoImage",
        totalBytes: File(customAvatarPath!).lengthSync(),
        metadata: {},
      );
      final directory = Directory(data.directory);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      File(customAvatarPath!).copySync(data.path);
      await data.saveAsync(null);
    }
  }

  static Future<Chat> findFromCloud(api.CloudChat c) async {
    var chat = Chat.findByRustGuid(c.groupId);
    if (chat != null) return chat;

    final query2= Database.chats.query(Chat_.chatIdentifier.equals(c.chatIdentifier)).build();
    final result2 = query2.findFirst();
    query2.close();
    if (result2 != null) return result2;


    var cond = Chat_.isRoutingStub.equals(false);
    if (c.displayName != null) {
      cond = cond.and(Chat_.apnTitle.equals(c.displayName!));
    }
    final query = (Database.chats.query(cond)
          ..linkMany(Chat_.handles, Handle_.address.oneOf(c.participants.map((e) => e.uri).toList())))
            .build();
    final results = query.find();
    query.close();

    var result = results.firstWhereOrNull((element) {
      var participantsCopy = c.participants.map((e) => e.uri).toList();
      for (var handle in element.handles) {
        var included = participantsCopy.contains(handle.address);
        if (!included) {
          return false;
        }
        participantsCopy.remove(handle.address);
      }
      return participantsCopy.isEmpty;
    });

    if (result != null) return result;

    chat = await backend.createChat(c.participants.map((p) => p.uri).toList(), null, c.serviceName, existingGuid: c.groupId);
    chat.senderIsKnown = true;
    chat.save(updateSenderIsKnown: true);
    return chat;
  }

  Future<api.CloudChat> toCloud() async {
    api.CloudChat existing;
    if (cloudData != null) {
      existing = api.restoreCloudChat(data: cloudData!);
    } else {
      chatIdentifier = participants.length == 1 ? participants[0].address : "chat${(Random().nextInt(pow(2, 32).toInt()) << 32) | Random().nextInt(pow(2, 32).toInt())}";
      cloudGuid ??= guid;
      existing = api.CloudChat(
        style: isGroup ? 43 : 45, 
        isFiltered: 0, 
        successfulQuery: 1, 
        state: 3, // seems to be a constant 
        chatIdentifier: chatIdentifier!, 
        groupId: cloudGuid!, 
        serviceName: "iMessage", 
        originalGroupId: cloudGuid!, 
        properties: api.CloudProp(
          numberOfTimesRespondedtoThread: 3, // always 3?
          shouldForceToSms: false,
          legacyGroupIdentifiers: [],
          messageHandshakeState: 1,
        ),
        participants: participants.map((p) => api.CloudParticipant(uri: p.address)).toList(), 
        prop001: const api.CloudProp001(syndicationType: 0), 
        lastReadMessageTimestamp: dbOnlyLatestMessageDate == null ? 0 : RustPushBBUtils.nsSinceAppleEpoch(dbOnlyLatestMessageDate!), 
        lastAddressedHandle: (await ensureHandle()).replaceFirst("mailto:", "").replaceFirst("tel:", ""), 
        guid: "iMessage;${isGroup ? '+' : '-'};$chatIdentifier",
        displayName: displayName,
        proto001: api.encodeChatproto(chat: const api.ChatProto(unk1: 0)),
      );
    }
    existing.style = isGroup ? 43 : 45;
    existing.chatIdentifier = chatIdentifier!;
    existing.participants = participants.map((p) => api.CloudParticipant(uri: p.address)).toList();
    existing.lastReadMessageTimestamp = dbOnlyLatestMessageDate == null ? 0 : RustPushBBUtils.nsSinceAppleEpoch(dbOnlyLatestMessageDate!);
    existing.lastAddressedHandle = (await ensureHandle()).replaceFirst("mailto:", "").replaceFirst("tel:", "");
    existing.displayName = displayName;
    if (existing.properties != null) {
      existing.properties!.pv = groupVersion ?? 1;
      // existing.properties!.gpufc = groupVersion ?? 1;
      existing.properties!.lastSeenMessageGuid = lastReadMessageGuid;
      existing.properties!.lastModificationDate = api.dateNow();
      existing.properties!.groupPhotoGuid = photoAttachmentGuid != null ? unconvertAttachmentGuid(photoAttachmentGuid!) : null;
    }
    if (customAvatarPath == null) {
      existing.groupPhoto = null;
      existing.groupPhotoGuid = null;
    } else {
      existing.groupPhotoGuid = photoAttachmentGuid != null ? unconvertAttachmentGuid(photoAttachmentGuid!) : null;
    }
    return existing;
  }

  String unconvertAttachmentGuid(String guid) {
    var items = guid.split("_");
    if (items.length == 1) return guid;
    return "at_${items[1]}_${items[0]}";
  }

  bool applyFromCloud(api.CloudChat c, String record) {
    chatIdentifier = c.chatIdentifier;
    ckRecordId = record;
    cloudGuid = c.groupId;
    ckSyncState = c.properties?.pv == (groupVersion ?? 1);
    if (c.properties?.pv == null || c.properties!.pv! <= (groupVersion ?? 1)) {
      Database.chats.put(this);
      return false;
    }
    Logger.info("Syncing new chat");
    style = c.style;
    // don't copy groupid
    lastReadMessageGuid = c.properties?.lastSeenMessageGuid;
    groupVersion = c.properties?.pv;
    // techincally uri doesn't have mailto: or tel: prefix, but that's fine
    handles.clear();
    handles.addAll(c.participants.map((i) => RustPushBBUtils.rustHandleToBB(i.uri)));
    handles.applyToDb();
    
    usingHandle = c.lastAddressedHandle.isEmail ? "mailto:${c.lastAddressedHandle}" : "tel:${c.lastAddressedHandle}";
    displayName = c.displayName;
    dbOnlyLatestMessageDate = RustPushBBUtils.fromNsSinceAppleEpoch(c.lastReadMessageTimestamp);
    cloudData = api.saveCloudChat(value: c);
    ckSyncState = true;

    if (c.groupPhoto != null) {
      var path = getIconPath(0);
      customAvatarPath = path;
    } else if (customAvatarPath != null) {
      File(customAvatarPath!).deleteSync();
      customAvatarPath = null;
    }

    Database.chats.put(this);
    return true;
  }

  static Future<Chat> getChatForTel(int tid, List<String> participants) async {
    final query3 = Database.chats.query(Chat_.telephonyId.equals(tid).and(Chat_.dateDeleted.isNull()).and(Chat_.isRoutingStub.equals(true))).build();
    final result4 = query3.findFirst();
    query3.close();
    if (result4 != null) return result4;

    final query = (Database.chats.query(Chat_.dateDeleted.isNull().and(Chat_.isRpSms.equals(true)).and(Chat_.isRoutingStub.equals(true)))
          ..linkMany(Chat_.handles, Handle_.address.oneOf(participants)))
            .build();
    final results = query.find();
    query.close();

    var result = results.firstWhereOrNull((element) {
      var participantsCopy = [...participants];
      for (var handle in element.handles) {
        var included = participantsCopy.contains(handle.address);
        if (!included) {
          return false;
        }
        participantsCopy.remove(handle.address);
      }
      return participantsCopy.isEmpty;
    });
    if (result == null) {
      result = await backend.createChat(participants, null, "SMS");
      result.isRoutingStub = true;
      ChatsSvc.updateChat(result);
    }
    result.telephonyId = tid;
    result.save(updateTelephonyId: true);
    return result;
  }

  Future<void> deliverSMS(String sender, bool fromMe, List<Map<String, dynamic>> parts) async {
    if (!SettingsSvc.settings.isSmsRouter.value) {
      return; // don't deliver if not enabled :)
    }
    if (sender.isEmail) return; // no one uses this feature anyway, and can't debug it due to TMO's MXRT AUP

    if (fromMe && "tel:$sender" != usingHandle) {
      Logger.info("Chat delivering sms, handle $usingHandle not sms handle $sender");
      usingHandle = "tel:$sender";
      save(updateUsingHandle: true);
    }

    var handle = Handle.findOne(addressAndService: HandleLookupKey(sender, "iMessage"));
    if (handle == null) {
      handle = Handle(
        address: sender
      );
      handle.save();
    }
    if (handle.originalROWID == null) {
      handle.originalROWID = handle.id!;
      handle.save();
    }
    for (var part in parts) {
      var partContent = part["body"] is Uint8List ? part["body"] as Uint8List : Uint8List.fromList(part["body"].cast<int>().toList());
      // smil is for unnessesary
      if (part["contentType"] == "application/smil") continue;
      if (part["contentType"] == "text/plain") {
        var bodyString = utf8.decode(partContent);
        if (bodyString.trim() == "") continue;
        final _message = Message(
          text: bodyString,
          threadOriginatorPart: "0:0:0",
          dateCreated: DateTime.now(),
          hasAttachments: false,
          isFromMe: fromMe,
          guid: part["id"] as String,
          handleId: 0,
          handle: handle,
          hasDdResults: true,
          hasBeenForwarded: true,
          attributedBody: [AttributedBody(string: bodyString, runs: [Run(
            range: [0, bodyString.length],
            attributes: Attributes(
              messagePart: 0,
            )
          )])],
          temp: true,
        );
        await backend.sendMessage(this, _message);
        if (fromMe) {
          await (backend as RustPushBackend).confirmSmsSent(_message, this, true);
        }
      } else {
        var myUuid = "${part["id"]}_0";
        String data = await rootBundle.loadString("assets/rustpush/uti-map.json");
        final utiMap = jsonDecode(data);

      
        final _message = Message(
          text: " ",
          threadOriginatorPart: "0:0:0",
          dateCreated: DateTime.now(),
          hasAttachments: true,
          isFromMe: fromMe,
          guid: part["id"] as String,
          handleId: 0,
          handle: handle,
          hasDdResults: true,
          hasBeenForwarded: true,
          attributedBody: [AttributedBody(string: " ", runs: [Run(
            range: [0, 1],
            attributes: Attributes(
              attachmentGuid: myUuid,
              messagePart: 0
            )
          )])],
          temp: true,
        );
        // Upstream dropped the `attachments` constructor argument in favour of
        // the `dbAttachments` backlink; the fork's transient setter is the
        // equivalent write path.
        _message.attachments = [
          Attachment(
            guid: myUuid,
            uti: utiMap[part["contentType"] as String] ?? "public.data",
            mimeType: part["contentType"] as String,
            isOutgoing: false,
            bytes: partContent,
            totalBytes: partContent.length,
            transferName: "${part["id"]}.${extensionFromMime(part["contentType"] as String) ?? "bin"}"
          )
        ];
        await _message.attachments.first!.writeToDisk();
        await (backend as RustPushBackend).forwardMMSAttachment(this, _message, _message.attachments.first!);
        File(_message.attachments.first!.path).deleteSync();
        if (fromMe) {
          await (backend as RustPushBackend).confirmSmsSent(_message, this, true);
        }
      }
    }
  }

  List<String> getRustHandlesExcludingMine() {
    return participants.map((e) {
      if (e.address.isEmail) {
        return "mailto:${e.address}";
      } else {
        return "tel:${e.address}";
      }
    }).toList();
  }
  
  Future<api.ConversationData> getConversationData() async {
    var handles = getRustHandlesExcludingMine();
    handles.add(await ensureHandle());
    return api.ConversationData(participants: handles, cvName: apnTitle, senderGuid: guid, afterGuid: sendLastMessage.stagingGuid ?? sendLastMessage.guid);
  }

  /// Change a chat's display name
  Future<Chat> changeNameAsync(String? name) async {
    if (kIsWeb) {
      displayName = name;
      return this;
    }
    displayName = name;
    await saveAsync(updateDisplayName: true);
    return this;
  }

  /// Get a chat's title
  String getTitle() => isNullOrEmpty(displayName) ? getChatCreatorSubtitle() : displayName!;

  /// Get a chat's title
  String getChatCreatorSubtitle() {
    final count = handles.length;
    if (count == 0) {
      if (chatIdentifier == null) return "Unnamed chat";
      if (chatIdentifier!.startsWith("urn:biz")) {
        return "Business Chat";
      }
      return chatIdentifier!;
    } else if (count == 1) {
      return handles.first.displayName;
    }

    if (count <= 4) {
      final buffer = StringBuffer();
      for (int i = 0; i < count; i++) {
        if (i > 0) buffer.write(i == count - 1 ? ' & ' : ', ');
        buffer.write(handles[i].shortName);
      }
      return buffer.toString();
    } else {
      final buffer = StringBuffer();
      for (int i = 0; i < 3; i++) {
        if (i > 0) buffer.write(', ');
        buffer.write(handles[i].shortName);
      }
      buffer.write(' & ${count - 3} others');
      return buffer.toString();
    }
  }

  /// Return whether or not the notification should be muted
  bool shouldMuteNotification(Message? message) {
    /// Filter unknown senders & sender doesn't have a contact, then don't notify
    if (SettingsSvc.settings.filterUnknownSenders.value && handles.length == 1 && handles.first.contactsV2.isEmpty) {
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
      return individuals.contains(message?.handleRelation.target?.address ?? "");

      /// Check if the chat is temporarily muted
    } else if (muteType == "temporary_mute") {
      DateTime time = DateTime.parse(muteArgs!);
      bool shouldMute = DateTime.now().toLocal().difference(time).inSeconds.isNegative;
      if (!shouldMute) {
        toggleMuteAsync(false);
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

  /// Delete a chat locally. Prefer using [softDelete] so the chat doesn't come back.
  static Future<void> deleteChat(Chat chat) async {
    if (kIsWeb) return;

    // OpenBubbles-only: rustpush deletes the chat from iCloud on the next sync
    // pass; record the CloudKit id before the row goes away.
    if (chat.ckRecordId != null && !pushService.syncStopDelete) {
      try {
        // ignore: deprecated_member_use
        final prefs = PrefsSvc.i;
        final list = List<String>.from(prefs.getStringList(kChatDeletionIdsKey) ?? const <String>[]);
        list.add(chat.ckRecordId!);
        await prefs.setStringList(kChatDeletionIdsKey, list);
      } catch (_) {}
    }

    // OpenBubbles-only: also remove the attachment files from disk.
    final attachments = await chat.getAttachmentsAsync();
    for (Attachment attachment in attachments) {
      try {
        File(attachment.getFile().path!).deleteSync();
      } catch (e) {
        Logger.debug("Failed to rm attachment $e");
      }
    }

    await ChatsSvc.deleteChat(chat);
  }

  static Future<void> softDelete(Chat chat, {bool markDeleted = true}) async {
    if (kIsWeb) return;
    // ChatsSvc.softDeleteChat closes the conversation view, soft-deletes the
    // row and calls chat.clearTranscript() for us.
    await ChatsSvc.softDeleteChat(chat);
    if (markDeleted) {
      // OpenBubbles: tell rustpush about the deletion.
      await backend.moveToRecycleBin(chat, null);
    }
  }

  static Future<void> unDelete(Chat chat) async {
    if (kIsWeb) return;
    chat.dateDeleted = null;
    // Pre-merge this was `!(handle.contact?.isShared ?? true)` on the old
    // Contact model. ContactV2 has no `isShared`; a contact that came from the
    // device's address book (isNative) is the equivalent of "really known".
    chat.senderIsKnown = chat.handles.any((handle) => handle.contactsV2.any((c) => c.isNative));
    chat.save(updateDateDeleted: true, updateSenderIsKnown: true);
    await ChatsSvc.unDeleteChat(chat);
  }

  /// OpenBubbles compatibility: synchronous, fire-and-forget wrapper around
  /// [toggleHasUnreadAsync] for the fork's call sites.
  Chat toggleHasUnread(bool hasUnread,
      {bool force = false,
      bool newOnMessage = false,
      bool clearLocalNotifications = true,
      bool privateMark = true}) {
    unawaited(toggleHasUnreadAsync(hasUnread,
        force: force,
        newOnMessage: newOnMessage,
        clearLocalNotifications: clearLocalNotifications,
        privateMark: privateMark));
    return this;
  }

  /// Toggle unread status - pure DB operation
  /// Note: For full unread toggle with active chat awareness, use ChatsSvc.toggleChatHasUnread
  Future<Chat> toggleHasUnreadAsync(bool hasUnread,
      {bool force = false,
      bool newOnMessage = false,
      bool clearLocalNotifications = true,
      bool privateMark = true}) async {
    if (kIsDesktop && !hasUnread) {
      NotificationsSvc.clearDesktopNotificationsForChat(guid);
    }

    if (hasUnreadMessage == hasUnread && !force) return this;
    // OpenBubbles: never flip a chat to unread while it is on screen, and only
    // notify the other side when the read state actually changed.
    var changed = false;
    if (!ChatsSvc.isChatActive(guid) || !hasUnread || force) {
      changed = (Chat.findOne(guid: guid)?.hasUnreadMessage ?? !hasUnread) != hasUnread || newOnMessage;
      hasUnreadMessage = hasUnread;
      await saveAsync(updateHasUnreadMessage: true);
    }
    if (ChatsSvc.isChatActive(guid) && hasUnread && !force) {
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
      // OpenBubbles routes read/unread through the BackendService (rustpush)
      // rather than ChatInterface/HttpSvc.
      if (privateMark && changed) {
        if (!hasUnread) {
          backend.markRead(
              this,
              SettingsSvc.settings.enablePrivateAPI.value &&
                  (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value));
        } else {
          backend.markUnread(this);
        }
      }
    } catch (e, s) {
      Logger.warn("Failed to mark chat as read on message add", error: e, trace: s, tag: 'Chat');
    }

    return this;
  }

  /// Add message to chat - pure DB operation
  /// Note: For full message add with service updates, use ChatsSvc.addMessageToChat
  Future<MessageSaveResult> addMessage(Message message,
      {bool changeUnreadStatus = true,
      bool checkForMessageText = true,
      bool clearNotificationsIfFromMe = true,
      List<Attachment> attachments = const []}) async {
    // Save the message using the interface
    Message? latest = dbLatestMessage.target;
    Message? newMessage;
    bool isNewer = false;

    try {
      final result = await ChatInterface.addMessageToChat(
        messageData: message.toMap(),
        attachmentsData: attachments.map((e) => e.toMap()).toList(),
        chatData: toMap(),
        latestMessageData: (latest ?? Message(dateCreated: DateTime.fromMillisecondsSinceEpoch(0), guid: guid)).toMap(),
        checkForMessageText: checkForMessageText,
      );

      // Extract from MessageSaveResult
      newMessage = result.message;
      isNewer = result.isNewer;
    } catch (ex, stacktrace) {
      newMessage = Message.findOne(guid: message.guid);
      if (newMessage == null) {
        Logger.error("Failed to add message (GUID: ${message.guid}) to chat (GUID: $guid)",
            error: ex, trace: stacktrace);
      }
    }

    // Handle post-save operations on main thread
    if (isNewer) {
      // Link the saved (DB-hydrated) message so a freshly-added chat's tile is
      // built with its subtitle populated on first paint.
      setLatestMessage(newMessage ?? message);
      if (dateDeleted != null) {
        dateDeleted = null;
        await saveAsync(updateDateDeleted: true);
        await ChatsSvc.addChat(this);
      }
      // OpenBubbles: don't unarchive on a message from a blocked sender.
      if (isArchived! &&
          !message.isFromMe! &&
          SettingsSvc.settings.unarchiveOnNewMessage.value &&
          !(participants.firstOrNull?.isBlocked() ?? false)) {
        await toggleArchivedAsync(false);
      }
    }

    if (!(senderIsKnown ?? true) && message.isFromMe!) {
      senderIsKnown = true;
      cvc(this).reportJunkAvailable.value = !(senderIsKnown ?? true);
      save(updateSenderIsKnown: true);
    }

    // Save the chat.
    // This will update the latestMessage info as well as update some
    // other fields that we want to "mimic" from the server
    await saveAsync();

    // If the incoming message was newer than the "last" one, set the unread status accordingly
    if (checkForMessageText && changeUnreadStatus && isNewer) {
      // OpenBubbles: force a (private-API) mark-read while the chat is on screen.
      final isActive = ChatsSvc.isChatActive(guid);
      if (message.isFromMe! || isActive) {
        await toggleHasUnreadAsync(false,
            clearLocalNotifications: clearNotificationsIfFromMe,
            force: isActive,
            privateMark: isActive,
            newOnMessage: !message.isFromMe!);
      } else {
        await toggleHasUnreadAsync(true, privateMark: false);
      }
    }

    // If the message is for adding or removing participants,
    // we need to ensure that all of the chat participants are correct by syncing with the server
    if (message.isParticipantEvent && checkForMessageText) {
      serverSyncParticipantsAsync();
    }

    // Return the saved message and isNewer flag
    return MessageSaveResult(newMessage ?? message, isNewer);
  }

  Future<void> serverSyncParticipantsAsync() async {
    // Sync participants from server - delegates to service layer
    // Note: For full sync with service updates, this is called by ChatsSvc.addMessageToChat
    try {
      // OpenBubbles: pre-merge this went through cm.fetchChat (now
      // ChatsSvc.fetchChat), which falls back to the local copy when there is no
      // BlueBubbles server. Upstream replaced it with a raw HttpSvc call — under
      // rustpush there is nothing to fetch, participants arrive over APNs.
      final remote = backend.getRemoteService();
      if (remote == null) return;
      final response = await remote.chat.fetchOne(guid, withQuery: "participants");
      if (response.statusCode == 200 && response.data["data"] != null) {
        final chatData = response.data["data"];
        final updatedChat = (await ChatInterface.bulkSyncChats(chatsData: [chatData])).chats;
        if (updatedChat.isNotEmpty) {
          await updatedChat.first.saveAsync();
        }
      }
    } catch (ex, stacktrace) {
      Logger.error("Failed to sync participants", error: ex, trace: stacktrace);
    }
  }

  // count() method moved to ChatsService

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
        if (chat.handles.isNotEmpty && !message.isFromMe! && message.handleId != null && message.handleId != 0) {
          Handle? handle = chat.handles.firstWhereOrNull((e) => e.originalROWID == message.handleId) ??
              message.handleRelation.target;
          if (handle == null) {
            messages.remove(message);
            i--;
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
          m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
        }
      }
      return messages;
    });
  }

  /// Fetch messages asynchronously with progressive loading
  /// Returns messages with attachments, then loads reactions in background
  static Future<List<Message>> getMessagesAsync(Chat chat,
      {int offset = 0,
      int limit = 25,
      bool includeDeleted = false,
      int? searchAround,
      Function? onSupplementalDataLoaded}) async {
    if (kIsWeb || chat.id == null) return [];

    final totalStopwatch = Stopwatch()..start();

    // PHASE 1: Query messages with attachments using interface/actions pattern
    final messages = await ChatInterface.getMessagesAsync(
      chatId: chat.id!,
      chatGuid: chat.guid,
      participantsData: chat.handles.map((e) => e.toMap()).toList(),
      offset: offset,
      limit: limit,
      includeDeleted: includeDeleted,
      searchAround: searchAround,
    );

    if (messages.isEmpty) {
      return messages;
    }

    // PHASE 2: Load reactions in background (non-blocking)
    final messageGuids = messages.map((e) => e.guid!).toList();

    // Don't await - let this run in background and call callback when done
    _loadSupplementalDataAsync(messages, messageGuids, totalStopwatch, onSupplementalDataLoaded);

    totalStopwatch.stop();
    Logger.debug("[getMessagesAsync] RETURNED (Phase 1 complete): ${totalStopwatch.elapsedMilliseconds}ms");

    // Return messages immediately (reactions/attachments will be added later)
    return messages;
  }

  /// Load reactions in background and append to messages
  static Future<void> _loadSupplementalDataAsync(
    List<Message> messages,
    List<String> messageGuids,
    Stopwatch totalStopwatch,
    Function? onComplete,
  ) async {
    final supplementalStopwatch = Stopwatch()..start();

    try {
      var associatedMessages = await ChatInterface.loadSupplementalData(
        messageGuids: messageGuids,
      );

      Logger.debug("[getMessagesAsync] Phase 2 - Supplemental query: ${supplementalStopwatch.elapsedMilliseconds}ms");

      // Normalize reactions
      associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);

      // Append reactions to original messages
      int messagesWithReactions = 0;
      for (Message m in messages) {
        final messageReactions = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
        m.associatedMessages = messageReactions;
        if (messageReactions.isNotEmpty) {
          messagesWithReactions++;
          Logger.debug("[getMessagesAsync] Phase 2 - Added ${messageReactions.length} reactions to message ${m.guid}",
              tag: "MessageReactivity");
        }
      }

      supplementalStopwatch.stop();
      Logger.debug(
          "[getMessagesAsync] Phase 2 - COMPLETE: ${supplementalStopwatch.elapsedMilliseconds}ms (${associatedMessages.length} reactions on $messagesWithReactions messages)");

      // Notify caller that supplemental data has been loaded
      if (onComplete != null) {
        Logger.debug("[getMessagesAsync] Phase 2 - Calling onComplete callback", tag: "MessageReactivity");
        onComplete();
      } else {
        Logger.warn("[getMessagesAsync] Phase 2 - No onComplete callback provided!", tag: "MessageReactivity");
      }
    } catch (ex, stacktrace) {
      Logger.error("Failed to load supplemental data for messages", error: ex, trace: stacktrace);
    }
  }

  void webSyncParticipants() {}

  /// Toggle pin status - pure DB operation
  /// Note: For full pin toggle with service updates, use ChatsSvc.toggleChatPin
  Future<Chat> togglePinAsync(bool isPinned) async {
    if (id == null) return this;
    this.isPinned = isPinned;
    _pinIndex.value = null;
    await saveAsync(updateIsPinned: true, updatePinIndex: true);
    return this;
  }

  Future<Chat> toggleMuteAsync(bool isMuted) async {
    if (id == null) return this;
    muteType = isMuted ? "mute" : null;
    muteArgs = null;
    await saveAsync(updateMuteType: true, updateMuteArgs: true);
    return this;
  }

  /// Toggle archive status - pure DB operation
  /// Note: For full archive toggle with service updates, use ChatsSvc.toggleChatArchive
  Future<Chat> toggleArchivedAsync(bool isArchived) async {
    if (id == null) return this;
    isPinned = false;
    this.isArchived = isArchived;
    await saveAsync(updateIsPinned: true, updateIsArchived: true);
    return this;
  }

  Future<Chat> toggleAutoReadAsync(bool? autoSendReadReceipts) async {
    if (id == null) return this;
    this.autoSendReadReceipts = autoSendReadReceipts;
    await saveAsync(updateAutoSendReadReceipts: true);
    // OpenBubbles routes this through the BackendService (rustpush).
    backend.markRead(this, autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value);
    return this;
  }

  Future<Chat> toggleAutoTypeAsync(bool? autoSendTypingIndicators) async {
    if (id == null) return this;
    this.autoSendTypingIndicators = autoSendTypingIndicators;
    await saveAsync(updateAutoSendTypingIndicators: true);
    if (!(autoSendTypingIndicators ?? SettingsSvc.settings.privateSendTypingIndicators.value)) {
      // OpenBubbles routes this through the BackendService (rustpush).
      backend.stoppedTyping(this);
    }
    return this;
  }

  /// Finds a chat - only use this method on Flutter Web!!!
  static Future<Chat?> findOneWeb({String? guid, String? chatIdentifier}) async {
    return null;
  }

  static Chat? findByHandle(String handle) {
    final query = (Database.chats.query()
          ..linkMany(Chat_.handles, Handle_.address.oneOf([handle])))
            .build();
    final results = query.find();
    query.close();

    return results.firstWhereOrNull((res) => res.handles.length == 1);
  }

  static Chat? findByRustGuid(String guid) {
    final direct = Chat.findOne(guid: guid);
    if (direct != null) return direct;

    // prioritize finding by related GUID
    final query = Database.chats.query(Chat_.guidRefs.containsElement(guid)).build();
    final results = query.find();
    query.close();
    if (results.isNotEmpty) {
      // we found one!
      return results[0];
    }
    return null;
  }

  // if soft is false, return is never null
  // only null if soft is true and no matching chat is found
  static Future<Chat?> findByRust(api.ConversationData data, String service, {bool soft = false, bool routingStub = false}) async {
    if (data.participants.isEmpty) {
      throw Exception("empty participants!??");
    }

    if (data.senderGuid != null) {
      // first find by direct GUID
      final direct = Chat.findOne(guid: data.senderGuid);
      if (direct != null) return direct;

      // prioritize finding by related GUID
      final query = Database.chats.query(Chat_.guidRefs.containsElement(data.senderGuid!)).build();
      final results = query.find();
      query.close();
      if (results.isNotEmpty) {
        // we found one!
        return results[0];
      }
    }

    var (mine, dartParticipants) = await RustPushBBUtils.rustParticipantsToBB(data.participants);

    final name = data.cvName;

    var cond = Chat_.isRoutingStub.equals(routingStub);
    if (name != null) {
      cond = cond.and(Chat_.apnTitle.equals(name));
    }
    final query = (Database.chats.query(cond)
          ..linkMany(Chat_.handles, Handle_.address.oneOf(dartParticipants.map((e) => e.address).toList())))
            .build();
    final results = query.find();
    query.close();

    Logger.warn("Found ${results.length} candidates");

    var result = results.firstWhereOrNull((element) {
      var participantsCopy = [...dartParticipants];
      for (var handle in element.handles) {
        var included = participantsCopy.contains(handle);
        if (!included) {
          Logger.warn("Bailing on candidate because ${handle.address} ${handle.id} is not ${participantsCopy.map((i) => "${i.address} ${i.id}").join(", ")} .. ${element.handles.map((i) => "${i.address} ${i.id}").join(", ")}");
          return false;
        }
        participantsCopy.remove(handle);
      }
      Logger.warn("Bailing on candidate left ${participantsCopy.map((i) => "${i.address} ${i.id}").join(", ")} .. ${element.handles.map((i) => "${i.address} ${i.id}").join(", ")}");
      return participantsCopy.isEmpty;
    });
    if (result == null && !soft) {
      result = await backend.createChat(dartParticipants.map((e) => e.address).toList(), null, service, existingGuid: data.senderGuid);
      result.displayName = data.cvName;
      result.isRoutingStub = routingStub;
      result.apnTitle = data.cvName;
      if (mine.isNotEmpty) result.usingHandle = mine[0];
      result = result.save();
      ChatsSvc.updateChat(result);
    }
    return result;
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

    final chats = await ChatInterface.getChatsAsync(
      limit: limit,
      offset: offset,
      ids: ids,
    );

    // Populate contact name cache on main thread for ALL chats in one transaction
    // The cache populated in the isolate doesn't transfer through JSON serialization
    // Database.runInTransaction(TxMode.read, () {
    //   for (Chat c in chats) {
    //     // Re-fetch handles from ObjectBox to get proper instances with relationships
    //     if (c._participants.isNotEmpty) {
    //       final handleIds = c._participants.map((h) => h.id).whereType<int>().where((id) => id != 0).toList();
    //       if (handleIds.isNotEmpty) {
    //         final handlesBox = Database.handles;
    //         final fetchedHandles = handlesBox.getMany(handleIds).whereType<Handle>().toList();
    //         c._participants = fetchedHandles;

    //         // Cache contact names while in transaction
    //         for (final handle in c._participants) {
    //           Logger.debug('[TEST] Handle has formatted address: ${handle.formattedAddress}');
    //           final contactCount = handle.contactsV2.length;
    //           if (contactCount > 0) {
    //             handle.cachedContactName = handle.contactsV2.first.displayName;
    //           } else {
    //             handle.cachedContactName = null;
    //           }
    //         }
    //       }
    //     }
    //   }
    // });

    return chats;
  }

  static Future<List<Chat>> bulkSyncChats(List<Chat> chats) async {
    if (kIsWeb) throw Exception("Web does not support saving chats!");
    if (chats.isEmpty) return [];

    return (await ChatInterface.bulkSyncChats(
      chatsData: chats.map((e) => e.toMap()).toList(),
    ))
        .chats;
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

  /// OpenBubbles-only: undo [clearTranscript].
  void restoreTranscript() {
    if (kIsWeb) return;
    Database.runInTransaction(TxMode.write, () {
      final toRestore = List<Message>.from(messages);
      for (Message element in toRestore) {
        element.dateDeleted = null;
      }
      Database.messages.putMany(toRestore);
    });
  }

  Future<void> clearTranscriptAsync() async {
    if (kIsWeb || id == null) return;

    await ChatInterface.clearTranscriptAsync(
      chatId: id!,
      chatGuid: guid,
    );
  }

  /// The messaging service this chat belongs to, derived from the GUID prefix.
  ChatServiceType get service => ChatServiceType.fromGuid(guid);

  /// OpenBubbles: rustpush SMS-relay chats count as text forwarding too.
  bool get isTextForwarding => service == ChatServiceType.sms || isRpSms;

  bool get isSMS => service == ChatServiceType.sms;

  bool get isIMessage => service == ChatServiceType.iMessage;

  // Check style first so handles isn't required to be evaluated, which will incur a DB lookup.
  bool get isGroup => style == 43 || handles.length > 1;

  Chat merge(Chat other) {
    id ??= other.id;
    _customAvatarPath.value ??= other._customAvatarPath.value;
    _customBackgroundPath.value ??= other._customBackgroundPath.value;
    _pinIndex.value ??= other._pinIndex.value;
    autoSendReadReceipts ??= other.autoSendReadReceipts;
    autoSendTypingIndicators ??= other.autoSendTypingIndicators;
    textFieldText ??= other.textFieldText;
    textFieldAnnotations ??= other.textFieldAnnotations;
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
    if (dbLatestMessage.target == null && other.dbLatestMessage.target != null) {
      setLatestMessage(other.dbLatestMessage.target!);
    }
    muteArgs ??= other.muteArgs;
    dateDeleted ??= other.dateDeleted;
    style ??= other.style;
    wallpaperType ??= other.wallpaperType;
    dynamicWallpaperId ??= other.dynamicWallpaperId;
    dynamicWallpaperConfig ??= other.dynamicWallpaperConfig;
    return this;
  }

  static int sort(Chat? a, Chat? b) {
    // If they both are pinned & ordered, reflect the order
    if (a!.isPinned! && b!.isPinned! && a.pinIndex != null && b.pinIndex != null) {
      return a.pinIndex!.compareTo(b.pinIndex!);
    }

    // If b is pinned & ordered, but a isn't either pinned or ordered, return accordingly
    if (b!.isPinned! && b.pinIndex != null && (!a.isPinned! || a.pinIndex == null)) {
      return 1;
    }
    // If a is pinned & ordered, but b isn't either pinned or ordered, return accordingly
    if (a.isPinned! && a.pinIndex != null && (!b.isPinned! || b.pinIndex == null)) {
      return -1;
    }

    // Compare when one is pinned and the other isn't
    if (!a.isPinned! && b.isPinned!) {
      return 1;
    }
    if (a.isPinned! && !b.isPinned!) {
      return -1;
    }

    // Compare the last message dates (negate to sort newest first)
    final aDate = a.dbOnlyLatestMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.dbOnlyLatestMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return -aDate.compareTo(bDate);
  }

  String getIconPath(int responseLength) {
    return "${FilesystemSvc.appDocDir.path}/avatars/${guid.characters.where((char) => char.isAlphabetOnly || char.isNumericOnly).join()}/avatar-$responseLength.jpg";
  }

  static Future<void> getIcon(Chat c, {bool force = false}) async {
    // OpenBubbles: chat icons come from the BackendService, not HttpSvc directly.
    if ((!force && c.lockChatIcon) || backend.getRemoteService() == null) return;
    final response = await backend.getRemoteService()!.chat.getIcon(c.guid).catchError((err, stack) async {
      Logger.error("Failed to get chat icon for chat ${c.getTitle()}", error: err, trace: stack);
      return Response(statusCode: 500, requestOptions: RequestOptions(path: ""));
    });
    if (response.statusCode != 200 || isNullOrEmpty(response.data)) {
      if (c.customAvatarPath != null) {
        await File(c.customAvatarPath!).delete(recursive: true);
        c.customAvatarPath = null;
        await c.saveAsync(updateCustomAvatarPath: true);
      }
    } else {
      Logger.debug("Got chat icon for chat ${c.getTitle()}");
      // OpenBubbles names the file after the payload length so a changed icon
      // lands on a new path and busts any image cache.
      File file = File(c.getIconPath(response.data.length));
      if (!(await file.exists())) {
        await file.create(recursive: true);
      }
      if (c.customAvatarPath != null) {
        await file.delete();
      }
      await file.writeAsBytes(response.data);
      c.customAvatarPath = file.path;
      await c.saveAsync(updateCustomAvatarPath: true);
    }
  }

  Map<String, dynamic> toMap() {
    final participants = handles.isEmpty ? this.participants : handles.toList();
    return {
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
      "_customBackgroundPath": _customBackgroundPath.value,
      "_pinIndex": _pinIndex.value,
      "autoSendReadReceipts": autoSendReadReceipts,
      "autoSendTypingIndicators": autoSendTypingIndicators,
      "dateDeleted": dateDeleted?.millisecondsSinceEpoch,
      "style": style,
      "lockChatName": lockChatName,
      "lockChatIcon": lockChatIcon,
      "lastReadMessageGuid": lastReadMessageGuid,
      "customThemeLight": customThemeLight,
      "customThemeDark": customThemeDark,
      "wallpaperType": wallpaperType,
      "dynamicWallpaperId": dynamicWallpaperId,
      "dynamicWallpaperConfig": dynamicWallpaperConfig,
      "textFieldText": textFieldText,
      "textFieldAttachments": textFieldAttachments,
      "dbOnlyLatestMessageDate": dbOnlyLatestMessageDate?.millisecondsSinceEpoch,
      "dbLatestMessageId": dbLatestMessage.targetId,
      // ---- OpenBubbles-only ----
      "isRpSms": isRpSms,
      "guidRefs": guidRefs,
      "telephonyId": telephonyId,
      "textFieldAnnotations": textFieldAnnotations,
      "notifsSilenced": notifsSilenced,
      "zenModeIsShared": zenModeIsShared,
      "shareZenMode": shareZenMode,
      "dateNotifiedAnyways": dateNotifiedAnyways?.millisecondsSinceEpoch,
      "isRoutingStub": isRoutingStub,
      "usingHandle": usingHandle,
    };
  }
}
