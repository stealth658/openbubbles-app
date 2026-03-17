import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Attachment being downloaded from the server.
/// The Obx reacts only to download-state and progress changes.
class DownloadingContent extends StatelessWidget {
  const DownloadingContent({
    super.key,
    required this.downloadController,
    required this.isInReply,
    required this.isiOS,
  });

  final AttachmentDownloadController downloadController;
  final bool isInReply;
  final bool isiOS;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: isInReply ? 10.0 : 20.0,
      ),
      child: Obx(() {
        final isError = downloadController.state.value == AttachmentDownloadState.error;
        final isProcessing = downloadController.state.value == AttachmentDownloadState.processing;
        final isQueued = downloadController.state.value == AttachmentDownloadState.queued;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              width: 40,
              child: Center(
                child: isError
                    ? Icon(isiOS ? CupertinoIcons.arrow_clockwise : Icons.refresh, size: 30)
                    : isProcessing
                        ? (isiOS ? const CupertinoActivityIndicator(radius: 14) : const CircularProgressIndicator())
                        : isQueued
                            ? Icon(isiOS ? CupertinoIcons.clock : Icons.schedule, size: 30)
                            : CircleProgressBar(
                                value: downloadController.progress.value?.toDouble() ?? 0,
                                backgroundColor: context.theme.colorScheme.outline,
                                foregroundColor: context.theme.colorScheme.properOnSurface,
                              ),
              ),
            ),
            isError ? const SizedBox(height: 10) : const SizedBox(height: 5),
            Text(
              isError
                  ? "Failed to download!"
                  : isProcessing
                      ? "Processing"
                      : isQueued
                          ? "Queued"
                          : (downloadController.attachment.mimeType ?? ""),
              style: context.theme.textTheme.bodyLarge!
                  .copyWith(color: context.theme.colorScheme.properOnSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        );
      }),
    );
  }
}
