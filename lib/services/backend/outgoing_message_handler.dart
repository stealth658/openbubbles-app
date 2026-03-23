import 'dart:async';
import 'dart:collection';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/file_utils.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';

// ─── Singleton accessor ───────────────────────────────────────────────────────

const _tag = 'OutgoingMessageHandler';

// ignore: non_constant_identifier_names
OutgoingMessageHandler get OutgoingMsgHandler => GetIt.I<OutgoingMessageHandler>();

// ─── Internal queue entry ─────────────────────────────────────────────────────

class _OutgoingEntry {
  final OutgoingItem item;

  _OutgoingEntry(this.item);
}

// ─── Handler ─────────────────────────────────────────────────────────────────

/// Processes all outgoing message events — text, multipart, and attachments.
///
/// ## Responsibilities
///
/// 1. **Serial send queue** — all sends are queued and processed one at a time
///    so messages always arrive in the order the user sent them.
///
/// 2. **Pre-send preparation** — `prepMessage` / `prepAttachment` write the
///    temp message/attachment to the DB and the MessagesService *before* the
///    HTTP call is made, so the UI shows the outgoing bubble immediately.
///
/// 3. **GUID replacement** — when the HTTP response arrives with the server's
///    real GUID, replaces the temp record in the DB and notifies [MessagesService]
///    so the bubble transitions from the temp ID to the permanent one.
///
/// 4. **Send-progress coordination** — exposes [completeSendProgressIfExists]
///    so [IncomingMessageHandler] can complete a send-progress tracker early
///    when a socket event for our own message arrives before the HTTP response.
///
/// 5. **Error marking** — failed sends update the message's GUID and error code
///    so the UI can show a retry/error badge.
class OutgoingMessageHandler {
  // ── Attachment upload progress ───────────────────────────────────────────

  /// Observable list of (attachmentGuid, uploadProgress) pairs.
  /// Read by [AttachmentsService] to drive progress indicators in the UI.
  final RxList<Tuple2<String, RxDouble>> attachmentProgress = <Tuple2<String, RxDouble>>[].obs;

  /// The active [CancelToken] for the most-recently-started attachment upload.
  /// The UI cancels this when the user presses the cancel button in the
  /// attachment bubble.
  CancelToken? latestCancelToken;

  // ── Send-progress trackers ───────────────────────────────────────────────

  /// tempGuid → (Chat, Completer) for the in-flight send futures.
  ///
  /// Allows [IncomingMessageHandler] to complete a send early when a socket
  /// event echoing our own message arrives before the HTTP response.
  final Map<String, Tuple2<Chat, Completer<void>>> _sendProgressTrackers = {};

  /// Registers a tracker so that [completeSendProgressIfExists] can complete
  /// [completer] and update [chat.sendProgress] if the socket event wins the
  /// HTTP vs. socket race.
  void registerSendProgressTracker(String tempGuid, Chat chat, Completer<void> completer) {
    _sendProgressTrackers[tempGuid] = Tuple2(chat, completer);
    Logger.debug('Registered send-progress tracker for $tempGuid', tag: _tag);
  }

