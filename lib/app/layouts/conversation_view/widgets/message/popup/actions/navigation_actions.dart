import 'dart:io';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/layouts/chat_creator/new_chat_creator.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_action_context.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_thread_popup.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/widgets.dart';

void reply(MessagePopupActionContext ctx) {
  ctx.popDetails();
  ctx.cvController.replyToMessage = MessageReplyContext(ctx.message, ctx.part.part);
}

void openDm(MessagePopupActionContext ctx) {
  if (ctx.dmChat == null) return;
  ctx.popDetails();
  Navigator.pushReplacement(
    ctx.context,
    cupertino.CupertinoPageRoute(
      builder: (BuildContext context) {
        return ConversationView(chat: ctx.dmChat!);
      },
    ),
  );
}

void showThread(MessagePopupActionContext ctx) {
  ctx.popDetails();
  if (ctx.message.threadOriginatorGuid != null) {
    final mwc = ctx.service.getMessageStateIfExists(ctx.message.threadOriginatorGuid!);
    if (mwc == null) return ctx.showSnack("Error", "Failed to find thread!");
    showReplyThread(
        ctx.context, mwc.message, mwc.parts[ctx.message.normalizedThreadPart], ctx.service, ctx.cvController);
  } else {
    showReplyThread(ctx.context, ctx.message, ctx.part, ctx.service, ctx.cvController);
  }
}

void newConvo(MessagePopupActionContext ctx) {
  final Handle? handle = ctx.message.handleRelation.target;
  if (handle == null) return;
  ctx.popDetails();
  // This route replacement bypasses ConversationView's back-handler, so
  // explicitly close the active controller first.
  ctx.cvController.close();
  NavigationSvc.pushAndRemoveUntil(
    ctx.context,
    NewChatCreator(initialSelected: [SelectedContact(displayName: handle.displayName, address: handle.address)]),
    (route) => route.isFirst,
  );
}

Future<void> forward(MessagePopupActionContext ctx) async {
  ctx.popDetails();
  final hasFile = ctx.message.dbAttachments.any((e) => AttachmentsSvc.getContent(e, autoDownload: false) is PlatformFile);
  if (hasFile || !isNullOrEmpty(ctx.message.text)) {
    // This route replacement bypasses ConversationView's back-handler, so
    // explicitly close the active controller first.
    ctx.cvController.close();
    // The message is sent as it is once a chat is chosen (text and
    // attachments together), not merged into the composer.
    NavigationSvc.pushAndRemoveUntil(
      ctx.context,
      NewChatCreator(forwardMessages: [ctx.message]),
      (route) => route.isFirst,
    );
  }
}
