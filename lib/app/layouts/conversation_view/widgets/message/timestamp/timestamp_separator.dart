import 'dart:io';

import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_down_button/pull_down_button.dart';

class _TimestampParts {
  final String? date;
  final String time;
  const _TimestampParts({this.date, required this.time});
}

class TimestampSeparator extends StatelessWidget {
  const TimestampSeparator({
    super.key,
    required this.olderMessage,
  });
  final Message? olderMessage;

  bool withinTimeThreshold(Message first, Message? second) {
    // OpenBubbles: a scheduled message always gets its own header, and
    // scheduled runs break every 5 minutes rather than every 30.
    if (second == null) return first.dateScheduled != null;
    final diff = second.chatViewDate!.difference(first.chatViewDate!).inMinutes.abs();
    return diff > 30 ||
        (first.dateScheduled != null) != (second.dateScheduled != null) ||
        (diff > 5 && first.dateScheduled != null);
  }

  _TimestampParts? buildTimeStamp(Message message) {
    if (SettingsSvc.settings.skin.value == Skins.Samsung &&
        message.chatViewDate?.day != olderMessage?.chatViewDate?.day) {
      return _TimestampParts(time: buildSeparatorDateSamsung(message.chatViewDate!));
    } else if (SettingsSvc.settings.skin.value != Skins.Samsung && withinTimeThreshold(message, olderMessage)) {
      final time = message.chatViewDate!;
      if (SettingsSvc.settings.skin.value == Skins.iOS) {
        return _TimestampParts(date: time.isToday() ? "Today" : buildDate(time), time: buildTime(time));
      } else {
        return _TimestampParts(
            date: time.isToday() ? "Today" : buildSeparatorDateMaterial(time), time: buildTime(time));
      }
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = MessageStateScope.messageOf(context);
    final timestamp = buildTimeStamp(message);
    final hasBackground = ChatStateScope.maybeOf(context)?.hasCustomWallpaper ?? false;

    if (timestamp == null) return const SizedBox.shrink();

    final textColor = hasBackground ? context.theme.colorScheme.onSurfaceVariant : context.theme.colorScheme.outline;

    final isScheduled = message.dateScheduled != null;

    final richText = RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: context.theme.textTheme.labelSmall!.copyWith(color: textColor, fontWeight: FontWeight.normal),
        children: [
          // OpenBubbles: header above a run of scheduled ("Send Later") messages.
          if (isScheduled && olderMessage?.dateScheduled == null)
            TextSpan(
              text: "Send Later\n",
              style: context.theme.textTheme.labelSmall!
                  .copyWith(fontWeight: FontWeight.w600, color: textColor, height: 2.5),
            ),
          if (timestamp.date != null)
            TextSpan(
              text: "${timestamp.date!} ",
              style: context.theme.textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w600, color: textColor),
            ),
          TextSpan(text: timestamp.time),
          if (isScheduled)
            TextSpan(
              text: " Edit",
              style: context.theme.textTheme.labelSmall!
                  .copyWith(fontWeight: FontWeight.w600, color: context.theme.primaryColor),
            ),
        ],
      ),
    );

    final separator = Padding(
      padding: const EdgeInsets.all(14.0),
      child: hasBackground
          ? Center(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: richText,
              ),
            )
          : richText,
    );

    if (!isScheduled) return separator;

    final chat = message.chat.target ?? ChatStateScope.maybeChatOf(context);
    if (chat == null) return separator;

    // OpenBubbles: tapping the "Send Later" header lets you send / reschedule /
    // delete the whole batch of messages scheduled for (roughly) that moment.
    return PullDownButton(
      routeTheme: PullDownMenuRouteTheme(
          backgroundColor: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)),
      animationAlignmentOverride: Alignment.bottomCenter,
      itemBuilder: (context) {
        final responsibleMessages = MessagesSvc(chat.guid)
            .struct
            .messages
            .where((m) =>
                m.dateScheduled != null &&
                m.dateScheduled!.difference(message.dateScheduled!).inMinutes < 5 &&
                m.dateScheduled!.difference(message.dateScheduled!).inMinutes >= 0)
            .toList();
        responsibleMessages.sort(Message.sort);
        return [
          PullDownMenuItem(
            title: responsibleMessages.length == 1 ? 'Send Message' : 'Send ${responsibleMessages.length} Messages',
            icon: CupertinoIcons.arrow_up_circle,
            onTap: () async {
              for (final m in responsibleMessages) {
                m.dateScheduled = null;
                m.stagingGuid = m.guid;
                m.dateCreated = DateTime.now();
                m.generateTempGuid();
                m.save();
                // Straight through the backend: the message row already exists,
                // so it must not be re-prepped by the outgoing queue.
                await backend.sendMessage(chat, m);
              }
            },
          ),
          PullDownMenuItem(
            title: 'Edit Time',
            icon: CupertinoIcons.clock,
            onTap: () async {
              final date = await showTimeframePicker("Pick date and time", context, presetsAhead: true);
              if (date == null || !date.isAfter(DateTime.now())) return;
              for (final m in responsibleMessages) {
                m.dateScheduled = date;
                m.save();
                await backend.sendMessage(chat, m);
              }
            },
          ),
          PullDownMenuItem(
            title: responsibleMessages.length == 1 ? 'Delete Message' : 'Delete ${responsibleMessages.length} Messages',
            icon: CupertinoIcons.trash,
            iconColor: Colors.red[700],
            onTap: () async {
              for (final m in responsibleMessages) {
                // actually perma deletes for scheduled messages, :shrug:
                await backend.moveToRecycleBin(chat, m);
                for (final attachment in (m.fetchAttachments() ?? <Attachment?>[])) {
                  if (attachment == null) continue;
                  try {
                    File(attachment.getFile().path!).deleteSync();
                  } catch (e) {
                    Logger.debug("Failed to rm attachment $e");
                  }
                }
                MessagesSvc(chat.guid).removeMessage(m);
                await Message.delete(m.guid!);
              }
            },
          ),
        ];
      },
      buttonBuilder: (context, showMenu) => GestureDetector(onTap: showMenu, child: separator),
    );
  }
}
