import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:animations/animations.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/app/components/media/bb_media_grid.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/other_file.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_holder.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart' as universal_io;
import 'package:video_player/video_player.dart';

/// Unified media card component for displaying attachments
/// 
/// Provides consistent styling across all media galleries (images, videos, documents).
/// Uses design tokens for border radius and spacing.
/// 
/// Example:
/// ```dart
/// BBMediaCard(attachment: attachment)
/// ```
class BBMediaCard extends StatefulWidget {
  const BBMediaCard({
    super.key,
    required this.attachment,
    this.borderRadius,
  });

  final Attachment attachment;
  
  /// Optional border radius override
  /// 
  /// Defaults to BBRadius.medium() based on current skin
  final BorderRadius? borderRadius;

  @override
  State<BBMediaCard> createState() => _BBMediaCardState();
}

class _BBMediaCardState extends OptimizedState<BBMediaCard> with AutomaticKeepAliveClientMixin {
  Uint8List? videoPreview;
  Duration? duration;
  late dynamic content;

  Attachment get attachment => widget.attachment;

  @override
  void initState() {
    super.initState();
    updateContent();
  }

  @override
  void didUpdateWidget(BBMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the attachment GUID changed (e.g., temp -> real GUID after send), update content
    if (oldWidget.attachment.guid != widget.attachment.guid) {
      updateContent();
    }
  }