  /// Called by [IncomingMessageHandler] when it receives a socket event for a
  /// message we just sent (i.e. [tempGuid] is in the tracker map).
  ///
  /// Completes the registered completer early and drives the progress
  /// animation to its final state so the UI doesn't wait for the HTTP
  /// response.
  void completeSendProgressIfExists(String tempGuid, Origin origin) {
    final tracker = _sendProgressTrackers.remove(tempGuid);
    if (tracker == null) return;

    if (origin == Origin.incomingMessageHandler) {
      Logger.debug('Server event arrived before HTTP response for $tempGuid — completing send progress early', tag: _tag);
    } else if (origin == Origin.outgoingMessageHandler) {
      Logger.debug('Outgoing send request returned before server event for $tempGuid — completing send progress', tag: _tag);
    } else {
      Logger.warn('Unknown origin $origin for send progress completion of $tempGuid', tag: _tag);
    }

    final chat = tracker.item1;
    final completer = tracker.item2;
    if (chat.sendProgress.value != 0) {
      chat.sendProgress.value = 1;
      Timer(const Duration(milliseconds: 500), () {
        chat.sendProgress.value = 0;
      });
    }
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  // ── Serial outgoing queue ────────────────────────────────────────────────

  final Queue<_OutgoingEntry> _queue = Queue();
  bool _isProcessing = false;

  /// Enqueues [item] for sending.  Preparation (DB write / file copy) is
  /// performed synchronously before the item enters the queue, so the
  /// outgoing bubble appears in the UI immediately.  The actual HTTP call
  /// happens when the queue reaches this item.
  ///
  /// Returns a [Future] that completes (or errors) when the item's
  /// [OutgoingItem.completer] resolves — i.e. when the HTTP response arrives
  /// or an error is surfaced.
  Future<void> queue(OutgoingItem item) async {
    Logger.debug(
      '[queue] Enqueueing type=${item.type.name} chat=${item.chat.guid} guid=${item.message.guid}',
      tag: _tag,
    );
    // Prepare items (writes temp messages / copies attachment files to disk).
    // prepMessage may return multiple Message objects when it splits a URL
    // message into two parts (pre-Big Sur macOS compatibility).
    final returned = await _prepItem(item);

    if (returned is List<Message>) {
      // prepMessage already saved each message to the DB; create a queue
      // entry for each one with the message that was actually saved.
      Logger.debug('[queue] prepMessage returned ${(returned as List).length} message(s)', tag: _tag);
      for (final m in returned) {
        Logger.debug('[queue] enqueueing message guid=${m.guid}', tag: _tag);
        _queue.add(_OutgoingEntry(OutgoingItem(
          type: item.type,
          chat: item.chat,
          message: m,
          completer: item.completer,
          selected: item.selected,
          reaction: item.reaction,
          customArgs: item.customArgs,
        )));
      }
    } else {
      // Attachment: prepAttachment already saved it; keep the original item.
      Logger.debug('[queue] attachment item enqueued guid=${item.message.guid}', tag: _tag);
      _queue.add(_OutgoingEntry(item));
    }

    unawaited(_processNext());
  }

  Future<void> _processNext() async {
    if (_isProcessing) return;
    _isProcessing = true;
    Logger.debug('[_processNext] Starting queue processing (${_queue.length} item(s) queued)', tag: _tag);

    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      final item = entry.item;
      Logger.debug(
        '[_processNext] Processing item type=${item.type.name} guid=${item.message.guid} chat=${item.chat.guid}',
        tag: _tag,
      );

      try {
        await _handleSend(() => _dispatchItem(item), item.chat).catchError((err) async {
          if (SettingsSvc.settings.cancelQueuedMessages.value) {
            // Cancel all subsequent messages for the same chat.
            final toCancel = _queue.where((e) => e.item.chat.guid == item.chat.guid).map((e) => e.item).toList();
            for (final pending in toCancel) {
              _queue.removeWhere((e) => e.item == pending);
              final m = pending.message;
              final tempGuid = m.guid;
              m.guid = m.guid!.replaceAll('temp', 'error-Canceled due to previous failure');
              m.error = MessageError.BAD_REQUEST.code;
              await Message.replaceMessage(tempGuid, m);
            }
          }
        });
        item.completer?.complete();
      } catch (ex, st) {
        Logger.error('Failed to handle outgoing queue item', error: ex, trace: st, tag: _tag);
        item.completer?.completeError(ex);
      }
    }

    Logger.debug('[_processNext] Queue drained', tag: _tag);
    _isProcessing = false;
  }

  /// Wraps a send [process] with the send-progress animation:
  ///
  /// * A 5-second timer sets [chat.sendProgress] to 0.9 to signal a long
  ///   send.
  /// * When [process] completes (success or error), the timer is cancelled
  ///   and progress is driven to 1 → 0 (unless an early socket event already
  ///   did so via [completeSendProgressIfExists]).
  Future<T> _handleSend<T>(Future<T> Function() process, Chat chat) {
    final timer = Timer(const Duration(seconds: 5), () {
      chat.sendProgress.value = .9;
    });
    final t = process();
    void _finalize(dynamic _) {
      timer.cancel();
      if (chat.sendProgress.value != 0 && chat.sendProgress.value != 1) {
        chat.sendProgress.value = 1;
        Timer(const Duration(milliseconds: 500), () {
          chat.sendProgress.value = 0;
        });
      }
    }

    t.then(_finalize, onError: _finalize);
    return t;
  }

