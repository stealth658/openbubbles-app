import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/polls.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

class SupportedInteractive extends StatefulWidget {
  final iMessageAppData data;

  const SupportedInteractive({
    super.key,
    required this.data,
  });

  @override
  State<StatefulWidget> createState() => _SupportedInteractiveState();
}

class _SupportedInteractiveState extends State<SupportedInteractive> with AutomaticKeepAliveClientMixin {
  iMessageAppData get data => widget.data;
  dynamic get file => File(content.path!);
  dynamic content;

  /// OpenBubbles: live iMessage-app extensions are hosted in a platform view,
  /// which is expensive. Keep at most [_maxAliveExtensions] of them mounted and
  /// force the oldest one to render nothing once the cap is exceeded.
  static const int _maxAliveExtensions = 20;
  static final List<_SupportedInteractiveState> aliveExtensions = [];

  bool forcedDead = false;

  @override
  void initState() {
    super.initState();
    aliveExtensions.add(this);
    if (aliveExtensions.length > _maxAliveExtensions) {
      final oldExt = aliveExtensions.removeAt(0);
      oldExt.forcedDead = true;
      if (oldExt.mounted) oldExt.setState(() {});
    }
  }

  @override
  void dispose() {
    aliveExtensions.remove(this);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // OpenBubbles: a live extension we actually have installed renders in its
    // own Android platform view rather than as a static preview image.
    if (data.isLive == true && data.appId != null && es.isAppAvailable(data.appId!)) {
      final message = MessageStateScope.messageOf(context);
      final params = data.toNative(null);
      params["messageGuid"] = message.stagingGuid ?? message.guid;
      params["user-count"] = (ChatsSvc.activeChat?.chat.participants.length ?? 0) + 1;
      return SizedBox(
        height: 250,
        child: forcedDead
            ? const SizedBox.shrink()
            : RepaintBoundary(
                child: AndroidView(
                  key: ValueKey(params.toString()),
                  viewType: "extension-live",
                  layoutDirection: TextDirection.ltr,
                  creationParams: params,
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),
      );
    }
    // OpenBubbles: polls sent by us have no appId yet - render the native poll UI.
    if (data.appName == "Polls" && data.appId == null) {
      return Polls(data: data, message: null);
    }
    if (content == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final attachment = MessageStateScope.messageOf(context).dbAttachments.firstOrNull;
        if (attachment != null) {
          content = AttachmentsSvc.getContent(attachment, autoDownload: true, onComplete: (file) {
            if (mounted) {
              setState(() {
                content = file;
              });
            }
          });
          if (content != null && mounted) setState(() {});
        }
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            if (content is PlatformFile && content.bytes != null)
              Image.memory(
                content.bytes!,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, object, stacktrace) => Center(
                  heightFactor: 1,
                  child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                ),
              ),
            if (content is PlatformFile && content.bytes == null && content.path != null)
              Image.file(
                file,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, object, stacktrace) => Center(
                  heightFactor: 1,
                  child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                ),
              ),
            if (!isNullOrEmpty(data.userInfo?.imageTitle) || !isNullOrEmpty(data.userInfo?.imageSubtitle))
              Positioned(
                bottom: 5,
                left: 15,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isNullOrEmpty(data.userInfo?.imageTitle))
                      Text(
                        data.userInfo!.imageTitle!,
                        style: context.theme.textTheme.bodyMedium!.apply(fontWeightDelta: 2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (!isNullOrEmpty(data.userInfo?.imageSubtitle))
                      Text(data.userInfo!.imageSubtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.normal)),
                  ],
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(15.0),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isNullOrEmpty(data.userInfo?.caption))
                  Flexible(
                    fit: !isNullOrEmpty(data.userInfo?.secondarySubcaption) ? FlexFit.tight : FlexFit.loose,
                    child: Text(
                      data.userInfo!.caption!,
                      style: context.theme.textTheme.bodyLarge!.apply(fontWeightDelta: 2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (isNullOrEmpty(data.userInfo?.caption) && !isNullOrEmpty(data.ldText))
                  Flexible(
                    fit: !isNullOrEmpty(data.userInfo?.secondarySubcaption) ? FlexFit.tight : FlexFit.loose,
                    child: Text(
                      data.ldText!,
                      style: context.theme.textTheme.bodyLarge!.apply(fontWeightDelta: 2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (!isNullOrEmpty(data.userInfo?.secondarySubcaption))
                  Text(
                    data.userInfo!.secondarySubcaption!,
                    style: context.theme.textTheme.bodyLarge!.apply(fontWeightDelta: 2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            if (!isNullOrEmpty(data.userInfo?.subcaption)) const SizedBox(height: 2.5),
            if (!isNullOrEmpty(data.userInfo?.subcaption))
              Text(data.userInfo!.subcaption!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.normal)),
            if (!isNullOrEmpty(data.appName)) const SizedBox(height: 5),
            if (!isNullOrEmpty(data.appName))
              Text(
                data.appName!,
                style: context.theme.textTheme.labelMedium!
                    .copyWith(fontWeight: FontWeight.normal, color: context.theme.colorScheme.outline),
                overflow: TextOverflow.clip,
                maxLines: 1,
              ),
          ]),
        )
      ],
    );
  }
}
