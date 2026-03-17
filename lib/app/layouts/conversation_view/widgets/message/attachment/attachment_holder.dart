import 'dart:async';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/parts/sending_opacity_wrapper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/parts/upload_progress_content.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/parts/not_loaded_content.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/parts/downloading_content.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/parts/resolved_file_content.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/app/state/attachment_state.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/ui/attributed_body_helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

class AttachmentHolder extends CustomStateful<MessageWidgetController> {
  const AttachmentHolder({
    super.key,
    required super.parentController,
    required this.message,
  });

  final MessagePart message;

  @override
  CustomState createState() => _AttachmentHolderState();
}

class _AttachmentHolderState extends CustomState<AttachmentHolder, void, MessageWidgetController> {
  MessagePart get part => widget.message;
  Message get message => controller.message;
  Message? get newerMessage => controller.newMessage;

  Attachment get attachment =>
      message.attachments.firstWhereOrNull((e) => e?.id == part.attachments.first.id) ??
      MessagesSvc(controller.cvController?.chat.guid ?? ChatsSvc.activeChat!.chat.guid)
          .struct
          .attachments
          .firstWhereOrNull((e) => e.id == part.attachments.first.id) ??
      part.attachments.first;

  String? get audioTranscript => getAudioTranscriptsFromAttributedBody(message.attributedBody)[part.part];

  // ── AttachmentState access ─────────────────────────────────────────────────

  /// Returns the [AttachmentState] for [attachment] from the per-message state
  /// map, if one exists.
  ///
  /// Lookup strategy (most-to-least stable):
  /// 1. Original part-level GUID (`part.attachments.first.guid`) — this is
  ///    always the temp GUID for outgoing messages and never changes on the
  ///    MessagePart, so the Obx subscription survives the temp → real swap.
  /// 2. Current `attachment.guid` — used once the state has been promoted to
  ///    the real key by [_syncAttachmentStates].
  AttachmentState? get _attachmentState {
    final messageState = controller.messageState;
    if (messageState == null) return null;

    // Try the original part GUID first (stable key, even after GUID swap).
    final originalGuid = part.attachments.first.guid;
    if (originalGuid != null) {
      final state = messageState.getAttachmentState(originalGuid);
      if (state != null) return state;
    }

    // Fall back to the current resolved attachment GUID.
    final currentGuid = attachment.guid;
    if (currentGuid == null) return null;
    return messageState.getAttachmentState(currentGuid);
  }

  /// Resolves the [MessagesService] for the chat that owns this message.
  MessagesService get _msvc =>
      MessagesSvc(controller.cvController?.chat.guid ?? ChatsSvc.activeChat!.chat.guid);

  @override
  void initState() {
    forceDelete = false;
    super.initState();
    _loadContent();
  }

  // ── Content loading ────────────────────────────────────────────────────────

  /// Delegates all content loading and download orchestration to the service
  /// layer.  The widget only reacts to [_attachmentState] observable changes.
  void _loadContent() {
    final msgGuid = message.guid;
    if (msgGuid == null) return;
    if (!Get.isRegistered<MessagesService>(tag: _msvc.tag)) return;
    unawaited(_msvc.loadAttachmentContent(msgGuid, attachment));
  }

  @override
  void updateWidget(void _) {
    _loadContent();
    super.updateWidget(_);
  }

  // ── Build helpers ──────────────────────────────────────────────────────────

  VoidCallback? _buildOnTap() {
    final state = _attachmentState;

    // Already resolved — no tap action needed.
    if (state?.resolvedFile.value != null) return null;

    return () {
      final isSending = state?.isSending.value ?? controller.messageState?.isSending.value ?? false;
      if (message.error != 0 || isSending) return;

      final msgGuid = message.guid;
      if (msgGuid == null) return;

      final activeDownload = state?.activeDownload.value;
      if (activeDownload != null) {
        // Only retry on error; ignore taps while already downloading.
        if (activeDownload.state.value != AttachmentDownloadState.error) return;
        _msvc.retryAttachmentDownload(msgGuid, attachment);
      } else {
        _msvc.startAttachmentDownload(msgGuid, attachment);
      }
    };
  }