  /// Fires [httpCall] and races the response against the socket echo for
  /// [tempGuid].  Whichever arrives first unblocks the queue; the HTTP work
  /// (GUID replacement, error marking, etc.) still runs to completion
  /// afterwards in the background.
  ///
  /// [onSuccess] receives the decoded [Message] from the server response.
  /// [onError] receives the original error and stack-trace so the caller can
  /// mark the message as failed and persist the error state.
  /// Both callbacks are wrapped in a try/catch so an internal failure (e.g.,
  /// a transient DB write error) never leaves the queue permanently blocked.
  Future<void> _sendWithRace({
    required String tempGuid,
    required Chat chat,
    required Future<Response> Function() httpCall,
    required Future<void> Function(Message newMessage) onSuccess,
    required Future<void> Function(Object error, StackTrace stack) onError,
  }) {
    final race = Completer<void>();
    registerSendProgressTracker(tempGuid, chat, race);

    httpCall().then((response) async {
      completeSendProgressIfExists(tempGuid, Origin.outgoingMessageHandler);
      try {
        await onSuccess(Message.fromMap(response.data['data']));
      } catch (ex, st) {
        Logger.warn('Send success handler threw for $tempGuid', error: ex, trace: st, tag: _tag);
      }
      if (!race.isCompleted) race.complete();
    }, onError: (Object error, StackTrace stack) async {
      completeSendProgressIfExists(tempGuid, Origin.outgoingMessageHandler);
      try {
        await onError(error, stack);
      } catch (ex, st) {
        Logger.warn('Send error handler threw for $tempGuid', error: ex, trace: st, tag: _tag);
      }
      if (!race.isCompleted) race.completeError(error, stack);
    });

    return race.future;
  }

  Future<void> _dispatchItem(OutgoingItem item) {
    switch (item.type) {
      case QueueType.sendMessage:
        return sendMessage(item.chat, item.message, item.selected, item.reaction);
      case QueueType.sendMultipart:
        return sendMultipart(item.chat, item.message, item.selected, item.reaction);
      case QueueType.sendAttachment:
        return sendAttachment(item.chat, item.message, item.customArgs?['audio'] ?? false);
    }
  }

  // ── Preparation ──────────────────────────────────────────────────────────

  /// Prepares [item] for sending.
  ///
  /// For message/multipart sends: calls [prepMessage], which assigns a temp
  /// GUID and saves the message to the DB and MessagesService, then returns
  /// the list of [Message]s to enqueue.
  ///
  /// For attachment sends: calls [prepAttachment], which copies the file to
  /// the local attachment directory and saves the message to the DB.  Returns
  /// `null` to indicate the item itself should be enqueued without splitting.
  Future<dynamic> _prepItem(OutgoingItem item) async {
    switch (item.type) {
      case QueueType.sendMultipart:
      case QueueType.sendMessage:
        return prepMessage(
          item.chat,
          item.message,
          item.selected,
          item.reaction,
          clearNotificationsIfFromMe: !(item.customArgs?['notifReply'] ?? false),
          isRetry: item.customArgs?['isRetry'] ?? false,
        );
      case QueueType.sendAttachment:
        await prepAttachment(item.chat, item.message);
        return null;
    }
  }

