import 'dart:async';

import 'package:bluebubbles/app/components/base/base.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/dialogs/metadata_dialog.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';

// (needed for custom back button)
//ignore: implementation_imports
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart' as media_kit_video_controls;
import 'package:universal_html/html.dart' as html;

class FullscreenVideo extends StatefulWidget {
  const FullscreenVideo({
    super.key,
    required this.file,
    required this.attachment,
    required this.showInteractions,
    this.videoController,
    this.mute,
  });

  final PlatformFile file;
  final Attachment attachment;
  final bool showInteractions;

  final VideoController? videoController;
  final RxBool? mute;

  @override
  OptimizedState createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends OptimizedState<FullscreenVideo> with AutomaticKeepAliveClientMixin {
  Timer? hideOverlayTimer;

  late VideoController videoController;

  bool hasListener = false;
  bool hasDisposed = false;
  final RxBool muted = SettingsSvc.settings.startVideosMutedFullscreen.value.obs;
  final RxBool showPlayPauseOverlay = true.obs;
  final RxDouble aspectRatio = 1.0.obs;

  @override
  void initState() {
    super.initState();

    if (widget.mute != null) {
      muted.value = widget.mute!.value;
    }

    _setFullscreen(true);
    initControllers();
  }

  void _setFullscreen(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void initControllers() async {
    if (widget.videoController != null) {
      // Reuse existing controller from in-chat player
      videoController = widget.videoController!;
      // Sync mute state
      await videoController.player.setVolume(muted.value ? 0 : 100);
    } else {
      // Create new controller
      videoController = VideoController(Player());

      late final Media media;
      if (widget.file.path == null) {
        final blob = html.Blob([widget.file.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        media = Media(url);
      } else {
        media = Media(widget.file.path!);
      }

      await videoController.player.setPlaylistMode(PlaylistMode.none);
      await videoController.player.open(media, play: false);
      await videoController.player.setVolume(muted.value ? 0 : 100);
    }

    createListener(videoController);
    showPlayPauseOverlay.value = true;
    setState(() {});
  }

  void createListener(VideoController controller) {
    if (hasListener) return;

    controller.rect.addListener(() {
      aspectRatio.value = controller.aspectRatio;
    });

    controller.player.stream.completed.listen((completed) async {
      // If the status is ended, restart
      if (completed && !hasDisposed) {
        await controller.player.pause();
        await controller.player.seek(Duration.zero);
        await controller.player.pause();
        showPlayPauseOverlay.value = true;
        showPlayPauseOverlay.refresh();
      }
    });

    hasListener = true;
  }

  @override
  void dispose() {
    hasDisposed = true;
    hideOverlayTimer?.cancel();
    _setFullscreen(false);

    // Sync mute state back to parent
    if (widget.mute != null) {
      widget.mute!.value = muted.value;
    }

    // Only dispose the player if one was not passed in (via a controller)
    if (widget.videoController == null) {
      videoController.player.dispose();
    }

    super.dispose();
  }

  void refreshAttachment() {
    showSnackbar('In Progress', 'Redownloading attachment. Please wait...');
    AttachmentsSvc.redownloadAttachment(widget.attachment, onComplete: (file) async {
      if (hasDisposed) return;
      hasListener = false;
      late final Media media;
      if (widget.file.path == null) {
        final blob = html.Blob([widget.file.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        media = Media(url);
      } else {
        media = Media(widget.file.path!);
      }
      await videoController.player.open(media, play: false);
      await videoController.player.setVolume(muted.value ? 0 : 100);
      createListener(videoController);
      showPlayPauseOverlay.value = !videoController.player.state.playing;
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final RxBool _hover = false.obs;
    return Container(
      color: Colors.black,
      child: Obx(
        () => MouseRegion(
          onEnter: (event) => showPlayPauseOverlay.value = true,
          onExit: (event) => showPlayPauseOverlay.value = !videoController.player.state.playing,
          child: SafeArea(
            child: Center(
              child: Theme(
                data: context.theme.copyWith(
                    platform: iOS ? TargetPlatform.iOS : TargetPlatform.android,
                    dialogBackgroundColor: context.theme.colorScheme.properSurface,
                    iconTheme: context.theme.iconTheme.copyWith(color: context.theme.textTheme.bodyMedium?.color)),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Video(
                        controller: videoController,
                        controls: (state) => Padding(
                              padding: EdgeInsets.all(!kIsWeb && !kIsDesktop ? 0 : 20)
                                  .copyWith(bottom: !kIsWeb && !kIsDesktop ? 10 : 0),
                              child: kIsDesktop
                                  ? media_kit_video_controls.MaterialDesktopVideoControls(state)
                                  : media_kit_video_controls.MaterialVideoControls(state),
                            ),
                        filterQuality: FilterQuality.medium),
                    if (kIsWeb || kIsDesktop)
                      Obx(() {
                        return MouseRegion(
                          onEnter: (event) => _hover.value = true,
                          onExit: (event) => _hover.value = false,
                          child: AbsorbPointer(
                            absorbing: !showPlayPauseOverlay.value && !_hover.value,
                            child: AnimatedOpacity(
                              opacity: _hover.value
                                  ? 1
                                  : showPlayPauseOverlay.value
                                      ? 0.5
                                      : 0,
                              duration: const Duration(milliseconds: 100),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: () async {
                                    if (videoController.player.state.playing) {
                                      await videoController.player.pause();
                                      showPlayPauseOverlay.value = true;
                                    } else {
                                      await videoController.player.play();
                                      showPlayPauseOverlay.value = false;
                                    }
                                  },
                                  child: Container(
                                    height: 75,
                                    width: 75,
                                    decoration: BoxDecoration(
                                      color: context.theme.colorScheme.background.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: SettingsSvc.settings.skin.value == Skins.iOS &&
                                                !videoController.player.state.playing
                                            ? 17
                                            : 10,
                                        top: SettingsSvc.settings.skin.value == Skins.iOS ? 13 : 10,
                                        right: 10,
                                        bottom: 10,
                                      ),
                                      child: Obx(
                                        () => videoController.player.state.playing
                                            ? Icon(
                                                SettingsSvc.settings.skin.value == Skins.iOS
                                                    ? CupertinoIcons.pause
                                                    : Icons.pause,
                                                color: context.iconColor,
                                                size: 45,
                                              )
                                            : Icon(
                                                SettingsSvc.settings.skin.value == Skins.iOS
                                                    ? CupertinoIcons.play
                                                    : Icons.play_arrow,
                                                color: context.iconColor,
                                                size: 45,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    if (!iOS && (kIsWeb || kIsDesktop))
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Obx(() {
                          return MouseRegion(
                            onEnter: (event) => _hover.value = true,
                            onExit: (event) => _hover.value = false,
                            child: AbsorbPointer(
                              absorbing: !showPlayPauseOverlay.value && !_hover.value,
                              child: AnimatedOpacity(
                                opacity: _hover.value
                                    ? 1
                                    : showPlayPauseOverlay.value
                                        ? 1
                                        : 0,
                                duration: const Duration(milliseconds: 100),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(40),
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                        size: 25,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    // Bottom action bar for iOS
                    if (iOS && widget.showInteractions)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedOpacity(
                          opacity: showPlayPauseOverlay.value ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: SafeArea(
                            top: false,
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color:
                                    samsung ? Colors.black : context.theme.colorScheme.properSurface.withValues(alpha: 0.9),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  BBIconButton(
                                    icon: CupertinoIcons.cloud_download,
                                    color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                    onPressed: () => AttachmentsSvc.saveToDisk(widget.file),
                                  ),
                                  BBIconButton(
                                    icon: CupertinoIcons.info,
                                    color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                    onPressed: () => showMetadataDialog(widget.attachment, context),
                                  ),
                                  BBIconButton(
                                    icon: CupertinoIcons.refresh,
                                    color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                    onPressed: () => refreshAttachment(),
                                  ),
                                  BBIconButton(
                                    icon: muted.value ? CupertinoIcons.volume_mute : CupertinoIcons.volume_up,
                                    color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                    onPressed: () async {
                                      muted.toggle();
                                      await videoController.player.setVolume(muted.value ? 0.0 : 100.0);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
