import 'dart:async';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

MessageWidgetController mwc(Message message) => Get.isRegistered<MessageWidgetController>(tag: message.guid)
    ? Get.find<MessageWidgetController>(tag: message.guid)
    : Get.put(MessageWidgetController(message), tag: message.guid);

MessageWidgetController? getActiveMwc(String guid) =>
    Get.isRegistered<MessageWidgetController>(tag: guid) ? Get.find<MessageWidgetController>(tag: guid) : null;

class MessageWidgetController extends StatefulController with GetSingleTickerProviderStateMixin {
  final RxBool showEdits = false.obs;
  final Rxn<DateTime> audioWasKept = Rxn<DateTime>(null);

  List<MessagePart> parts = [];
  Message message;
  String? oldMessageGuid;
  String? newMessageGuid;
  ConversationViewController? cvController;
  late final String tag;
  late final StreamSubscription? sub;
  bool built = false;

  static const maxBubbleSizeFactor = 0.75;
  
  /// Granular update flags to minimize re-renders
  /// Only triggers rebuilds for specific components that need updating
  /// 
  /// - deliveryStatusChanged: Triggers only DeliveredIndicator updates (read/delivered status)
  /// - reactionsChanged: Triggers only ReactionHolder updates when reactions added/removed
  /// - contentChanged: Triggers full message rebuild when text/edits/parts change
  /// - threadRepliesChanged: Triggers only MessageProperties when reply count changes
  /// - errorStateChanged: Triggers only error icon when error status changes
  /// 
  /// This avoids unnecessary full MessageHolder rebuilds which cause scrolling jank
  final RxBool deliveryStatusChanged = false.obs;
  final RxBool reactionsChanged = false.obs;
  final RxBool contentChanged = false.obs;
  final RxBool threadRepliesChanged = false.obs;
  final RxBool errorStateChanged = false.obs;
  
  /// Cache for parsed message parts to avoid repeated expensive parsing
  /// Set to false when message content changes, forcing a rebuild on next access
  bool _partsCached = false;

  MessageWidgetController(this.message) {
    tag = message.guid!;
  }

  Message? get newMessage =>
      newMessageGuid == null ? null : MessagesSvc(cvController!.chat.guid).struct.getMessage(newMessageGuid!);
  Message? get oldMessage =>
      oldMessageGuid == null ? null : MessagesSvc(cvController!.chat.guid).struct.getMessage(oldMessageGuid!);

  @override
  void onInit() {
    super.onInit();
    buildMessageParts();
    if (!kIsWeb && message.id != null) {
      final messageQuery = Database.messages.query(Message_.id.equals(message.id!)).watch();
      sub = messageQuery.listen((Query<Message> query) async {
        if (message.id == null) return;
        final _message = await runAsync(() {
          return Database.messages.get(message.id!);
        });
        if (_message != null) {
          if (_message.hasAttachments) {
            _message.attachments = List<Attachment>.from(_message.dbAttachments);
          }
          _message.associatedMessages = message.associatedMessages;
          _message.handle = _message.getHandle();
          updateMessage(_message);
        }
      });
    } else if (kIsWeb) {
      sub = WebListeners.messageUpdate.listen((tuple) {
        final _message = tuple.item1;
        final tempGuid = tuple.item2;
        if (_message.guid == message.guid || tempGuid == message.guid) {
          updateMessage(_message);
        }
      });
    }
  }

  @override
  void onClose() {
    sub?.cancel();
    super.onClose();
  }

  void close() {
    Get.delete<MessageWidgetController>(tag: tag);
  }

  void buildMessageParts({bool force = false}) {
    // Skip if already cached and not forced
    if (_partsCached && !force) return;
    
    // Clear parts for fresh build
    parts.clear();
    
    // go through the attributed body
    if (message.attributedBody.firstOrNull?.runs.isNotEmpty ?? false) {
      parts = attributedBodyToMessagePart(message.attributedBody.first);
    }
    // add edits
    if (message.messageSummaryInfo.firstOrNull?.editedParts.isNotEmpty ?? false) {
      for (int part in message.messageSummaryInfo.first.editedParts) {
        final edits = message.messageSummaryInfo.first.editedContent[part.toString()] ?? [];
        final existingPart = parts.firstWhereOrNull((element) => element.part == part);
        if (existingPart != null) {
          existingPart.edits.addAll(edits
              .where((e) => e.text?.values.isNotEmpty ?? false)
              .map((e) => attributedBodyToMessagePart(e.text!.values.first).firstOrNull)
              .where((e) => e != null)
              .map((e) => e!)
              .toList());
          if (existingPart.edits.isNotEmpty) {
            existingPart.edits.removeLast();
          }
        }
      }
    }
    // add unsends
    if (message.messageSummaryInfo.firstOrNull?.retractedParts.isNotEmpty ?? false) {
      for (int part in message.messageSummaryInfo.first.retractedParts) {
        final existing = parts.indexWhere((e) => e.part == part);
        if (existing >= 0) {
          parts.removeAt(existing);
        }
        parts.add(MessagePart(
          part: part,
          isUnsent: true,
        ));
      }
    }
    if (parts.isEmpty) {
      if (!message.hasApplePayloadData &&
          !message.isLegacyUrlPreview &&
          !message.isInteractive &&
          !message.isGroupEvent) {
        parts.addAll(message.attachments.mapIndexed((index, e) => MessagePart(
              attachments: [e!],
              part: index,
            )));
      } else if (message.isInteractive) {
        parts.add(MessagePart(
          part: 0,
        ));
      }

      if (message.fullText.isNotEmpty || message.isGroupEvent) {
        parts.add(MessagePart(
          subject: message.subject,
          text: message.text,
          part: parts.length,
        ));
      }
    }
    parts.sort((a, b) => a.part.compareTo(b.part));
    _partsCached = true;
  }