  /// Prepares a text message for sending.
  ///
  /// On macOS < Big Sur, long messages containing a URL may be split into two
  /// separate messages to prevent server-side matching glitches.
  ///
  /// Each resulting message receives a temp GUID and is saved to the DB via
  /// [Chat.addMessage].  Returns the list of messages that were saved.
  Future<List<Message>> prepMessage(
    Chat c,
    Message m,
    Message? selected,
    String? r, {
    bool clearNotificationsIfFromMe = true,
    bool isRetry = false,
  }) async {
    // If it's a retry, the message should already be in the correct format
    if (isRetry) return [m];
    if ((m.text?.isEmpty ?? true) && (m.subject?.isEmpty ?? true) && r == null) return [];

    final List<Message> messages = [];

    if (!(await SettingsSvc.isMinBigSur) && r == null) {
      // Split URL messages on OS X to prevent message matching glitches.
      String mainText = m.text!;
      String? secondaryText;
      final match = parseLinks(m.text!.replaceAll('\n', ' ')).firstOrNull;
      if (match != null) {
        if (match.start == 0) {
          mainText = m.text!.substring(0, match.end).trimRight();
          secondaryText = m.text!.substring(match.end).trimLeft();
        } else if (match.end == m.text!.length) {
          mainText = m.text!.substring(0, match.start).trimRight();
          secondaryText = m.text!.substring(match.start).trimLeft();
        }
      }

      messages.add(m..text = mainText);
      if (!isNullOrEmpty(secondaryText)) {
        messages.add(Message(
          text: secondaryText,
          threadOriginatorGuid: m.threadOriginatorGuid,
          threadOriginatorPart: '${m.threadOriginatorPart ?? 0}:0:0',
          expressiveSendStyleId: m.expressiveSendStyleId,
          dateCreated: DateTime.now(),
          hasAttachments: false,
          isFromMe: true,
          handleId: 0,
        ));
      }

      for (final message in messages) {
        message.generateTempGuid();
        await c.addMessage(message, clearNotificationsIfFromMe: clearNotificationsIfFromMe);
      }
    } else {
      m.generateTempGuid();
      await c.addMessage(m, clearNotificationsIfFromMe: clearNotificationsIfFromMe);
      messages.add(m);
    }
    return messages;
  }

  /// Copies the attachment file to the local storage directory and saves the
  /// message to the DB.
  ///
  /// Attachment metadata carries the original source path so the file can be
  /// copied without loading it into memory (except GIFs, which need
  /// optimisation).
  Future<void> prepAttachment(Chat c, Message m) async {
    final attachment = m.attachments.first!;
    final progress = Tuple2(attachment.guid!, 0.0.obs);
    attachmentProgress.add(progress);

    if (!kIsWeb) {
      final sourcePath = attachment.metadata?['source_path'] as String?;
      Logger.debug(
        'prepAttachment: sourcePath=$sourcePath, hasBytes=${attachment.bytes != null}',
        tag: _tag,
      );
      if (sourcePath == null && attachment.bytes == null) {
        throw Exception('Attachment has no source_path in metadata or bytes');
      }

      final destinationPath = attachment.path;
      final destinationFile = await File(destinationPath).create(recursive: true);

      if (sourcePath != null) {
        if (attachment.mimeType == 'image/gif') {
          final bytes = await File(sourcePath).readAsBytes();
          final optimizedBytes = await fixSpeedyGifs(bytes);
          await destinationFile.writeAsBytes(optimizedBytes);
        } else {
          await File(sourcePath).copy(destinationPath);
        }
      } else {
        Uint8List bytesToWrite = attachment.bytes!;
        if (attachment.mimeType == 'image/gif') {
          bytesToWrite = await fixSpeedyGifs(bytesToWrite);
        }
        await destinationFile.writeAsBytes(bytesToWrite);
        attachment.bytes = null;
      }

      if (attachment.mimeStart == 'image') {
        try {
          await AttachmentsSvc.loadImageProperties(attachment, actualPath: destinationPath);
        } catch (ex) {
          Logger.warn('Failed to load image properties for outgoing attachment', error: ex, tag: _tag);
        }
      }

      attachment.isDownloaded = true;
    }

    Logger.debug(
      'prepAttachment: calling addMessage with attachment.guid=${attachment.guid}',
      tag: _tag,
    );
    await c.addMessage(m);
    final savedAttachment = await Attachment.findOneAsync(attachment.guid!);
    Logger.debug(
      'prepAttachment: attachment ${attachment.guid} in DB = ${savedAttachment != null}',
      tag: _tag,
    );

    // Register upload-in-progress state so the UI can react immediately.
    // Must come after addMessage so the message is in the DB.
    if (Get.isRegistered<MessagesService>(tag: c.guid)) {
      MessagesSvc(c.guid).notifyAttachmentUploadStarted(m, attachment);
      Logger.debug('prepAttachment: AttachmentState set to uploading for ${attachment.guid}', tag: _tag);
    }
  }

  // ── Send methods ─────────────────────────────────────────────────────────