  void updateContent() {
    // Use the attachment service to get the content properly
    content = AttachmentsSvc.getContent(attachment, autoDownload: false, onComplete: onComplete);

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
      videoPreview = await AttachmentsSvc.getVideoThumbnail(file.path!);
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
    final skin = SettingsSvc.settings.skin.value;
    final effectiveBorderRadius = widget.borderRadius ?? BBRadius.mediumBR(skin);

    late Widget child;
    bool addPadding = true;

    if (hideAttachments) {
      child = Text(
        attachment.mimeType ?? "Unknown",
        textAlign: TextAlign.center,
      );
    } else if (content is AttachmentWithProgress) {
      // Attachment being sent - show image with progress overlay
      final attachmentWithProgress = content as AttachmentWithProgress;
      final file = attachmentWithProgress.file;
      final progress = attachmentWithProgress.progress;

      addPadding = false;
      child = Stack(
        fit: StackFit.expand,
        children: [
          // Background image with lower opacity
          Opacity(
            opacity: 0.3,
            child: attachment.mimeType?.startsWith("image") ?? false
                ? Image.file(
                    universal_io.File(file.path!),
                    fit: BoxFit.cover,
                  )
                : const SizedBox.shrink(),
          ),
          // Progress indicator overlay
          Center(
            child: SizedBox(
              height: 50,
              width: 50,
              child: CircleProgressBar(
                foregroundColor: context.theme.colorScheme.primary,
                backgroundColor: context.theme.colorScheme.outline,
                value: progress.item2.value,
              ),
            ),
          ),
        ],
      );
    } else if (content is AttachmentDownloadController) {
      // Download in progress
      final controller = content as AttachmentDownloadController;
      child = SizedBox(
        height: 40,
        width: 40,
        child: Obx(() {
          return controller.state.value == AttachmentDownloadState.processing
              ? (iOS ? const CupertinoActivityIndicator(radius: 14) : const CircularProgressIndicator())
              : CircleProgressBar(
                  foregroundColor: context.theme.colorScheme.primary,
                  backgroundColor: context.theme.colorScheme.outline,
                  value: controller.progress.value?.toDouble() ?? 0,
                );
        }),
      );
    } else if (content == null || (content is! PlatformFile && content is! AttachmentWithProgress)) {
      // Not downloaded - show download button
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            iOS ? CupertinoIcons.arrow_down_circle : Icons.download,
            size: 48,
            color: context.theme.colorScheme.primary,
          ),
          const SizedBox(height: BBSpacing.sm),
          TextButton(
            onPressed: downloadAttachment,
            child: const Text("Download"),
          ),
          const SizedBox(height: BBSpacing.xs),
          Text(
            attachment.mimeType ?? "Unknown File Type",
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (content is PlatformFile) {
      final file = content as PlatformFile;
      if (attachment.mimeType?.startsWith("image") ?? false) {
        child = _BBImageDisplay(attachment: attachment, file: file);
        addPadding = false;
      } else if ((attachment.mimeType?.startsWith("video") ?? false) && !kIsDesktop && !kIsWeb) {
        if (videoPreview != null) {
          child = _BBImageDisplay(attachment: attachment, image: videoPreview!, duration: duration);
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
      borderRadius: effectiveBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        alignment: Alignment.center,
        color: context.theme.colorScheme.properSurface,
        padding: addPadding ? const EdgeInsets.all(BBSpacing.sm) : null,
        child: child,
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// Internal image display widget for BBMediaCard
class _BBImageDisplay extends StatefulWidget {
  const _BBImageDisplay({
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
  State<_BBImageDisplay> createState() => _BBImageDisplayState();
}

class _BBImageDisplayState extends State<_BBImageDisplay> {
  bool _needsBlur = true; // Default to true (safer)
  bool _dimensionsChecked = false;

  @override
  void initState() {
    super.initState();
    _checkImageDimensions();
  }

  @override
  void didUpdateWidget(_BBImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check if file or image changed
    if (oldWidget.file?.path != widget.file?.path || oldWidget.image != widget.image) {
      _dimensionsChecked = false;
      _needsBlur = true;
      _checkImageDimensions();
    }
  }

  void _checkImageDimensions() {
    if (_dimensionsChecked) return;

    // Only check metadata - avoid expensive image decoding
    final metadata = widget.attachment.metadata;
    if (metadata != null && metadata['width'] != null && metadata['height'] != null) {
      final width = (metadata['width'] as num).toDouble();
      final height = (metadata['height'] as num).toDouble();
      final aspectRatio = width / height;
      
      // If aspect ratio is significantly different from 1.0 (square), we need blur
      // Allow 10% tolerance (0.9 to 1.1 range)
      setState(() {
        _needsBlur = aspectRatio < 0.9 || aspectRatio > 1.1;
        _dimensionsChecked = true;
      });
    } else {
      // No metadata available - assume we need blur rather than decode image
      // This is cheaper than decoding the image just to check dimensions
      setState(() {
        _needsBlur = true;
        _dimensionsChecked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      openBuilder: (_, closeContainer) {
        return FullscreenMediaHolder(
          attachment: widget.attachment,
          showInteractions: true,
        );
      },
      closedBuilder: (_, openContainer) {
        return InkWell(
          onTap: () {
            openContainer();
          },
          child: SizedBox(
            width: NavigationSvc.width(context) / BBMediaGrid.calculateCrossAxisCount(context),
            height: NavigationSvc.width(context) / BBMediaGrid.calculateCrossAxisCount(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred background image (only if needed based on aspect ratio)
                if (_needsBlur) ...[
                  if (widget.file != null && widget.file!.path != null)
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: BBBlur.strong, sigmaY: BBBlur.strong),
                      child: Image.file(
                        File(widget.file!.path!),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        alignment: Alignment.center,
                      ),
                    )
                  else if (widget.image != null)
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: BBBlur.strong, sigmaY: BBBlur.strong),
                      child: Image.memory(
                        widget.image!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                ],
                // Centered main image (preserving aspect ratio)
                if (widget.file != null && widget.file!.path != null)
                  Center(
                    child: Image.file(
                      File(widget.file!.path!),
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      cacheWidth: (NavigationSvc.width(context) ~/
                              BBMediaGrid.calculateCrossAxisCount(context) *
                              MediaQuery.of(context).devicePixelRatio)
                          .toInt(),
                    ),
                  )
                else if (widget.image != null)
                  Center(
                    child: Image.memory(
                      widget.image!,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      cacheWidth: (NavigationSvc.width(context) ~/
                              BBMediaGrid.calculateCrossAxisCount(context) *
                              MediaQuery.of(context).devicePixelRatio)
                          .toInt(),
                    ),
                  ),
                // Video duration overlay
                if ((widget.attachment.mimeType?.contains("video") ?? false) && widget.duration != null)
                  Positioned(
                    bottom: BBSpacing.sm,
                    right: BBSpacing.sm,
                    child: Text(
                      widget.duration
                          .toString()
                          .split('.')
                          .first
                          .padLeft(8, "0")
                          .padLeft(9, "a")
                          .replaceFirst("a00:", "")
                          .replaceFirst("a", ""),
                      style: context.theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                // Contact avatar (iOS only)
                if (!(widget.attachment.message.target?.isFromMe ?? true) &&
                    widget.attachment.message.target?.handleRelation.hasValue == true &&
                    SettingsSvc.settings.skin.value == Skins.iOS)
                  Positioned(
                    top: BBSpacing.sm,
                    right: BBSpacing.sm,
                    child: ContactAvatarWidget(handle: widget.attachment.message.target?.handleRelation.target),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
