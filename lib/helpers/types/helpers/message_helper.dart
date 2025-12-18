import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/backend/interfaces/message_interface.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class MessageHelper {
  static Future<List<Message>> bulkAddMessages(Chat? chat, List<dynamic> messages,
      {bool checkForLatestMessageText = true, Function(int progress, int length)? onProgress}) async {
    // Convert messages to map format for the interface
    final messagesData = messages.map((item) => item as Map<String, dynamic>).toList();
    final chatData = chat?.toMap();

    // Track progress on the UI thread
    int processedCount = 0;
    final totalCount = messages.length;
    
    // Report initial progress
    if (onProgress != null) {
      onProgress(processedCount, totalCount);
    }

    // Offload the heavy work to the isolate via the interface
    // This processes messages in batches, handles DB operations, etc.
    Logger.info('Starting bulk add of $totalCount messages via isolate', tag: "BulkIngest");
    
    try {
      final results = await MessageInterface.bulkAddMessages(
        chatData: chatData,
        messagesData: messagesData,
        checkForLatestMessageText: checkForLatestMessageText,
      );

      // Report completion
      if (onProgress != null) {
        onProgress(totalCount, totalCount);
      }
      
      Logger.info('Completed bulk add of ${results.length} messages', tag: "BulkIngest");
      return results;
    } catch (ex, stacktrace) {
      Logger.error('Failed to bulk add messages', error: ex, trace: stacktrace, tag: "BulkIngest");
      rethrow;
    }
  }

  static Future<void> handleNotification(Message message, Chat chat, {bool findExisting = true}) async {
    // if from me
    if (message.isFromMe! || message.handle == null) return;
    // if it is a "kept audio" message
    if (message.itemType == 5 && message.subject != null) return;
    // See if there is an existing message for the given GUID
    if (findExisting && Message.findOne(guid: message.guid) != null) return;
    // if needing to mute
    if (chat.shouldMuteNotification(message)) return;
    // if the chat is active
    if (LifecycleSvc.isAlive && cm.isChatActive(chat.guid)) return;
    // if app is alive, on chat list, but notifying on chat list is disabled
    if (LifecycleSvc.isAlive && cm.activeChat == null && Get.rawRoute?.settings.name == "/" && !SettingsSvc.settings.notifyOnChatList.value) return;
    await NotificationsSvc.createNotification(chat, message);
  }

  static String getNotificationText(Message message, {bool withSender = false}) {
    if (message.isGroupEvent) return message.groupEventText;
    if (message.expressiveSendStyleId == "com.apple.MobileSMS.expressivesend.invisibleink") {
      return "Message sent with Invisible Ink";
    }
    if (kIsWeb && !message.isFromMe! && message.handle == null) {
      message.handle = message.getHandle();
    }
    String sender = !withSender ? "" : "${message.isFromMe! ? "You: " : (message.handle?.displayName ?? "Someone")}: ";

    if (message.isInteractive) {
      return "$sender${message.interactiveText}";
    }
    if (isNullOrEmpty(message.fullText) && !message.hasAttachments && isNullOrEmpty(message.associatedMessageGuid)) {
      if (message.dateEdited != null) {
        return "${sender}Unsent message";
      }
      return "${sender}Empty message";
    }
    if (message.hasAttachments && message.attachments.isEmpty) {
      message.fetchAttachments();
    }

    // If there are attachments, return the number of attachments
    if (message.realAttachments.isNotEmpty) {
      int aCount = message.realAttachments.length;
      // Build the attachment output by counting the attachments
      String output = "Attachment${aCount > 1 ? "s" : ""}";
      return "$output: ${_getAttachmentText(message.realAttachments)}";
    } else if (!isNullOrEmpty(message.associatedMessageGuid)) {
      // It's a reaction message, get the sender
      String sender = message.isFromMe! ? 'You' : (message.handle?.displayName ?? "Someone");
      // fetch the associated message object
      Message? associatedMessage = Message.findOne(guid: message.associatedMessageGuid);
      if (associatedMessage != null) {
        // grab the verb we'll use from the reactionToVerb map
        String? verb = ReactionTypes.reactionToVerb[message.associatedMessageType];
        // we need to check balloonBundleId first because for some reason
        // game pigeon messages have the text "�"
        if (associatedMessage.isInteractive) {
          return "$sender $verb ${message.interactiveText}";
          // now we check if theres a subject or text and construct out message based off that
        } else if (associatedMessage.expressiveSendStyleId == "com.apple.MobileSMS.expressivesend.invisibleink") {
          return "$sender $verb a message with Invisible Ink";
        } else {
          String? messageText;
          bool attachment = false;
          if (message.associatedMessagePart != null && associatedMessage.attributedBody.firstOrNull != null) {
            final attrBod = associatedMessage.attributedBody.first;
            final ranges = attrBod.runs.where((e) => e.attributes?.messagePart == message.associatedMessagePart).map((e) => e.range).sorted((a, b) => a.first.compareTo(b.first));
            final attachmentGuids = attrBod.runs.where((e) => e.attributes?.messagePart == message.associatedMessagePart && e.attributes?.attachmentGuid != null)
                .map((e) => e.attributes?.attachmentGuid).toSet();
            if (attachmentGuids.isNotEmpty) {
              attachment = true;
              messageText = _getAttachmentText(associatedMessage.fetchAttachments()!.where((e) => attachmentGuids.contains(e?.guid)).toList());
            } else if (ranges.isNotEmpty) {
              messageText = "";
              for (List range in ranges) {
                final substring = attrBod.string.substring(range.first, range.first + range.last);
                messageText = messageText! + substring;
              }
            }
          }
          // fallback
          if (messageText == null) {
            if (associatedMessage.hasAttachments) {
              attachment = true;
              messageText = _getAttachmentText(associatedMessage.fetchAttachments()!);
            } else {
              messageText = (associatedMessage.subject ?? "")
                + (!isNullOrEmpty(associatedMessage.subject?.trim()) ? "\n" : "")
                + (associatedMessage.text ?? "");
            }
          }
          return '$sender $verb ${attachment ? "" : "“"}$messageText${attachment ? "" : "”"}';
        }
      }
      // if we can't fetch the associated message for some reason
      // (or none of the above conditions about it are true)
      // then we should fallback to unparsed reaction messages
      Logger.info("Couldn't fetch associated message for message: ${message.guid}");
      return "$sender ${message.text}";
    } else {
      // It's all other message types
      return sender + message.fullText;
    }
  }

  // returns the attachments as a string
  static String _getAttachmentText(List<Attachment?> attachments) {
    Map<String, int> counts = {};
    for (Attachment? attachment in attachments) {
      String? mime = attachment!.mimeType;
      String key;
      if (mime == null) {
        key = "link";
      } else if (mime.contains("vcard")) {
        key = "contact card";
      } else if (mime.contains("location")) {
        key = "location";
      } else if (mime.contains("contact")) {
        key = "contact";
      } else if (mime.contains("video")) {
        key = "movie";
      } else if (mime.contains("image/gif")) {
        key = "GIF";
      } else if (mime.contains("application/pdf")) {
        key = "PDF";
      } else {
        key = mime.split("/").first;
      }

      int current = counts.containsKey(key) ? counts[key]! : 0;
      counts[key] = current + 1;
      // a message can only ever have 1 link (but multiple "attachments", so we break out)
      if (key == "link") break;
    }

    List<String> attachmentStr = [];
    counts.forEach((key, value) {
      attachmentStr.add("$value $key${value > 1 ? "s" : ""}");
    });
    return attachmentStr.join(attachmentStr.length == 2 ? " & " : ", ");
  }

  /// Removes duplicate associated message guids from a list of [associatedMessages]
  static List<Message> normalizedAssociatedMessages(List<Message> associatedMessages) {
    Set<String> guids = associatedMessages.map((e) => e.guid!).toSet();
    List<Message> normalized = [];

    for (Message message in associatedMessages.reversed.toList()) {
      if (!ReactionTypes.toList().contains(message.associatedMessageType)) {
        normalized.add(message);
      } else if (guids.remove(message.guid)) {
        normalized.add(message);
      }
    }
    return normalized;
  }

  static bool shouldShowBigEmoji(String text) {
    if (isNullOrEmptyString(text)) return false;
    if (text.codeUnits.length == 1 && text.codeUnits.first == 9786) return true;

    final darkSunglasses = RegExp('\u{1F576}');
    if (emojiRegex.firstMatch(text) == null && !text.contains(darkSunglasses)) return false;

    List<RegExpMatch> matches = emojiRegex.allMatches(text).toList();
    List<String> items = matches.map((m) => m.toString()).toList();

    String replaced = text.replaceAll(emojiRegex, "").replaceAll(String.fromCharCode(65039), "").replaceAll(darkSunglasses, "").trim();
    return items.length <= 3 && replaced.isEmpty;
  }

  static List<TextSpan> buildEmojiText(String text, TextStyle style, {TapGestureRecognizer? recognizer}) {
    if (!FilesystemSvc.fontExistsOnDisk.value) {
      return [
        TextSpan(
          text: text,
          style: style,
          recognizer: recognizer,
        )
      ];
    }

    RegExp _emojiRegex = RegExp("${emojiRegex.pattern}|\u{1F576}");
    List<RegExpMatch> matches = _emojiRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return [
        TextSpan(
          text: text,
          style: style,
          recognizer: recognizer,
        )
      ];
    }

    final children = <TextSpan>[];
    int previousEnd = 0;
    for (int i = 0; i < matches.length; i++) {
      // Before the emoji
      if (previousEnd <= matches[i].start) {
        String chunk = text.substring(previousEnd, matches[i].start);
        children.add(
          TextSpan(
            text: chunk,
            style: style,
            recognizer: recognizer,
          ),
        );
        previousEnd += chunk.length;
      }

      // The emoji
      String chunk = text.substring(matches[i].start, matches[i].end);

      // Add stringed emoji
      while (i + 1 < matches.length && matches[i + 1].start == matches[i].end) {
        chunk += text.substring(matches[++i].start, matches[i].end);
      }
      children.add(
        TextSpan(
          text: chunk,
          style: style.apply(fontFamily: "Apple Color Emoji"),
          recognizer: recognizer,
        ),
      );
      previousEnd += chunk.length;
    }
    if (previousEnd < text.length) {
      children.add(
        TextSpan(
          text: text.substring(previousEnd),
          style: style,
          recognizer: recognizer,
        )
      );
    }

    return children;
  }
}