  /// Sends a text message (or a reaction/tapback) to [c].
  ///
  /// For reactions ([r] != null), a temp reaction is added to the UI
  /// immediately before the HTTP call so the user sees instant feedback.
  Future<void> sendMessage(Chat c, Message m, Message? selected, String? r) {
    ChatsSvc.updateChat(c);
    ChatsSvc.updateChatLatestMessage(c.guid, m);
    final tempGuid = m.guid!;
    Logger.debug(
      '[sendMessage] START tempGuid=$tempGuid chat=${c.guid} '
      'isReaction=${r != null} selectedGuid=${selected?.guid}',
      tag: _tag,
    );

    // Add temp reaction to UI immediately for instant feedback.
    if (r != null && m.associatedMessageGuid != null) {
      final parentState = MessagesSvc(c.guid).getMessageStateIfExists(m.associatedMessageGuid!);
      parentState?.addAssociatedMessageInternal(m);
    }

    return _sendWithRace(
      tempGuid: tempGuid,
      chat: c,
      httpCall: () => r == null
          ? HttpSvc.sendMessage(
              c.guid,
              tempGuid,
              m.text!,
              subject: m.subject,
              method: (SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.settings.privateAPISend.value) ||
                      (m.subject?.isNotEmpty ?? false) ||
                      m.threadOriginatorGuid != null ||
                      m.expressiveSendStyleId != null
                  ? 'private-api'
                  : 'apple-script',
              selectedMessageGuid: m.threadOriginatorGuid,
              effectId: m.expressiveSendStyleId,
              partIndex: int.tryParse(m.threadOriginatorPart?.split(':').firstOrNull ?? ''),
              ddScan: !SettingsSvc.isMinSonomaSync && m.text!.hasUrl,
            )
          : HttpSvc.sendTapback(
              c.guid,
              selected!.text ?? '',
              selected.guid!,
              r,
              partIndex: m.associatedMessagePart,
            ),
      onSuccess: (newMessage) async {
        Logger.debug(
          r == null
              ? 'Message sent: temp=$tempGuid, real=${newMessage.guid}'
              : 'Reaction sent: temp=$tempGuid, real=${newMessage.guid}, parent=${selected?.guid}',
          tag: _tag,
        );
        await _matchMessageWithExisting(c, tempGuid, newMessage);
        if (r != null && newMessage.associatedMessageGuid != null) {
          // Update the parent message's reaction in-place once we have the real GUID.
          final parentState = MessagesSvc(c.guid).getMessageStateIfExists(newMessage.associatedMessageGuid!);
          if (parentState != null) {
            parentState.updateAssociatedMessageInternal(newMessage, tempGuid: tempGuid);
          } else {
            Logger.warn(
              'Parent MessageState not found for ${newMessage.associatedMessageGuid} when updating reaction',
              tag: _tag,
            );
          }
        }
      },
      onError: (error, stack) async {
        Logger.error(
          r == null ? 'Failed to send message' : 'Failed to send reaction',
          error: error,
          trace: stack,
          tag: _tag,
        );
        m = handleSendError(error, m);
        Logger.test('Updated message with error: error=${m.error} errorMessage=${m.errorMessage}', tag: _tag);
        if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
      },
    );
  }

  /// Sends a multipart (mention / mixed-content) message.
  Future<void> sendMultipart(Chat c, Message m, Message? selected, String? r) {
    ChatsSvc.updateChat(c);
    ChatsSvc.updateChatLatestMessage(c.guid, m);
    final tempGuid = m.guid!;
    Logger.debug('[sendMultipart] START tempGuid=$tempGuid chat=${c.guid}', tag: _tag);
    final parts = m.attributedBody.first.runs
        .map((e) => {
              'text': m.attributedBody.first.string.substring(e.range.first, e.range.first + e.range.last),
              'mention': e.attributes!.mention,
              'partIndex': e.attributes!.messagePart,
            })
        .toList();

    return _sendWithRace(
      tempGuid: tempGuid,
      chat: c,
      httpCall: () => HttpSvc.sendMultipart(
        c.guid,
        tempGuid,
        parts,
        subject: m.subject,
        selectedMessageGuid: m.threadOriginatorGuid,
        effectId: m.expressiveSendStyleId,
        partIndex: int.tryParse(m.threadOriginatorPart?.split(':').firstOrNull ?? ''),
        ddScan: !SettingsSvc.isMinSonomaSync && parts.any((e) => e['text'].toString().hasUrl),
      ),
      onSuccess: (newMessage) => _matchMessageWithExisting(c, tempGuid, newMessage),
      onError: (error, stack) async {
        Logger.error('Failed to send multipart message', error: error, trace: stack, tag: _tag);
        m = handleSendError(error, m);
        if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
      },
    );
  }

