import 'dart:async';
import 'dart:io';

import 'package:bluebubbles/app/state/attachment_state.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/helpers/types/helpers/message_helper.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:rxdart/rxdart.dart';
import 'package:tuple/tuple.dart';

// ignore: non_constant_identifier_names
MessagesService MessagesSvc(String chatGuid) => Get.isRegistered<MessagesService>(tag: chatGuid)
    ? Get.find<MessagesService>(tag: chatGuid)
    : Get.put(MessagesService(chatGuid), tag: chatGuid);

String? lastReloadedChat() =>
    Get.isRegistered<String>(tag: 'lastReloadedChat') ? Get.find<String>(tag: 'lastReloadedChat') : null;

class MessagesService extends GetxController {
  static final Map<String, Size> cachedBubbleSizes = {};
  late Chat chat;
  late StreamSubscription countSub;
  final ChatMessages struct = ChatMessages();
  late Function(Message) newFunc;
  late Function(Message, {String? oldGuid}) updateFunc;
  late Function(Message) removeFunc;
  late Function(String) jumpToMessage;
  late List<Message> messagesRef;

  final String tag;
  MessagesService(this.tag);

  int currentCount = 0;
  bool isFetching = false;
  bool _init = false;
  bool messagesLoaded = false;
  String? method;

  /// Map of message states for granular reactivity
  /// Key is message GUID, value is MessageState
  /// Provides O(1) lookups and granular observable fields
  final Map<String, MessageState> messageStates = {};

  /// Listeners for redacted mode settings to update all MessageStates
  StreamSubscription? _redactedModeListener;
  StreamSubscription? _hideMessageContentListener;

  /// Granular reactivity map to track individual message updates
  /// Key: message guid, Value: timestamp of last update
  final RxMap<String, int> messageUpdateTrigger = <String, int>{}.obs;