  List<MessagePart> attributedBodyToMessagePart(AttributedBody body) {
    final mainString = body.string;
    final list = <MessagePart>[];
    body.runs.sort((a, b) => a.range.first.compareTo(b.range.first));
    body.runs.forEachIndexed((i, e) async {
      if (e.attributes?.messagePart == null) return;
      final existingPart = list.firstWhereOrNull((element) => element.part == e.attributes!.messagePart!);
      if (existingPart != null) {
        final newText = mainString.substring(e.range.first, e.range.first + e.range.last);
        final currentLength = existingPart.text?.length ?? 0;
        existingPart.text = (existingPart.text ?? "") + newText;
        if (e.hasMention) {
          existingPart.mentions.add(Mention(
            mentionedAddress: e.attributes?.mention,
            range: [currentLength, currentLength + e.range.last],
          ));
          existingPart.mentions.sort((a, b) => a.range.first.compareTo(b.range.first));
        }
      } else {
        Attachment? foundAttachment;
        if (e.isAttachment && (cvController?.chat != null || cm.activeChat != null)) {
          final attachmentGuid = e.attributes!.attachmentGuid!;
          
          // First check message.attachments (loaded by Phase 1)
          foundAttachment = message.attachments.firstWhereOrNull((a) => a?.guid == attachmentGuid);
          if (foundAttachment == null) {
            // Then check struct cache
            foundAttachment = MessagesSvc(cvController?.chat.guid ?? cm.activeChat!.chat.guid)
                .struct
                .getAttachment(attachmentGuid);
            foundAttachment ??= await Attachment.findOneAsync(attachmentGuid);
          }
        }
        
        list.add(MessagePart(
          subject: i == 0 ? message.subject : null,
          text: e.isAttachment ? null : mainString.substring(e.range.first, e.range.first + e.range.last),
          attachments: foundAttachment != null ? [foundAttachment] : [],
          mentions: !e.hasMention
              ? []
              : [
                  Mention(
                    mentionedAddress: e.attributes?.mention,
                    range: [0, e.range.last],
                  )
                ],
          part: e.attributes!.messagePart!,
        ));
      }
    });
    return list;
  }

  void updateMessage(Message newItem) {
    final chat = message.chat.target?.guid ?? cvController?.chat.guid ?? cm.activeChat!.chat.guid;
    final oldGuid = message.guid;
    
    // Handle temp message guid replacement - requires full rebuild for color change
    if (newItem.guid != oldGuid && oldGuid!.contains("temp")) {
      message = Message.merge(newItem, message);
      MessagesSvc(chat).updateMessage(message, oldGuid: oldGuid);
      _partsCached = false; // Invalidate cache
      buildMessageParts(force: true);
      
      // Trigger content widget rebuilds to update bubble color from dark to normal
      // This happens once per sent message, so performance impact is minimal
      updateWidgets<TextBubble>(null);
      updateWidgets<InteractiveHolder>(null);
      
      if (message.isFromMe! && message.attachments.isNotEmpty) {
        updateWidgets<AttachmentHolder>(null);
      }
      return;
    }
    
    // Track what changed to minimize updates
    final deliveryChanged = newItem.dateDelivered != message.dateDelivered;
    final readChanged = newItem.dateRead != message.dateRead;
    final notifyChanged = newItem.didNotifyRecipient != message.didNotifyRecipient;
    final edited = newItem.dateEdited != message.dateEdited;
    final errorChanged = newItem.error != message.error;
    
    // Handle delivery/read status changes (lightweight update)
    if (deliveryChanged || readChanged || notifyChanged) {
      message = Message.merge(newItem, message);
      MessagesSvc(chat).updateMessage(message);
      
      // Only update delivery indicators, not full message
      deliveryStatusChanged.toggle();
      
      // Update the latest 2 messages in case their indicators need to go away
      final messages = MessagesSvc(chat)
          .struct
          .messages
          .where((e) => e.isFromMe! && (e.dateDelivered != null || e.dateRead != null))
          .toList()
        ..sort(Message.sort);
      for (Message m in messages.take(2)) {
        getActiveMwc(m.guid!)?.deliveryStatusChanged.toggle();
      }
      
      // If message was also edited, rebuild parts and update full holder
      if (edited) {
        _partsCached = false;
        buildMessageParts(force: true);
        contentChanged.toggle();
      }
      return;
    }
    
    // Handle content changes (edits) - requires full rebuild
    if (edited) {
      message = Message.merge(newItem, message);
      _partsCached = false;
      buildMessageParts(force: true);
      MessagesSvc(chat).updateMessage(message);
      contentChanged.toggle();
      return;
    }
    
    // Handle error state changes (lightweight update - just icon)
    if (errorChanged) {
      message = Message.merge(newItem, message);
      MessagesSvc(chat).updateMessage(message);
      errorStateChanged.toggle();
      return;
    }
  }

  void updateThreadOriginator(Message newItem) {
    // Use granular update instead of full MessageProperties rebuild
    threadRepliesChanged.toggle();
  }

  void updateAssociatedMessage(Message newItem, {bool updateHolder = true}) {
    final index = message.associatedMessages.indexWhere((e) => e.id == newItem.id);
    if (index >= 0) {
      message.associatedMessages[index] = newItem;
    } else {
      message.associatedMessages.add(newItem);
    }
    if (updateHolder) {
      // Use granular update instead of full MessageHolder rebuild
      reactionsChanged.toggle();
    }
  }

  void removeAssociatedMessage(Message toRemove) {
    message.associatedMessages.removeWhere((e) => e.id == toRemove.id);
    // Use granular update instead of full MessageHolder rebuild
    reactionsChanged.toggle();
  }
}