  /// Sends an attachment message.
  Future<void> sendAttachment(Chat c, Message m, bool isAudioMessage) async {
    if (m.attachments.isEmpty) return;
    final attachment = m.attachments.first!;
    // Save both GUIDs before any mutation — attachment.guid == m.guid by design
    // (set in send_animation.dart: attachment.guid = message.guid).
    final tempGuid = m.guid!;
    // The temp message was already saved to DB in prepAttachment; update ChatState
    // subtitle immediately so the tile reflects the outgoing attachment.
    ChatsSvc.updateChat(c);
    ChatsSvc.updateChatLatestMessage(c.guid, m);
    Logger.debug(
      '[sendAttachment] START tempGuid=$tempGuid chat=${c.guid} '
      'attachmentGuid=${attachment.guid} mimeType=${attachment.mimeType} '
      'isAudio=$isAudioMessage',
      tag: _tag,
    );

    Uint8List? bytes;
    if (!kIsWeb) {
      try {
        bytes = await File(attachment.path).readAsBytes();
      } catch (ex) {
        Logger.error('Failed to read attachment bytes for sending', error: ex, tag: _tag);
        return;
      }
    }
    if (bytes == null) return;

    final progress = attachmentProgress.firstWhere((e) => e.item1 == attachment.guid);
    latestCancelToken = CancelToken();
    // Capture token so the closure below uses the one created for THIS send,
    // not a later one overwritten by a concurrent (post-queue) sendAttachment.
    final cancelToken = latestCancelToken!;

    return _sendWithRace(
      tempGuid: tempGuid,
      chat: c,
      httpCall: () => HttpSvc.sendAttachment(
        c.guid,
        attachment.guid!,
        PlatformFile(
          name: attachment.transferName!,
          bytes: bytes,
          path: kIsWeb ? null : attachment.path,
          size: attachment.totalBytes ?? 0,
        ),
        onSendProgress: (count, total) {
          final uploadFraction = count / bytes!.length;
          progress.item2.value = uploadFraction;
          // Mirror upload progress into AttachmentState for reactive UI.
          if (Get.isRegistered<MessagesService>(tag: c.guid)) {
            MessagesSvc(c.guid).notifyAttachmentUploadProgress(tempGuid, attachment.guid!, uploadFraction);
          }
        },
        method: (SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.settings.privateAPIAttachmentSend.value) ||
                (m.subject?.isNotEmpty ?? false) ||
                m.threadOriginatorGuid != null ||
                m.expressiveSendStyleId != null
            ? 'private-api'
            : 'apple-script',
        selectedMessageGuid: m.threadOriginatorGuid,
        effectId: m.expressiveSendStyleId,
        partIndex: int.tryParse(m.threadOriginatorPart?.split(':').firstOrNull ?? ''),
        isAudioMessage: isAudioMessage,
        cancelToken: cancelToken,
      ),
      onSuccess: (newMessage) async {
        latestCancelToken = null;
        // Swap attachment GUIDs first, then swap the message GUID.
        for (final a in newMessage.attachments) {
          if (a == null) continue;
          try {
            await _matchAttachmentWithExisting(c, tempGuid, a);
            // Complete the attachment state.  We pass both the temp and real
            // message GUIDs because the socket event may have already moved
            // the MessageState to the real key before the HTTP response arrived.
            // The state key is intentionally left at the temp attachment GUID
            // so the Obx can still find it; _syncAttachmentStates promotes it
            // to the real key when updateMessage delivers the updated struct.
            if (Get.isRegistered<MessagesService>(tag: c.guid)) {
              MessagesSvc(c.guid).notifyAttachmentSendComplete(tempGuid, newMessage.guid!, tempGuid, a);
            }
            MessagesSvc(c.guid).updateMessage(newMessage);
          } catch (e, st) {
            Logger.warn('Failed to replace attachment ${a.guid}', error: e, trace: st, tag: _tag);
          }
        }
        await _matchMessageWithExisting(c, tempGuid, newMessage);
        attachmentProgress.removeWhere((e) => e.item1 == tempGuid);
      },
      onError: (error, stack) async {
        latestCancelToken = null;
        Logger.error('Failed to send attachment', error: error, trace: stack, tag: _tag);
        m = handleSendError(error, m);
        if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
        // Mark attachment as errored so the UI shows a retry option.
        if (Get.isRegistered<MessagesService>(tag: c.guid)) {
          MessagesSvc(c.guid).notifyAttachmentTransferError(tempGuid, attachment.guid!);
        }
        // Use the saved tempGuid — m.guid is now the error GUID after handleSendError.
        attachmentProgress.removeWhere((e) => e.item1 == tempGuid);
      },
    );
  }

