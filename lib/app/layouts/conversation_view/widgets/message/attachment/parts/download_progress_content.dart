import 'dart:math';

import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Attachment transfer actively in progress: shows a circular progress bar.
/// Applies to both incoming downloads and outgoing uploads without a local
/// preview file.  The [Obx] rebuilds only this widget on each progress tick.
class DownloadProgressContent extends StatelessWidget {
  const DownloadProgressContent({
    super.key,
    required this.progress,
    required this.attachment,
    required this.message,
  });

  final RxnDouble progress;
  final Attachment attachment;
  final Message message;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final progressValue = progress.value ?? 0.0;
      return Padding(
        padding: EdgeInsets.only(
          left: 10.0,
          top: 10.0,
          right: 10.0,
          bottom: progressValue < 1 && message.error == 0 ? 0 : 10.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              width: 40,
              child: Center(
                child: CircleProgressBar(
                  value: progressValue,
                  backgroundColor: context.theme.colorScheme.outline,
                  foregroundColor: context.theme.colorScheme.properOnSurface,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "${(attachment.totalBytes! * min(progressValue, 1.0)).toDouble().getFriendlySize(withSuffix: false)} / ${attachment.getFriendlySize()}",
              style: context.theme.textTheme.bodyLarge!
                  .copyWith(color: context.theme.colorScheme.properOnSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (message.error == 0)
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: progressValue < 1
                    ? () => OutgoingMsgHandler.latestCancelToken?.cancel("User cancelled send.")
                    : null,
                child: progressValue < 1
                    ? Text("Cancel",
                        style: context.theme.textTheme.bodyLarge!
                            .copyWith(color: context.theme.colorScheme.primary))
                    : Text("Waiting for iMessage...",
                        style: context.theme.textTheme.bodyLarge!, textAlign: TextAlign.center),
              ),
          ],
        ),
      );
    });
  }
}