  Message? get mostRecentSent => (struct.messages.where((e) => e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecent => (struct.messages.toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecentReceived =>
      (struct.messages.where((e) => !e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  // ========== MessageState Management ==========

  /// Get or create a MessageState for a specific message GUID
  /// Creates the state if it doesn't exist
  /// Throws if message doesn't exist in struct
  MessageState getOrCreateMessageState(String guid) {
    if (!messageStates.containsKey(guid)) {
      final message = struct.getMessage(guid);
      if (message == null) {
        throw Exception('Cannot create MessageState: Message $guid not found in struct');
      }
      final state = MessageState(message);
      state.onInit();
      messageStates[guid] = state;
      Logger.debug("Created MessageState for message $guid", tag: "MessageState");
    }
    return messageStates[guid]!;
  }

  /// Get or create a [MessageState] for [message], initialising it if new.
  /// This is the widget-facing entry point (replaces getOrCreateController).
  MessageState getOrCreateState(Message message) {
    final guid = message.guid!;
    if (!messageStates.containsKey(guid)) {
      final state = MessageState(message);
      state.onInit();
      messageStates[guid] = state;
      Logger.debug("Created MessageState for message $guid", tag: "MessageState");
    }
    return messageStates[guid]!;
  }

  /// Get MessageState if it exists, null otherwise
  /// Use this when you're not sure if the message exists
  MessageState? getMessageStateIfExists(String guid) {
    return messageStates[guid];
  }

  /// Sync a MessageState from the database
  /// Call this after any external DB update that doesn't go through MessagesService
  /// This ensures MessageState stays in sync with DB changes
  void syncMessageStateFromDB(String guid) {
    final message = Message.findOne(guid: guid);
    if (message != null) {
      final state = messageStates[guid];
      if (state != null) {
        state.updateFromMessage(message);
        Logger.debug("Synced MessageState from DB for message $guid", tag: "MessageState");
      } else {
        // State doesn't exist, create it
        messageStates[guid] = MessageState(message);
        Logger.debug("Created MessageState from DB sync for message $guid", tag: "MessageState");
      }
    }
  }

  /// Ensure MessageStates exist for a list of messages
  /// Creates states for messages that don't have them yet
  void _ensureMessageStates(List<Message> messages) {
    for (final message in messages) {
      if (message.guid != null && !messageStates.containsKey(message.guid)) {
        final state = MessageState(message);
        state.onInit();
        messageStates[message.guid!] = state;
      }
      // Re-apply uploading state for any attachment that is still actively
      // being sent.  When MessagesService is torn down (user navigates away)
      // and then re-created (user re-enters), AttachmentState is constructed
      // fresh from the persisted data.  Because prepAttachment sets
      // isDownloaded=true before the upload completes, the constructor
      // defaults those attachments to transferState=complete/isSending=false,
      // hiding the in-progress send overlay.  This call corrects that.
      _restoreInFlightAttachmentStates(message);
    }
  }

  /// For each temp-GUID attachment on [message] that is actively tracked in
  /// [OutgoingMsgHandler.attachmentProgress], transitions the [AttachmentState]
  /// to [AttachmentTransferState.uploading] and populates
  /// [AttachmentState.uploadPreviewFile] from the local file — so re-entering
  /// a chat mid-upload immediately shows the correct progress UI instead of
  /// a brief [NotLoadedContent] flash.
  ///
  /// Only called for messages whose GUID starts with `temp`; non-temp messages
  /// and stale orphaned temp records (upload progress not in tracker) are
  /// left unchanged so existing behaviour is undisturbed.
  void _restoreInFlightAttachmentStates(Message message) {
    if (kIsWeb) return;
    final msgGuid = message.guid;
    if (msgGuid == null) return;

    for (final attachment in message.dbAttachments) {
      if (attachment.guid == null || !(attachment.guid!.startsWith('temp'))) continue;
      // Only restore if the upload is actively tracked in the singleton handler.
      // This intentionally skips stale temp records from crashed/killed sessions.
      final inFlight = OutgoingMsgHandler.attachmentProgress.firstWhereOrNull((e) => e.item1 == attachment.guid);
      if (inFlight == null) continue;

      final msgState = messageStates[msgGuid];
      if (msgState == null) continue;

      final attState = msgState.getOrCreateAttachmentState(attachment.guid!, attachment: attachment);
      if (attState.transferState.value != AttachmentTransferState.uploading) {
        attState.updateTransferStateInternal(AttachmentTransferState.uploading);
      }

      // Populate the preview file so UploadProgressContent can render the
      // image behind the progress overlay immediately on re-entry.
      if (attState.uploadPreviewFile.value == null && attachment.transferName != null) {
        final pathName = attachment.path;
        if (File(pathName).existsSync()) {
          attState.updateUploadPreviewFileInternal(PlatformFile(
            name: attachment.transferName!,
            path: pathName,
            size: attachment.totalBytes ?? 0,
          ));
        }
      }

      Logger.debug(
        'Restored in-flight upload state for attachment ${attachment.guid} (msg $msgGuid)',
        tag: 'AttachmentState',
      );
    }
  }

  // ========== End MessageState Management ==========

  // ========== AttachmentState Management ==========

  /// Returns the [AttachmentState] for [attachmentGuid] within the message
  /// identified by [messageGuid], or `null` if either state does not exist.
  AttachmentState? getAttachmentState(String messageGuid, String attachmentGuid) {
    return messageStates[messageGuid]?.getAttachmentState(attachmentGuid);
  }

  /// Notifies that an attachment upload is starting (called from
  /// [OutgoingMessageHandler.prepAttachment] before the HTTP call is made).
  ///
  /// Ensures the message and attachment are registered in the state maps and
  /// transitions the attachment to [AttachmentTransferState.uploading].
  void notifyAttachmentUploadStarted(Message message, Attachment attachment) {
    if (message.guid == null || attachment.guid == null) return;

    // Ensure the message is in the struct (the ObjectBox watch debounce may
    // not have fired yet at this point).
    if (struct.getMessage(message.guid!) == null) {
      struct.addMessages([message]);
    }

    // Create MessageState if it doesn't exist yet.
    if (!messageStates.containsKey(message.guid!)) {
      final state = MessageState(message);
      state.onInit();
      messageStates[message.guid!] = state;
      Logger.debug("Created MessageState for outgoing message ${message.guid}", tag: "AttachmentState");
    }

    final messageState = messageStates[message.guid!]!;
    final attachmentState = messageState.getOrCreateAttachmentState(attachment.guid!, attachment: attachment);
    attachmentState.updateTransferStateInternal(AttachmentTransferState.uploading);

    // Populate uploadPreviewFile so the UI can show the image behind the
    // progress overlay while the upload is in flight.  The file was already
    // copied to attachment.path by prepAttachment.
    if (!kIsWeb && attachment.transferName != null) {
      final path = attachment.path;
      if (path.isNotEmpty && File(path).existsSync()) {
        attachmentState.updateUploadPreviewFileInternal(PlatformFile(
          name: attachment.transferName!,
          path: path,
          size: attachment.totalBytes ?? 0,
        ));
      }
    }

    Logger.debug(
      "AttachmentState[${attachment.guid}] → uploading (msg ${message.guid})",
      tag: "AttachmentState",
    );
  }

  /// Updates the upload progress for an attachment in flight.
  /// [progress] is a value in [0.0, 1.0].
  void notifyAttachmentUploadProgress(String messageGuid, String attachmentGuid, double progress) {
    messageStates[messageGuid]?.getAttachmentState(attachmentGuid)?.updateUploadProgressInternal(progress);
  }

  /// Notifies that an attachment download has started.
  ///
  /// Transitions the attachment state to [AttachmentTransferState.downloading]
  /// and wires [ctrl.progress] into [AttachmentState.downloadProgress] so the
  /// UI receives live progress updates reactively.
  void notifyAttachmentDownloadStarted(String messageGuid, String attachmentGuid, AttachmentDownloadController ctrl) {
    final messageState = messageStates[messageGuid];
    if (messageState == null) return;

    AttachmentState attachmentState;
    try {
      attachmentState = messageState.getOrCreateAttachmentState(
        attachmentGuid,
        attachment: ctrl.attachment,
      );
    } catch (_) {
      // Message may not have the attachment object yet; create a bare state.
      attachmentState = AttachmentState(ctrl.attachment);
      messageState.attachmentStates[attachmentGuid] = attachmentState;
    }

    attachmentState.updateTransferStateInternal(AttachmentTransferState.downloading);
    attachmentState.updateActiveDownloadInternal(ctrl);
    attachmentState.syncDownloadInternal(ctrl, (PlatformFile file) {
      _onAttachmentDownloadComplete(messageGuid, attachmentGuid, file);
    });

    Logger.debug(
      "AttachmentState[$attachmentGuid] → downloading (msg $messageGuid)",
      tag: "AttachmentState",
    );
  }

  /// Marks an attachment as fully downloaded and transitions its state to
  /// [AttachmentTransferState.complete].
  void notifyAttachmentDownloadComplete(String messageGuid, String attachmentGuid) {
    final state = messageStates[messageGuid]?.getAttachmentState(attachmentGuid);
    if (state == null) return;

    state.updateIsDownloadedInternal(true);
    state.updateActiveDownloadInternal(null);
    state.updateTransferStateInternal(AttachmentTransferState.complete);

    Logger.debug(
      "AttachmentState[$attachmentGuid] → complete (msg $messageGuid)",
      tag: "AttachmentState",
    );
  }

  /// Transitions an attachment to [AttachmentTransferState.error].
  void notifyAttachmentTransferError(String messageGuid, String attachmentGuid) {
    messageStates[messageGuid]
        ?.getAttachmentState(attachmentGuid)
        ?.updateTransferStateInternal(AttachmentTransferState.error);

    Logger.debug(
      "AttachmentState[$attachmentGuid] → error (msg $messageGuid)",
      tag: "AttachmentState",
    );
  }

  /// Re-keys an [AttachmentState] from [oldAttachmentGuid] to
  /// [newAttachmentGuid] within the message identified by [messageGuid].
  ///
  /// Called after an attachment GUID swap (temp → real) so that the state
  /// object survives the transition.  The [AttachmentState.guid] observable is
  /// also updated so reactive listeners receive the new value.
  void renameAttachmentState(String messageGuid, String oldAttachmentGuid, String newAttachmentGuid) {
    if (oldAttachmentGuid == newAttachmentGuid) return;

    final messageState = messageStates[messageGuid];
    if (messageState == null) return;

    final oldState = messageState.attachmentStates.remove(oldAttachmentGuid);
    if (oldState != null) {
      oldState.updateGuidInternal(newAttachmentGuid);
      messageState.attachmentStates[newAttachmentGuid] = oldState;
      Logger.debug(
        "Renamed AttachmentState $oldAttachmentGuid → $newAttachmentGuid (msg $messageGuid)",
        tag: "AttachmentState",
      );
    }
  }

  // ========== End AttachmentState Management ==========

  // ========== Attachment Send Completion ==========

  /// Called after the server confirms an outgoing attachment upload, or when
  /// the incoming handler replaces a temp attachment with the real one.
  ///
  /// Finds the attachment state at [tempAttachmentGuid] — the ORIGINAL key
  /// the state was stored under — and updates it in-place WITHOUT renaming
  /// the map key.  This is intentional: the widget's [_attachmentState] getter
  /// looks up by [part.attachments.first.guid] (always the temp GUID) so it
  /// must be able to find the state even after the Obx re-runs.  The deferred
  /// key rename from temp → real happens lazily in [_syncAttachmentStates]
  /// once [updateMessage] delivers the updated message struct.
  ///
  /// [tempMessageGuid] and [realMessageGuid] are used to locate the
  /// [MessageState]: the temp GUID is tried first (HTTP beats socket); the
  /// real GUID is the fallback for when the socket arrived first and the
  /// MessageState was already moved.
  void notifyAttachmentSendComplete(
    String tempMessageGuid,
    String realMessageGuid,
    String tempAttachmentGuid,
    Attachment resolvedAttachment,
  ) {
    final realAttGuid = resolvedAttachment.guid!;

    // Locate the MessageState — try temp key first, fall back to real.
    MessageState? messageState = messageStates[tempMessageGuid];
    if (messageState == null && realMessageGuid != tempMessageGuid) {
      messageState = messageStates[realMessageGuid];
    }
    if (messageState == null) {
      Logger.warn(
        'notifyAttachmentSendComplete: no MessageState for tempMsg=$tempMessageGuid / realMsg=$realMessageGuid',
        tag: 'AttachmentState',
      );
      return;
    }

    // Register the temp→real mapping so _syncAttachmentStates can promote the
    // correct state key deterministically (critical for multi-attachment messages).
    if (tempAttachmentGuid != realAttGuid) {
      messageState.registerGuidPromotion(tempAttachmentGuid, realAttGuid);
    }

    // Look up state by temp GUID.  If it was already promoted (rare race),
    // fall back to the real key.
    AttachmentState? state = messageState.attachmentStates[tempAttachmentGuid];
    if (state == null && tempAttachmentGuid != realAttGuid) {
      state = messageState.attachmentStates[realAttGuid];
    }
    if (state == null) {
      state = AttachmentState(resolvedAttachment);
      messageState.attachmentStates[tempAttachmentGuid] = state;
    }

    // Sync all metadata (guid, transferName, dimensions, …) so that
    // state.attachment.path uses the real transferName and guid.
    state.updateFromAttachment(resolvedAttachment);

    // Populate resolvedFile if we don't have it yet.
    if (!kIsWeb && state.resolvedFile.value == null && resolvedAttachment.transferName != null) {
      final filePath = resolvedAttachment.path;
      if (File(filePath).existsSync()) {
        state.updateResolvedFileInternal(PlatformFile(
          name: resolvedAttachment.transferName!,
          path: filePath,
          size: resolvedAttachment.totalBytes ?? 0,
        ));
      } else {
        Logger.warn(
          'notifyAttachmentSendComplete: file not found at $filePath '
          'dirContents=${_listDir(resolvedAttachment.directory)}',
          tag: 'AttachmentState',
        );
      }
    }

    // Force-complete the state.  updateFromAttachment's isDownloaded guard
    // may skip the transition when isDownloaded was already true (set in
    // prepAttachment), so we do it explicitly here.
    state.updateIsDownloadedInternal(true);
    state.updateActiveDownloadInternal(null);
    if (state.transferState.value != AttachmentTransferState.complete) {
      state.updateTransferStateInternal(AttachmentTransferState.complete);
    }

    Logger.debug(
      'AttachmentState[$tempAttachmentGuid] → complete '
      '(will promote to $realAttGuid on next _syncAttachmentStates)',
      tag: 'AttachmentState',
    );
  }

  /// Helper: safely lists file names in [dirPath] for debug logging.
  static String _listDir(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return '<dir missing>';
      final names = dir.listSync().map((e) => e.path.split('/').last).join(', ');
      return names.isEmpty ? '<empty dir>' : names;
    } catch (_) {
      return '<error listing dir>';
    }
  }

  // ========== End Attachment Send Completion ==========

  /// Called by [MessagesService] when a download controller confirms the file.
  /// Updates [AttachmentState.resolvedFile] and clears [activeDownload] before
  /// delegating to [notifyAttachmentDownloadComplete].
  void _onAttachmentDownloadComplete(String messageGuid, String attachmentGuid, PlatformFile file) {
    final attState = messageStates[messageGuid]?.getAttachmentState(attachmentGuid);
    if (attState == null) return;
    attState.updateResolvedFileInternal(file);
    attState.updateActiveDownloadInternal(null);
    notifyAttachmentDownloadComplete(messageGuid, attachmentGuid);
  }

  /// Loads the renderable content for [attachment] and updates its
  /// [AttachmentState] accordingly.  Replaces the per-widget `updateContent`
  /// logic so all download orchestration lives in the service layer.
  ///
  /// Safe to call on every widget build — early-returns when the content is
  /// already resolved or a transfer is already in progress.
  Future<void> loadAttachmentContent(String messageGuid, Attachment attachment) async {
    if (attachment.guid == null) return;

    final msgState = messageStates[messageGuid];
    if (msgState == null) return;

    final attState = msgState.getOrCreateAttachmentState(attachment.guid!, attachment: attachment);

    // Don't interfere with active or already-resolved transfers.
    final ts = attState.transferState.value;
    if (ts == AttachmentTransferState.uploading) return;
    if (ts == AttachmentTransferState.downloading || ts == AttachmentTransferState.queued) return;
    if (ts == AttachmentTransferState.complete &&
        attState.resolvedFile.value != null &&
        attState.guid.value == attachment.guid) {
      return;
    }

    final content = AttachmentsSvc.getContent(attachment, onComplete: (PlatformFile file) {
      _onAttachmentDownloadComplete(messageGuid, attachment.guid!, file);
    });

    if (content is PlatformFile) {
      attState.updateResolvedFileInternal(content);
      attState.updateIsDownloadedInternal(true);
      if (attState.transferState.value != AttachmentTransferState.complete) {
        attState.updateTransferStateInternal(AttachmentTransferState.complete);
      }
      return;
    }

    if (content is AttachmentDownloadController) {
      attState.updateActiveDownloadInternal(content);
      notifyAttachmentDownloadStarted(messageGuid, attachment.guid!, content);
      return;
    }

    if (content is AttachmentWithProgress) {
      attState.updateUploadPreviewFileInternal(content.file);
      if (attState.transferState.value != AttachmentTransferState.uploading) {
        attState.updateTransferStateInternal(AttachmentTransferState.uploading);
      }
      return;
    }

    if (content is Tuple2<String, RxDouble>) {
      // Upload in progress without an accessible preview file.
      if (attState.transferState.value != AttachmentTransferState.uploading) {
        attState.updateTransferStateInternal(AttachmentTransferState.uploading);
      }
      return;
    }

    if (content is Attachment) {
      if (attachment.guid?.startsWith('temp') ?? false) return;
      final messageError = struct.getMessage(messageGuid)?.error ?? 0;
      if (messageError != 0) return;

      if (await AttachmentsSvc.canAutoDownload()) {
        _startAttachmentDownload(messageGuid, content);
      }
    }
  }

  /// Starts a download for [attachment] and wires it into [AttachmentState].
  void _startAttachmentDownload(String messageGuid, Attachment attachment) {
    final msgGuid = messageGuid;
    final attGuid = attachment.guid!;
    final ctrl = AttachmentDownloader.startDownload(attachment, onComplete: (PlatformFile file) {
      _onAttachmentDownloadComplete(msgGuid, attGuid, file);
    });

    final msgState = messageStates[messageGuid];
    if (msgState == null) return;

    final attState = msgState.getOrCreateAttachmentState(attGuid, attachment: attachment);
    attState.updateActiveDownloadInternal(ctrl);
    notifyAttachmentDownloadStarted(messageGuid, attGuid, ctrl);
  }

  /// Manually triggers a download for [attachment] (e.g., user tapped
  /// a not-loaded attachment).  The [messageGuid] must match the owning
  /// message's GUID.
  void startAttachmentDownload(String messageGuid, Attachment attachment) {
    _startAttachmentDownload(messageGuid, attachment);
  }

  /// Deletes the stale [AttachmentDownloadController] and restarts the
  /// download.  Called when the user taps a failed (error-state) attachment.
  void retryAttachmentDownload(String messageGuid, Attachment attachment) {
    if (attachment.guid != null) {
      Get.delete<AttachmentDownloadController>(tag: attachment.guid);
    }
    // Clear stale active-download reference before restarting.
    messageStates[messageGuid]?.getAttachmentState(attachment.guid!)?.updateActiveDownloadInternal(null);
    _startAttachmentDownload(messageGuid, attachment);
  }

  /// Deletes the local attachment files, resets the [AttachmentState] so the
  /// UI immediately shows the downloading UI, and starts a fresh download.
  ///
  /// Called when the user picks "Re-download from server".  Unlike a simple
  /// `attachmentRefreshKey` bump, this method explicitly clears `resolvedFile`
  /// and transitions the state to [AttachmentTransferState.downloading] so
  /// that [loadAttachmentContent]'s early-exit guards don't swallow the event.
  Future<void> redownloadAttachment(String messageGuid, Attachment attachment) async {
    final attGuid = attachment.guid;
    if (attGuid == null) return;

    // 1. Reset the AttachmentState so the UI drops the resolved file
    //    immediately and shows the downloading widget instead.
    final attState = messageStates[messageGuid]?.getAttachmentState(attGuid);
    if (attState != null) {
      attState.updateResolvedFileInternal(null);
      attState.updateActiveDownloadInternal(null);
      attState.updateIsDownloadedInternal(false);
      attState.updateTransferStateInternal(AttachmentTransferState.idle);
    }

    // 2. Delete local files, reset DB flag, and register a new controller.
    await AttachmentsSvc.redownloadAttachment(attachment);

    // 3. Wire the freshly created controller into the state machine so the
    //    Obx in AttachmentHolder rebuilds with DownloadingContent.
    final ctrl = AttachmentDownloader.getController(attGuid);
    if (ctrl != null) {
      notifyAttachmentDownloadStarted(messageGuid, attGuid, ctrl);
    }
  }

  // ========== End Attachment Download Orchestration ==========

  void init(Chat c, Function(Message) onNewMessage, Function(Message, {String? oldGuid}) onUpdatedMessage,
      Function(Message) onDeletedMessage, Function(String) jumpToMessageFunc, List<Message> messagesRef) {
    chat = c;
    Get.put<String>(tag, tag: 'lastReloadedChat');

    updateFunc = onUpdatedMessage;
    removeFunc = onDeletedMessage;
    newFunc = onNewMessage;
    jumpToMessage = jumpToMessageFunc;
    this.messagesRef = messagesRef;

    // watch for new messages
    if (!_init) {
      if (chat.id != null) {
        final countQuery = (Database.messages.query(Message_.dateDeleted.isNull())
              ..link(Message_.chat, Chat_.id.equals(chat.id!))
              ..order(Message_.id, flags: Order.descending))
            .watch(triggerImmediately: true);

        // Debounce the stream to batch rapid changes (reduces processing overhead)
        countSub = countQuery.debounceTime(const Duration(milliseconds: 100)).listen((event) async {
          if (!SettingsSvc.settings.finishedSetup.value) return;
          final newCount = event.count();
          if (!isFetching && newCount > currentCount && currentCount != 0) {
            event.limit = newCount - currentCount;
            final messages = event.find();
            event.limit = 0;
            for (Message message in messages) {
              await _handleNewMessage(message);
            }
          }
          currentCount = newCount;
        });
      } else if (kIsWeb) {
        countSub = WebListeners.newMessage.listen((tuple) {
          if (tuple.item2?.guid == chat.guid) {
            _handleNewMessage(tuple.item1);
          }
        });
      }
    }
    _init = true;
    _setupRedactedModeListeners();
  }

  /// Set up global listeners for redacted mode settings that update all message states
  void _setupRedactedModeListeners() {
    // Cancel existing listeners if any
    _redactedModeListener?.cancel();
    _hideMessageContentListener?.cancel();

    // Listen to redacted mode master toggle - when enabled, redact all messages; when disabled, unredact all
    _redactedModeListener = SettingsSvc.settings.redactedMode.listen((enabled) {
      for (final messageState in messageStates.values) {
        if (enabled) {
          messageState.redactFields();
        } else {
          messageState.unredactFields();
        }
      }
    });

    // Listen to hideMessageContent toggle - only affects message text/subject
    _hideMessageContentListener = SettingsSvc.settings.hideMessageContent.listen((enabled) {
      for (final messageState in messageStates.values) {
        if (enabled) {
          messageState.redactMessageContent();
        } else {
          messageState.unredactMessageContent();
        }
      }
    });
  }

  @override
  void onClose() {
    if (_init) {
      countSub.cancel();
      _redactedModeListener?.cancel();
      _hideMessageContentListener?.cancel();
    }
    _init = false;
    // Dispose all message states (attachment workers + web subscription)
    for (final messageState in messageStates.values) {
      messageState.onClose();
    }
    messageStates.clear();
    super.onClose();
  }

  void close({force = false}) {
    String? lastChat = lastReloadedChat();
    if (force || lastChat != tag) {
      Get.delete<MessagesService>(tag: tag);
    }

    struct.flush();
  }

  void reload() {
    messagesLoaded = false;
    Get.put<String>(tag, tag: 'lastReloadedChat');
    Get.reload<MessagesService>(tag: tag);
  }

  Future<void> _handleNewMessage(Message message) async {
    if (message.hasAttachments && !kIsWeb) {
      message.attachments = List<Attachment>.from(message.dbAttachments);
      // we may need an artificial delay in some cases since the attachment
      // relation is initialized after message itself is saved
      if (message.attachments.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 250));
        message.attachments = List<Attachment>.from(message.dbAttachments);
      }
    }

    // Add to struct first to ensure it's available for lookups
    struct.addMessages([message]);

    // Create or update MessageState for this message.
    // If it already exists (e.g. created by prepAttachment before the ObjectBox
    // watch fired), update the metadata rather than overwriting transfer states.
    if (message.guid != null) {
      if (!messageStates.containsKey(message.guid!)) {
        final state = MessageState(message);
        state.onInit();
        messageStates[message.guid!] = state;
        Logger.debug("Created MessageState for new message ${message.guid}", tag: "MessageState");
      } else {
        messageStates[message.guid!]!.updateFromMessage(message);
        Logger.debug("Updated existing MessageState for message ${message.guid}", tag: "MessageState");
      }
    }

    // Handle reactions with improved reactivity
    if (message.associatedMessageGuid != null) {
      final parentMessage = struct.getMessage(message.associatedMessageGuid!);
      if (parentMessage != null) {
        // Add to parent's associated messages list
        parentMessage.associatedMessages.add(message);

        // Update parent MessageState with the new reaction
        final parentState = messageStates[message.associatedMessageGuid!];
        if (parentState != null) {
          parentState.addAssociatedMessageInternal(message);
          Logger.debug("Added reaction ${message.guid} to MessageState of parent ${message.associatedMessageGuid}",
              tag: "MessageState");
        }

        // Notify UI of update (no longer need to call controller methods)
        triggerMessageUpdate(message.associatedMessageGuid!);
      } else {
        Logger.warn("Parent message not found for reaction ${message.guid} (parent: ${message.associatedMessageGuid})",
            tag: "MessageReactivity");
      }
    }

    // Handle thread originators with improved reactivity
    if (message.threadOriginatorGuid != null) {
      // Update thread originator MessageState
      final originatorState = messageStates[message.threadOriginatorGuid!];
      if (originatorState != null) {
        final currentCount = originatorState.threadReplyCount.value;
        originatorState.updateThreadReplyCountInternal(currentCount + 1);
        Logger.debug("Incremented thread reply count for ${message.threadOriginatorGuid} to ${currentCount + 1}",
            tag: "MessageState");
      }

      // Notify UI of update
      triggerMessageUpdate(message.threadOriginatorGuid!);
    }

    // Only call newFunc for non-reactions (regular messages)
    if (message.associatedMessageGuid == null) {
      newFunc.call(message);
    }
  }

  void updateMessage(Message updated, {String? oldGuid}) {
    // Try to find the message - check oldGuid first, then fallback to updated.guid
    // This handles race conditions where the GUID was already replaced
    Message? toUpdate;
    if (oldGuid != null) {
      toUpdate = struct.getMessage(oldGuid);
    }
    toUpdate ??= struct.getMessage(updated.guid!);
    if (toUpdate == null) return;

    updated = updated.mergeWith(toUpdate);
    struct.removeMessage(oldGuid ?? updated.guid!);
    struct.removeAttachments(toUpdate.attachments.map((e) => e!.guid!));
    struct.addMessages([updated]);

    // Update MessageState - try oldGuid first, then fallback to updated.guid
    MessageState? messageState;
    if (oldGuid != null) {
      messageState = messageStates[oldGuid];
    }
    messageState ??= messageStates[updated.guid!];

    if (messageState != null) {
      messageState.updateFromMessage(updated);
      Logger.debug("Updated MessageState for message ${updated.guid}", tag: "MessageState");

      // If guid changed (temp -> real), update the map
      if (oldGuid != null && oldGuid != updated.guid) {
        messageStates.remove(oldGuid);
        if (updated.guid != null) {
          messageStates[updated.guid!] = messageState;
          Logger.debug("Moved MessageState from $oldGuid to ${updated.guid}", tag: "MessageState");
        }

        // Notify the state to merge the new message reference and rebuild parts.
        // notifyGuidSwap avoids re-entering this method.
        messageState.notifyGuidSwap(updated);
      }
    } else if (updated.guid != null) {
      // State doesn't exist, create it
      final state = MessageState(updated);
      state.onInit();
      messageStates[updated.guid!] = state;
    }

    // Trigger granular update for this specific message
    messageUpdateTrigger[updated.guid!] = DateTime.now().millisecondsSinceEpoch;

    updateFunc.call(updated, oldGuid: oldGuid);
  }

  void removeMessage(Message toRemove) {
    struct.removeMessage(toRemove.guid!);
    struct.removeAttachments(toRemove.attachments.map((e) => e!.guid!));
    messageUpdateTrigger.remove(toRemove.guid!);

    // Dispose attachment states and remove MessageState
    messageStates.remove(toRemove.guid!)?.onClose();
    Logger.debug("Removed MessageState for message ${toRemove.guid}", tag: "MessageState");

    removeFunc.call(toRemove);
  }

  /// Check if a specific message has been updated (for granular Obx widgets)
  bool isMessageUpdated(String guid) {
    return messageUpdateTrigger.containsKey(guid);
  }

  /// Trigger an update for a specific message (useful for reactions, read receipts, etc.)
  void triggerMessageUpdate(String guid) {
    messageUpdateTrigger[guid] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Clear the update flag for a message after it's been processed
  void clearMessageUpdate(String guid) {
    messageUpdateTrigger.remove(guid);
  }

  /// Retry sending a failed message
  /// Generates new temp GUID, clears error state, and updates both DB and MessageState
  Future<void> retryFailedMessage(Message message, {String? oldGuid}) async {
    final guidToDelete = oldGuid ?? message.guid!;

    // Generate new temp GUID for retry
    message.generateTempGuid();

    // Clear error and delivery status
    message.error = 0;
    message.errorMessage = null;
    message.dateCreated = DateTime.now();
    message.dateDelivered = null;
    message.dateRead = null;

    // Delete old errored message from DB and save with new temp GUID
    await Message.delete(guidToDelete);
    message.id = null;
    message.save(chat: chat);

    // Update struct using the proper map API (struct.messages returns a copy, not the backing map)
    struct.removeMessage(guidToDelete);
    struct.addMessages([message]);

    // If the message isn't the last one in the list, we should remove it from the message view first
    // before re-adding it so it shows up in the proper order based on the retry.
    if (messagesRef.isNotEmpty && messagesRef.last.guid != guidToDelete) {
      removeFunc(message);
      newFunc(message);
    }

    // Clean up old MessageState, then create new one with updated struct entry
    messageStates.remove(guidToDelete);
    final messageState = getOrCreateMessageState(message.guid!);
    messageState.updateErrorInternal(0);
    messageState.updateErrorMessageInternal(null);
    messageState.updateDateCreatedInternal(message.dateCreated);
    messageState.updateDateDeliveredInternal(null);
    messageState.updateDateReadInternal(null);

    // Clear notification
    await NotificationsSvc.clearFailedToSend(chat.id!);

    // Reload attachment bytes if needed
    for (Attachment? a in message.dbAttachments) {
      if (a == null) continue;
      await Attachment.deleteAsync(a.guid!);
      a.bytes = await File(a.path).readAsBytes();
    }

    // Queue for sending (message already in UI, just updated)
    if (message.dbAttachments.isNotEmpty) {
      OutgoingMsgHandler.queue(OutgoingItem(
        type: QueueType.sendAttachment,
        chat: chat,
        message: message,
        customArgs: {
          'isRetry': true,
        }
      ));
    } else {
      OutgoingMsgHandler.queue(OutgoingItem(
        type: QueueType.sendMessage,
        chat: chat,
        message: message,
        customArgs: {
          'isRetry': true,
        }
      ));
    }
  }

  /// Delete a message from DB, struct, and MessageState
  Future<void> deleteMessage(Message message) async {
    await Message.delete(message.guid!);
    removeMessage(message);
  }

  /// Toggle bookmark status on a message
  /// Updates DB and MessageState
  void toggleBookmark(Message message) {
    message.isBookmarked = !message.isBookmarked;
    message.save(updateIsBookmarked: true);

    // Update MessageState if it exists
    final messageState = getMessageStateIfExists(message.guid!);
    messageState?.updateIsBookmarkedInternal(message.isBookmarked);
  }

  Future<bool> loadChunk(int offset, ConversationViewController controller, {int limit = 25}) async {
    isFetching = true;
    List<Message> _messages = [];

    // Adjust offset because reactions _are_ messages. We just separate them out in the struct.
    offset = offset + struct.reactions.length;

    try {
      Logger.debug("[loadChunk] Starting to load messages (offset: $offset, limit: $limit)", tag: "MessageReactivity");

      _messages = await Chat.getMessagesAsync(
        chat,
        offset: offset,
        limit: limit,
        onSupplementalDataLoaded: () {
          // Phase 2 complete - reactions have been loaded into message.associatedMessages
          Logger.info("[loadChunk] Supplemental data loaded, syncing MessageStates for ${_messages.length} messages",
              tag: "MessageReactivity");

          // Ensure MessageStates exist first (in case they weren't created yet)
          _ensureMessageStates(_messages);

          // Sync associatedMessages into MessageState observables
          for (final message in _messages) {
            if (message.guid != null && message.associatedMessages.isNotEmpty) {
              final messageState = messageStates[message.guid];
              if (messageState != null) {
                // Clear and repopulate the observable list to trigger reactivity
                messageState.associatedMessages.clear();
                messageState.associatedMessages.addAll(message.associatedMessages);
                messageState.hasReactions.value = message.associatedMessages.isNotEmpty;

                Logger.debug(
                    "[loadChunk] Synced ${message.associatedMessages.length} reactions into MessageState for ${message.guid}",
                    tag: "MessageReactivity");
              }
            }
          }
        },
      );

      Logger.debug("[loadChunk] Loaded ${_messages.length} messages from local DB");
      if (_messages.isEmpty) {
        // get from server and save
        final fromServer = await ChatsSvc.getMessages(chat.guid, offset: offset, limit: limit);
        final temp = await MessageHelper.bulkAddMessages(chat, fromServer, checkForLatestMessageText: false);
        if (!kIsWeb) {
          // re-fetch from the DB because it will find handles / associated messages for us
          _messages = await Chat.getMessagesAsync(chat, offset: offset, limit: limit);
        } else {
          final reactions = temp.where((e) => e.associatedMessageGuid != null);
          for (Message m in reactions) {
            final associatedMessage = temp.firstWhereOrNull((element) => element.guid == m.associatedMessageGuid);
            associatedMessage?.hasReactions = true;
            associatedMessage?.associatedMessages.add(m);
          }
          _messages = temp;
        }
      }
    } catch (e, s) {
      return Future.error(e, s);
    }

    struct.addMessages(_messages);

    // Create MessageStates for all loaded messages
    _ensureMessageStates(_messages);
    Logger.debug("[loadChunk] Created MessageStates for ${_messages.length} messages", tag: "MessageState");

    // get thread originators
    for (Message m in _messages.where((e) => e.threadOriginatorGuid != null)) {
      // see if the originator is already loaded
      final guid = m.threadOriginatorGuid!;
      if (struct.getMessage(guid) != null) continue;
      // if not, fetch local and add to data
      final threadOriginator = Message.findOne(guid: guid);
      if (threadOriginator != null) {
        // create the state so it can be rendered in a reply bubble
        final c = getOrCreateState(threadOriginator);
        c.cvController = controller;
        struct.addThreadOriginator(threadOriginator);
      }
    }

    // this indicates an audio message was kept by the recipient
    // run this every time more messages are loaded just in case
    for (Message m in struct.messages.where((e) => e.itemType == 5 && e.subject != null)) {
      final otherMessage = struct.getMessage(m.subject!);
      if (otherMessage != null) {
        final otherMwc = getMessageStateIfExists(m.subject!) ?? getOrCreateState(otherMessage);
        otherMwc.audioWasKept.value = m.dateCreated;
      }
    }

    isFetching = false;
    messagesLoaded = true;
    return _messages.isNotEmpty;
  }

  Future<void> loadSearchChunk(Message around, SearchMethod method) async {
    isFetching = true;
    List<Message> _messages = [];
    if (method == SearchMethod.local) {
      _messages = await Chat.getMessagesAsync(chat, searchAround: around.dateCreated!.millisecondsSinceEpoch);
      _messages.add(around);
      _messages.sort(Message.sort);
      struct.addMessages(_messages);
      // Create MessageStates for loaded messages
      _ensureMessageStates(_messages);
    } else {
      final beforeResponse = await ChatsSvc.getMessages(
        chat.guid,
        limit: 25,
        before: around.dateCreated!.millisecondsSinceEpoch,
      );
      final afterResponse = await ChatsSvc.getMessages(
        chat.guid,
        limit: 25,
        sort: "ASC",
        after: around.dateCreated!.millisecondsSinceEpoch,
      );
      beforeResponse.addAll(afterResponse);
      _messages = beforeResponse.map((e) => Message.fromMap(e)).toList();
      _messages.sort(Message.sort);
      struct.addMessages(_messages);
      // Create MessageStates for loaded messages
      _ensureMessageStates(_messages);
    }
    isFetching = false;
  }

  static Future<List<dynamic>> getMessages(
      {bool withChats = false,
      bool withAttachments = false,
      bool withHandles = false,
      bool withChatParticipants = false,
      List<dynamic> where = const [],
      String sort = "DESC",
      int? before,
      int? after,
      String? chatGuid,
      int offset = 0,
      int limit = 100}) async {
    Completer<List<dynamic>> completer = Completer();
    final withQuery = <String>["attributedBody", "messageSummaryInfo", "payloadData"];
    if (withChats) withQuery.add("chat");
    if (withAttachments) withQuery.add("attachment");
    if (withHandles) withQuery.add("handle");
    if (withChatParticipants) withQuery.add("chat.participants");
    withQuery.add("attachment.metadata");

    HttpSvc.messages(
            withQuery: withQuery,
            where: where,
            sort: sort,
            before: before,
            after: after,
            chatGuid: chatGuid,
            offset: offset,
            limit: limit)
        .then((response) {
      if (!completer.isCompleted) completer.complete(response.data["data"]);
    }).catchError((err) {
      late final dynamic error;
      if (err is Response) {
        error = err.data["error"]["message"];
      } else {
        error = err?.toString();
      }
      if (!completer.isCompleted) completer.completeError(error ?? "");
    });

    return completer.future;
  }
}
