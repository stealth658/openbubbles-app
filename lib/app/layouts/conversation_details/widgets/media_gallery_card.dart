import 'dart:async';
import 'dart:math';

import 'package:animations/animations.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/other_file.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_holder.dart';
import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';
import 'package:video_player/video_player.dart';

class MediaGalleryCard extends StatefulWidget {
  MediaGalleryCard({super.key, required this.attachment});
  final Attachment attachment;

  @override
  State<MediaGalleryCard> createState() => _MediaGalleryCardState();
}

class _MediaGalleryCardState extends OptimizedState<MediaGalleryCard> with AutomaticKeepAliveClientMixin {
  Uint8List? videoPreview;
  Duration? duration;
  late dynamic content;

  Attachment get attachment => widget.attachment;

  @override
  void initState() {
    super.initState();
    updateContent();
  }

  void updateContent() {
    // Use the attachment service to get the content properly
    content = as.getContent(attachment, autoDownload: false, onComplete: onComplete);
    
    // If getContent returned a controller, listen to it
    if (content is AttachmentDownloadController) {
      (content as AttachmentDownloadController).completeFuncs.add(onComplete);
      (content as AttachmentDownloadController).errorFuncs.add(() {
        if (mounted) {
          setState(() {});
        }
      });
    }
    
    // If content is a PlatformFile with a path, generate video preview if needed
    if (content is PlatformFile && (content as PlatformFile).path != null) {
      if (attachment.mimeType?.contains("video") ?? false) {
        getVideoPreview(content as PlatformFile);
      }
    }
  }

  void onComplete(PlatformFile file) {
    if (mounted) {
      setState(() {
        content = file;
      });
      if (attachment.mimeType?.contains("video") ?? false) {
        getVideoPreview(file);
      }
    }
  }

  void downloadAttachment() {
    setState(() {
      content = AttachmentDownloader.startDownload(attachment, onComplete: onComplete);
      if (content is AttachmentDownloadController) {
        (content as AttachmentDownloadController).errorFuncs.add(() {
          if (mounted) {
            setState(() {});
          }
          showSnackbar("Error", "Failed to download attachment!");
        });
      }
    });
  }

  Future<void> getVideoPreview(PlatformFile file) async {
    if (videoPreview != null || file.path == null) return;
    if (attachment.metadata?['thumbnail_status'] == 'error') {
      return;
    }

    try {
      videoPreview = await as.getVideoThumbnail(file.path!);
      dynamic _file = File(file.path!);
      final tempController = VideoPlayerController.file(_file);
      await tempController.initialize();
      duration = tempController.value.duration;
    } catch (_) {
      // If an error occurs, set the thumbnail to the cached no preview image
      videoPreview = FilesystemSvc.noVideoPreviewIcon;

      if (attachment.metadata?['thumbnail_status'] != 'error') {
        attachment.metadata ??= {};
        attachment.metadata!['thumbnail_status'] = 'error';
        await attachment.saveAsync(null);
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool hideAttachments = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideAttachments.value;

    late Widget child;
    bool addPadding = true;

    if (hideAttachments) {
      child = Text(
        attachment.mimeType ?? "Unknown",
        textAlign: TextAlign.center,
      );
    } else if (content is AttachmentDownloadController) {
      child = SizedBox(
        height: 40,
        width: 40,
        child: Obx(() {
          final controller = content as AttachmentDownloadController;
          return controller.state.value == AttachmentDownloadState.processing
              ? (iOS
                  ? const CupertinoActivityIndicator(radius: 14)
                  : const CircularProgressIndicator())
              : CircleProgressBar(
                  foregroundColor: context.theme.colorScheme.primary,
                  backgroundColor: context.theme.colorScheme.outline,
                  value: controller.progress.value?.toDouble() ?? 0,
                );
        }),
      );
    } else if (content is Attachment) {
      // Attachment not downloaded yet
      child = InkWell(
        onTap: downloadAttachment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              attachment.getFriendlySize(),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 5),
            Icon(SettingsSvc.settings.skin.value == Skins.iOS
                ? CupertinoIcons.cloud_download
                : Icons.cloud_download,
              size: 28.0,
              color: context.theme.colorScheme.properOnSurface
            ),
            const SizedBox(height: 5),
            Text(
              attachment.mimeType ?? "Unknown File Type",
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else if (content is PlatformFile) {
      final file = content as PlatformFile;
      if (attachment.mimeType?.startsWith("image") ?? false) {
        child = ImageDisplay(attachment: attachment, file: file);
        addPadding = false;
      } else if ((attachment.mimeType?.startsWith("video") ?? false) && !kIsDesktop && !kIsWeb) {
        if (videoPreview != null) {
          child = ImageDisplay(attachment: attachment, image: videoPreview!, duration: duration);
          addPadding = false;
        } else {
          child = const Text(
            "Loading video preview...",
            textAlign: TextAlign.center,
          );
        }
      } else {
        child = OtherFile(
          file: file,
          attachment: attachment,
        );
      }
    } else {
      child = const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: Container(
        alignment: Alignment.center,
        color: context.theme.colorScheme.properSurface,
        padding: addPadding ? const EdgeInsets.all(10) : null,
        child: child,
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ImageDisplay extends StatelessWidget {
  const ImageDisplay({
    super.key,
    required this.attachment,
    this.file,
    this.image,
    this.duration,
  });

  final Attachment attachment;
  final PlatformFile? file;
  final Uint8List? image;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      openBuilder: (_, closeContainer) {
        return FullscreenMediaHolder(
          attachment: attachment,
          showInteractions: true,
        );
      },
      closedBuilder: (_, openContainer) {
        return InkWell(
          onTap: () {
            openContainer();
          },
          child: SizedBox(
            width: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
            height: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
            child: Stack(
              children: [
                if (file != null && file!.path != null)
                  Image.file(
                    File(file!.path!),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    cacheWidth: NavigationSvc.width(context) ~/ max(2, NavigationSvc.width(context) ~/ 200) * 2,
                    width: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                    height: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                  )
                else if (image != null)
                  Image.memory(
                    image!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    cacheWidth: NavigationSvc.width(context) ~/ max(2, NavigationSvc.width(context) ~/ 200) * 2,
                    width: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                    height: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                  )
                else
                  SizedBox(
                    width: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                    height: NavigationSvc.width(context) / max(2, NavigationSvc.width(context) ~/ 200),
                  ),
                if ((attachment.mimeType?.contains("video") ?? false) && duration != null)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Text(duration.toString().split('.').first
                        .padLeft(8, "0").padLeft(9, "a")
                        .replaceFirst("a00:", "").replaceFirst("a", ""),
                      style: context.theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                if (!(attachment.message.target?.isFromMe ?? true)
                    && attachment.message.target?.handleRelation.hasValue == true
                    && SettingsSvc.settings.skin.value == Skins.iOS)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: ContactAvatarWidget(handle: attachment.message.target?.handleRelation.target),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
