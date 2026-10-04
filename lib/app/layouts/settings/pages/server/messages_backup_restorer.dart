import 'dart:async';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey;
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:universal_io/io.dart';

/// Counts from one restore run, for the summary shown to the user and the log.
class MessagesRestoreReport {
  int chats = 0;
  int chatErrors = 0;
  int messages = 0;
  int messageErrors = 0;
  int orphanMessages = 0;
  int attachments = 0;
  int attachmentErrors = 0;
  int attachmentFiles = 0;
  int handles = 0;

  bool get hadErrors => chatErrors + messageErrors + attachmentErrors > 0;

  @override
  String toString() =>
      "chats=$chats (errors $chatErrors), handles=$handles, messages=$messages (errors $messageErrors, "
      "orphans $orphanMessages), attachments=$attachments (errors $attachmentErrors, files $attachmentFiles)";
}

/// Rebuilds the local chat database from the JSON half of an OpenBubbles chats
/// backup plus the attachment blobs that were carried alongside it.
///
/// Why this exists instead of the few loops that used to live in the panel:
///
/// * Handles kept their old ObjectBox IDs. ObjectBox refuses a put whose ID is
///   above its internal sequence, so on a fresh install (the normal reason to
///   restore) the very first chat save threw and the whole restore ended in
///   "Something went wrong". Handles are now re-created by address + service
///   and messages are linked to the re-created handle.
/// * `Message.fromMap` no longer hydrates `dbAttachments`, so attachments were
///   written with no message relation and never showed up in a conversation.
///   The owning message is now looked up through the backup's message maps.
/// * One bad record aborted everything. Errors are now counted per record and
///   the rest of the backup still comes through.
/// * The chat list needs each chat's latest message to sort and preview; that
///   relation is rebuilt once the messages are in.
class MessagesBackupRestorer {
  /// [files] are the attachment blobs in the order they appear in the backup;
  /// index `bytes_id` on an attachment map points into it. Files are moved
  /// into place, so the list is consumed.
  static Future<MessagesRestoreReport> restore(
    Map<dynamic, dynamic> json,
    List<File> files, {
    void Function(String status)? onProgress,
  }) async {
    final report = MessagesRestoreReport();
    final List chatMaps = (json["chats"] as List?) ?? const [];
    final List msgMaps = (json["messages"] as List?) ?? const [];
    final List attMaps = (json["atts"] as List?) ?? const [];

    void progress(String s) {
      onProgress?.call(s);
    }

    // Everything the backup replaces. Handles are rebuilt from the chats and
    // messages below so stale rows never collide with re-created ones.
    Database.chats.removeAll();
    Database.handles.removeAll();
    Database.messages.removeAll();
    Database.attachments.removeAll();

    // address/service -> the one saved handle for it
    final Map<String, Handle> handleCache = {};
    Handle resolveHandle(Handle h) {
      final key = "${h.address}/${h.service}";
      final cached = handleCache[key];
      if (cached != null) return cached;
      Handle? existing = Handle.findOne(addressAndService: HandleLookupKey(h.address, h.service));
      if (existing == null) {
        h.id = null; // never reuse an ID from another database
        existing = h.save();
        report.handles++;
      }
      handleCache[key] = existing;
      return existing;
    }

    // ---- chats ----
    final Map<String, Chat> chatsByGuid = {};
    for (int i = 0; i < chatMaps.length; i++) {
      try {
        final Map<String, dynamic> map = Map<String, dynamic>.from(chatMaps[i] as Map);
        final chat = Chat.fromMap(map);
        chat.id = null;
        chat.participants = chat.participants.map(resolveHandle).toList();
        chat.save();
        chatsByGuid[chat.guid] = chat;
        report.chats++;
      } catch (e, s) {
        report.chatErrors++;
        Logger.error("Restore: failed to import chat ${_guidOf(chatMaps[i])}", error: e, trace: s);
      }
      if (i % 50 == 0) {
        progress("Chats ${i + 1} of ${chatMaps.length}");
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ---- messages ----
    // attachment guid -> owning message guid, from the message maps' embedded attachment lists
    final Map<String, String> attachmentOwner = {};
    for (final m in msgMaps) {
      final atts = (m as Map)["attachments"];
      if (atts is! List) continue;
      for (final a in atts) {
        final g = (a as Map?)?["guid"];
        final mg = m["guid"];
        if (g is String && mg is String) attachmentOwner[g] = mg;
      }
    }

    for (int i = 0; i < msgMaps.length; i++) {
      try {
        final Map<String, dynamic> map = Map<String, dynamic>.from(msgMaps[i] as Map);
        final msg = Message.fromMap(map);
        msg.id = null;
        final chatGuid = map["chat"];
        final Chat? chat = chatGuid is String ? (chatsByGuid[chatGuid] ?? Chat.findOne(guid: chatGuid)) : null;
        if (chat == null) report.orphanMessages++;
        if (msg.handle != null) {
          final h = resolveHandle(msg.handle!);
          msg.handle = h;
          msg.handleRelation.target = h;
        }
        msg.save(chat: chat);
        report.messages++;
      } catch (e, s) {
        report.messageErrors++;
        Logger.error("Restore: failed to import message ${_guidOf(msgMaps[i])}", error: e, trace: s);
      }
      if (i % 200 == 0) {
        progress("Messages ${i + 1} of ${msgMaps.length}");
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ---- attachments ----
    for (int i = 0; i < attMaps.length; i++) {
      try {
        final Map<String, dynamic> map = Map<String, dynamic>.from(attMaps[i] as Map);
        final att = Attachment.fromMap(map);
        att.id = null;
        final ownerGuid = att.guid == null ? null : attachmentOwner[att.guid!];
        final Message? owner = ownerGuid == null ? null : Message.findOne(guid: ownerGuid);
        if (owner != null) att.message.target = owner;

        final bytesId = map["bytes_id"];
        if (bytesId is int && bytesId >= 0 && bytesId < files.length) {
          final dest = File(att.path);
          await dest.parent.create(recursive: true);
          try {
            await files[bytesId].rename(dest.path);
          } on FileSystemException {
            // rename can fail across mount points; fall back to copy + delete
            await files[bytesId].copy(dest.path);
            await files[bytesId].delete();
          }
          report.attachmentFiles++;
        }
        att.id = Database.attachments.put(att);
        report.attachments++;
      } catch (e, s) {
        report.attachmentErrors++;
        Logger.error("Restore: failed to import attachment ${_guidOf(attMaps[i])}", error: e, trace: s);
      }
      if (i % 100 == 0) {
        progress("Attachments ${i + 1} of ${attMaps.length}");
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ---- latest message per chat, then hand the chats to the chat list ----
    progress("Finishing up");
    int n = 0;
    for (final chat in chatsByGuid.values) {
      try {
        final latest = _latestMessage(chat);
        if (latest != null) {
          chat.dbLatestMessage.target = latest;
          chat.dbOnlyLatestMessageDate = latest.dateCreated;
          chat.save(updateLatestMessage: true);
        }
        await ChatsSvc.addChat(chat);
      } catch (e, s) {
        Logger.error("Restore: failed to finalize chat ${chat.guid}", error: e, trace: s);
      }
      if (++n % 50 == 0) await Future<void>.delayed(Duration.zero);
    }

    Logger.info("Restore finished: $report");
    return report;
  }

  static Message? _latestMessage(Chat chat) {
    if (chat.id == null) return null;
    final query = (Database.messages.query(Message_.chat.equals(chat.id!))
          ..order(Message_.dateCreated, flags: Order.descending))
        .build();
    query.limit = 1;
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  static String _guidOf(dynamic map) => map is Map ? "${map["guid"]}" : "?";
}
