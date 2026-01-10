import 'dart:math';
import 'dart:io';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/live_photo_mixin.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ImageViewer extends StatefulWidget {
  final PlatformFile file;
  final Attachment attachment;
  final bool isFromMe;

  ImageViewer({
    super.key,
    required this.file,
    required this.attachment,
    required this.isFromMe,
    this.controller,
  });

  final ConversationViewController? controller;

  @override
  OptimizedState createState() => _ImageViewerState();
}

class _ImageViewerState extends OptimizedState<ImageViewer> with AutomaticKeepAliveClientMixin, LivePhotoMixin {
  Attachment get attachment => widget.attachment;
  PlatformFile get file => widget.file;
  ConversationViewController? get controller => widget.controller;
  
  // Implement required getter for LivePhotoMixin
  @override
  Attachment get livePhotoAttachment => attachment;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Handle demo attachments
    if (attachment.guid!.contains("demo")) {
      return Image.asset(attachment.transferName!, fit: BoxFit.cover);
    }

    // Build the appropriate image widget based on platform and file availability
    Widget imageWidget;
    if (kIsWeb || file.path == null) {
      // Web or no path - use memory image
      if (file.bytes == null) {
        imageWidget = SizedBox(
          width: min((attachment.width?.toDouble() ?? NavigationSvc.width(context) * 0.5), NavigationSvc.width(context) * 0.5),
          height: min((attachment.height?.toDouble() ?? NavigationSvc.width(context) * 0.5 / attachment.aspectRatio), NavigationSvc.width(context) * 0.5 / attachment.aspectRatio),
        );
      } else {
        final displayWidth = min((attachment.width?.toDouble() ?? NavigationSvc.width(context) * 0.5), NavigationSvc.width(context) * 0.5);
        final displayHeight = min((attachment.height?.toDouble() ?? NavigationSvc.width(context) * 0.5 / attachment.aspectRatio), NavigationSvc.width(context) * 0.5 / attachment.aspectRatio);
        final qualityFactor = SettingsSvc.settings.previewImageQuality.value;
        final calculatedWidth = (displayWidth * Get.pixelRatio * qualityFactor).round().abs().nonZero;
        final calculatedHeight = (displayHeight * Get.pixelRatio * qualityFactor).round().abs().nonZero;
        imageWidget = Image.memory(
          file.bytes!,
          gaplessPlayback: true,
          filterQuality: FilterQuality.none,
          cacheWidth: calculatedWidth,
          cacheHeight: calculatedHeight,
          fit: BoxFit.contain,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            if (frame == null) {
              // Show placeholder while loading
              return Container(
                width: displayWidth,
                height: displayHeight,
                color: context.theme.colorScheme.properSurface.withOpacity(0.3),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.outline),
                  ),
                ),
              );
            }
            return child;
          },
          errorBuilder: (context, object, stacktrace) => Center(
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 5.0),
              child: Row(
                children: [
                  Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                  const SizedBox(width: 2.0),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            "Image Stacktrace",
                            style: context.theme.textTheme.titleLarge,
                          ),
                          backgroundColor: context.theme.colorScheme.properSurface,
                          content: SizedBox(
                            width: NavigationSvc.width(context) * 3 / 5,
                            height: context.height * 1 / 4,
                            child: Container(
                              padding: const EdgeInsets.all(10.0),
                              decoration: BoxDecoration(color: context.theme.colorScheme.background, borderRadius: const BorderRadius.all(Radius.circular(10))),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  stacktrace.toString(),
                                  style: context.theme.textTheme.bodyLarge,
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              child: Text("Close", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(CupertinoIcons.info_circle)
                  )
                ]
            ),
          ),
        ));
      }
    } else {
      // Non-web with file path - use file image (much more efficient)
      // Note: For HEIC/TIFF, the path might point to unconverted file initially.
      // Image.file will handle it on iOS/macOS (native support), or fail gracefully
      // and trigger errorBuilder where we can attempt conversion.
      final displayWidth = min((attachment.width?.toDouble() ?? NavigationSvc.width(context) * 0.5), NavigationSvc.width(context) * 0.5);
      final displayHeight = min((attachment.height?.toDouble() ?? NavigationSvc.width(context) * 0.5 / attachment.aspectRatio), NavigationSvc.width(context) * 0.5 / attachment.aspectRatio);
      // Use configured quality factor from settings (25% to 100%)
      final qualityFactor = SettingsSvc.settings.previewImageQuality.value;
      final calculatedWidth = (displayWidth * Get.pixelRatio * qualityFactor).round().abs().nonZero;
      final calculatedHeight = (displayHeight * Get.pixelRatio * qualityFactor).round().abs().nonZero;
      imageWidget = Image.file(
        File(file.path!),
        gaplessPlayback: true,
        filterQuality: FilterQuality.none,
        cacheWidth: calculatedWidth,
        cacheHeight: calculatedHeight,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          if (frame == null) {
            // Show placeholder while loading
            return Container(
              width: displayWidth,
              height: displayHeight,
              color: context.theme.colorScheme.properSurface.withOpacity(0.3),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.outline),
                ),
              ),
            );
          }
          return child;
        },
        errorBuilder: (context, object, stacktrace) => FutureBuilder<String?>(
          future: AttachmentsSvc.ensureImageCompatibility(attachment, actualPath: file.path),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                width: min((attachment.width?.toDouble() ?? NavigationSvc.width(context) * 0.5), NavigationSvc.width(context) * 0.5),
                height: min((attachment.height?.toDouble() ?? NavigationSvc.width(context) * 0.5 / attachment.aspectRatio), NavigationSvc.width(context) * 0.5 / attachment.aspectRatio),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            
            if (snapshot.hasData && snapshot.data != null && snapshot.data != file.path) {
              // Conversion successful, display converted image
              return Image.file(
                File(snapshot.data!),
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
                cacheWidth: calculatedWidth,
                cacheHeight: calculatedHeight,
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  if (frame == null) {
                    // Show placeholder while loading converted image
                    return Container(
                      width: displayWidth,
                      height: displayHeight,
                      color: context.theme.colorScheme.properSurface.withOpacity(0.3),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.outline),
                        ),
                      ),
                    );
                  }
                  return child;
                },
              );
            }
            
            // Conversion failed or not needed
            return Center(
              heightFactor: 1,
              child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
            );
          },
        ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 40,
          minWidth: 100,
        ),
        child: Stack(
          alignment: !widget.isFromMe ? Alignment.topRight : Alignment.topLeft,
          children: [
            imageWidget,
            // Live photo video overlay
            if (attachment.hasLivePhoto) buildLivePhotoOverlay(),
            // Live photo button indicator
            if (attachment.hasLivePhoto && !isPlayingLivePhoto)
              Positioned(
                top: 8,
                right: widget.isFromMe ? null : 8,
                left: widget.isFromMe ? 8 : null,
                child: GestureDetector(
                  onTap: () {
                    if (!isDownloadingLivePhoto) {
                      handleLivePhotoTap();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDownloadingLivePhoto)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          const Icon(
                            Icons.album_outlined,
                            size: 12,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 3),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