  // ── DB helpers ──────────────────────────────────────────────────────────

  /// Replaces the temp message record ([existingGuid]) with [replacement] in
  /// the DB and notifies [MessagesService] so the UI bubble transitions.
  ///
  /// Handles the parallel-delivery race where [IncomingMessageHandler] may
  /// have already processed the socket echo:
  ///
  /// * If [replacement.guid] is already in the DB (socket beat HTTP): update
  ///   the existing record if [replacement] is newer, clean up the stale temp,
  ///   and update the controller.
  /// * Otherwise: call [Message.replaceMessage] to rename the temp record to
  ///   the real GUID.
  Future<void> _matchMessageWithExisting(
    Chat chat,
    String existingGuid,
    Message replacement,
  ) async {
    Logger.debug(
      '[_matchMessageWithExisting] START existingGuid=$existingGuid → replacementGuid=${replacement.guid} chat=${chat.guid}',
      tag: _tag,
    );

    final alreadyPresent = Message.findOne(guid: replacement.guid);
    Logger.debug(
      '[_matchMessageWithExisting] alreadyPresent check for ${replacement.guid} → found=${alreadyPresent != null} (id=${alreadyPresent?.id})',
      tag: _tag,
    );

    if (alreadyPresent != null) {
      // Socket event won the race — real GUID is already in the DB.
      final isNewer = replacement.isNewerThan(alreadyPresent);
      Logger.debug(
        '[_matchMessageWithExisting] parallel-delivery: isNewerThan=$isNewer',
        tag: _tag,
      );
      if (isNewer) {
        Logger.debug('[_matchMessageWithExisting] overwriting with newer replacement ${replacement.guid}', tag: _tag);
        await Message.replaceMessage(replacement.guid, replacement);
      }

      // Clean up the stale temp record if it's distinct from the real one.
      if (existingGuid != replacement.guid) {
        final stale = Message.findOne(guid: existingGuid);
        Logger.debug(
          '[_matchMessageWithExisting] stale cleanup: existingGuid=$existingGuid staleFound=${stale != null}',
          tag: _tag,
        );
        if (stale != null) {
          Logger.debug('[_matchMessageWithExisting] deleting stale record $existingGuid', tag: _tag);
          Message.delete(stale.guid!);
          if (Get.isRegistered<MessagesService>(tag: chat.guid)) {
            Logger.debug(
              '[_matchMessageWithExisting] calling updateMessage oldGuid=$existingGuid → ${replacement.guid}',
              tag: _tag,
            );
            MessagesSvc(chat.guid).updateMessage(replacement, oldGuid: existingGuid);
          }
        }
      } else {
        Logger.debug('[_matchMessageWithExisting] existingGuid == replacementGuid — no stale cleanup needed',
            tag: _tag);
      }
    } else {
      // Normal path: rename the temp record to the real GUID.
      Logger.debug(
        '[_matchMessageWithExisting] normal path: replaceMessage $existingGuid → ${replacement.guid}',
        tag: _tag,
      );
      try {
        await Message.replaceMessage(existingGuid, replacement);
        Logger.debug('[_matchMessageWithExisting] replaceMessage succeeded: $existingGuid → ${replacement.guid}',
            tag: _tag);
        if (Get.isRegistered<MessagesService>(tag: chat.guid)) {
          Logger.debug(
            '[_matchMessageWithExisting] calling updateMessage oldGuid=$existingGuid → ${replacement.guid}',
            tag: _tag,
          );
          MessagesSvc(chat.guid).updateMessage(replacement, oldGuid: existingGuid);
        }
      } catch (ex, st) {
        Logger.warn(
          '[_matchMessageWithExisting] FAILED: Unable to find & replace message with GUID $existingGuid',
          error: ex,
          trace: st,
          tag: _tag,
        );
      }
    }
  }