  EdgeInsetsGeometry _computePadding(bool hideAttachments, bool showTail, bool isInReply) {
    final state = _attachmentState;
    final sideInsets = EdgeInsets.only(
      left: message.isFromMe! ? 0 : 10,
      right: message.isFromMe! ? 10 : 0,
    );

    if (state?.resolvedFile.value != null && !hideAttachments) {
      return showTail ? EdgeInsets.zero : sideInsets;
    }
    if (isInReply) {
      return const EdgeInsets.symmetric(vertical: 5, horizontal: 10).add(sideInsets);
    }
    if (state?.isSending.value == true && message.isFromMe!) {
      return EdgeInsets.zero;
    }
    return const EdgeInsets.symmetric(vertical: 10, horizontal: 15).add(sideInsets);
  }

  Widget _buildContent({
    required bool hideAttachments,
    required bool showTail,
    required bool isInReply,
    required bool isiOS,
  }) {
    // Redacted mode always shows placeholder regardless of download status.
    if (hideAttachments) {
      return NotLoadedContent(
        attachment: attachment,
        message: message,
        controller: controller,
        hideAttachments: true,
        isiOS: isiOS,
      );
    }

    final state = _attachmentState;

    // Outgoing send failed — render the local file as normal so it shows next
    // to the ErrorIndicatorObserver in MessageHolder (which handles the error UI).
    final hasError = (state?.hasError.value ?? false) || message.error > 0;
    if (hasError && message.isFromMe == true) {
      final previewFile = state?.uploadPreviewFile.value ?? state?.resolvedFile.value;
      if (previewFile != null) {
        return ResolvedFileContent(
          file: previewFile,
          attachment: attachment,
          message: message,
          audioTranscript: audioTranscript,
          showTail: showTail,
          isiOS: isiOS,
          cvController: controller.cvController,
        );
      }
    }

    // File is available — render it.
    final file = state?.resolvedFile.value;
    if (file != null) {
      return ResolvedFileContent(
        file: file,
        attachment: attachment,
        message: message,
        audioTranscript: audioTranscript,
        showTail: showTail,
        isiOS: isiOS,
        cvController: controller.cvController,
      );
    }

    // Upload in progress — show progress overlay (with optional preview).
    if (state?.isSending.value == true) {
      return UploadProgressContent(
        previewFile: state!.uploadPreviewFile.value,
        progress: state.uploadProgress,
        attachment: attachment,
        message: message,
        isiOS: isiOS,
        cvController: controller.cvController,
      );
    }

    // Download in progress — show the download controller's progress UI.
    final download = state?.activeDownload.value;
    if (download != null) {
      return DownloadingContent(
        downloadController: download,
        isInReply: isInReply,
        isiOS: isiOS,
      );
    }

    // Not yet loaded, queued, or errored.
    return NotLoadedContent(
      attachment: attachment,
      message: message,
      controller: controller,
      hideAttachments: false,
      isiOS: isiOS,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool showTail = message.showTail(newerMessage) && part.part == controller.parts.length - 1;
    final bool hideAttachments = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideAttachments.value;
    final bool isInReply = ReplyScope.maybeOf(context) != null;

    return Obx(() {
      final bool isiOS = iOS;
      final bool selected = !isiOS && (controller.cvController?.selected.any((m) => m.guid == message.guid) ?? false);
      final state = _attachmentState;

      // Reading these observables registers the Obx dependency so the widget
      // rebuilds whenever transfer state, resolved file, or active download
      // changes — including service-driven transitions (upload complete,
      // incoming GUID swap, auto-download started from another code path).
      // ignore: unused_local_variable
      final _ = state?.transferState.value;
      // ignore: unused_local_variable
      final __ = state?.resolvedFile.value;
      // ignore: unused_local_variable
      final ___ = state?.activeDownload.value;
      // ignore: unused_local_variable
      final ____ = state?.hasError.value;

      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          context.theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          selected ? BlendMode.srcOver : BlendMode.dstOver,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _buildOnTap(),
            child: Ink(
              color: context.theme.colorScheme.properSurface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: NavigationSvc.width(context) * 0.5,
                  maxHeight: isInReply ? double.infinity : context.height * 0.6,
                  minHeight: isInReply ? 0 : 40,
                  minWidth: isInReply ? 0 : 100,
                ),
                child: Padding(
                  padding: _computePadding(hideAttachments, showTail, isInReply),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    child: Center(
                      heightFactor: 1,
                      widthFactor: 1,
                      // SendingOpacityWrapper has its own Obx so isSending
                      // changes only rebuild the opacity layer, not this tree.
                      child: SendingOpacityWrapper(
                        controller: controller,
                        child: _buildContent(
                          hideAttachments: hideAttachments,
                          showTail: showTail,
                          isInReply: isInReply,
                          isiOS: isiOS,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}