  /// Swaps a temp attachment GUID for the real one after the server confirms
  /// the upload.
  Future<void> _matchAttachmentWithExisting(
    Chat chat,
    String existingGuid,
    Attachment replacement,
  ) async {
    Logger.debug(
      '[_matchAttachmentWithExisting] START existingGuid=$existingGuid → replacementGuid=${replacement.guid} chat=${chat.guid}',
      tag: _tag,
    );

    final alreadyPresent = await Attachment.findOneAsync(replacement.guid!);
    Logger.debug(
      '[_matchAttachmentWithExisting] alreadyPresent check for ${replacement.guid} → found=${alreadyPresent != null}',
      tag: _tag,
    );
    if (alreadyPresent != null) {
      Logger.debug('[_matchAttachmentWithExisting] parallel-delivery: updating ${replacement.guid} in place',
          tag: _tag);
      await Attachment.replaceAttachmentAsync(replacement.guid, replacement);
      if (existingGuid != replacement.guid) {
        final stale = await Attachment.findOneAsync(existingGuid);
        Logger.debug(
          '[_matchAttachmentWithExisting] stale cleanup: $existingGuid staleFound=${stale != null}',
          tag: _tag,
        );
        if (stale != null) {
          Logger.debug('[_matchAttachmentWithExisting] deleting stale attachment $existingGuid', tag: _tag);
          await Attachment.deleteAsync(stale.guid!);
        }
      } else {
        Logger.debug('[_matchAttachmentWithExisting] existingGuid == replacementGuid — no stale cleanup needed',
            tag: _tag);
      }
    } else {
      Logger.debug(
        '[_matchAttachmentWithExisting] normal path: replaceAttachmentAsync $existingGuid → ${replacement.guid}',
        tag: _tag,
      );
      try {
        await Attachment.replaceAttachmentAsync(existingGuid, replacement);
        Logger.debug(
          '[_matchAttachmentWithExisting] replaceAttachmentAsync succeeded: $existingGuid → ${replacement.guid}',
          tag: _tag,
        );
      } catch (ex) {
        Logger.warn(
          '[_matchAttachmentWithExisting] FAILED: Unable to find & replace attachment with GUID $existingGuid',
          error: ex,
          tag: _tag,
        );
      }
    }

    Logger.debug('[_matchAttachmentWithExisting] END existingGuid=$existingGuid → ${replacement.guid}', tag: _tag);

    // Move the file directory from the temp-GUID path to the real-GUID path so that
    // getContent finds the local file immediately without triggering a server download.
    if (!kIsWeb && existingGuid != replacement.guid && existingGuid.startsWith('temp')) {
      try {
        final oldDir = Directory('${Attachment.baseDirectory}/$existingGuid');
        final newDir = Directory(replacement.directory);
        if (oldDir.existsSync() && !newDir.existsSync()) {
          oldDir.renameSync(newDir.path);
          Logger.debug(
            '[_matchAttachmentWithExisting] moved attachment dir $existingGuid → ${replacement.guid}',
            tag: _tag,
          );
        }
      } catch (ex) {
        Logger.warn(
          '[_matchAttachmentWithExisting] failed to move attachment dir $existingGuid → ${replacement.guid}',
          error: ex,
          tag: _tag,
        );
      }
    }
  }

  // ── Service lifecycle ────────────────────────────────────────────────────

  /// Cancels pending progress timers and fails any queued items.
  ///
  /// Called by GetIt when the singleton is unregistered.
  void dispose() {
    latestCancelToken?.cancel('OutgoingMessageHandler disposed');
    latestCancelToken = null;
    _sendProgressTrackers.clear();
    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      entry.item.completer?.completeError(
        StateError('OutgoingMessageHandler disposed before item was processed'),
      );
    }
    _isProcessing = false;
  }
}
