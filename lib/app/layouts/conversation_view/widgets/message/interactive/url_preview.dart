import 'dart:convert';
import 'dart:ui';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart' as parser;
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlPreview extends StatefulWidget {
  final UrlPreviewData data;
  final Message message;
  final PlatformFile? file;

  const UrlPreview({
    super.key,
    required this.data,
    required this.message,
    this.file,
  });

  @override
  OptimizedState createState() => _UrlPreviewState();
}

class _UrlPreviewState extends OptimizedState<UrlPreview> with AutomaticKeepAliveClientMixin {
  UrlPreviewData get data => widget.data;
  UrlPreviewData? dataOverride;
  File? get file => content is PlatformFile && content?.path != null ? File(content!.path!) : null;
  PlatformFile? content;
  MediaMetadata? localImageMetadata;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    updateObx(() async {
      // refers to a location widget
      if (widget.file != null) {
        String? _location;
        if (kIsWeb || widget.file!.path == null) {
          _location = utf8.decode(widget.file!.bytes!);
        } else {
          _location = await File(widget.file!.path!).readAsString();
        }
        dataOverride = UrlPreviewData(
          title: data.title,
          siteName: data.siteName,
        );
        dataOverride!.url = AttachmentsSvc.parseAppleLocationUrl(_location)
            ?.replaceAll("\\", "")
            .replaceAll("http:", "https:")
            .replaceAll("/?", "/place?")
            .replaceAll(",", "%2C");
        if (dataOverride!.url == null) return;
        final response = await HttpSvc.dio.get(dataOverride!.url!);
        final document = parser.parse(response.data);
        final link = document
            .getElementsByClassName("sc-platter-cell")
            .firstOrNull
            ?.children
            .firstWhereOrNull((e) => e.localName == "a");
        final url = link?.attributes["href"];
        if (url != null) {
          MetadataFetch.extract(dataOverride!.url!).then((metadata) {
            if (metadata?.image != null) {
              dataOverride!.imageMetadata = MediaMetadata(size: const Size.square(1), url: metadata!.image);
              dataOverride!.summary = metadata.description ?? metadata.title;
              dataOverride!.url = url;
              if (mounted) setState(() {});
            }
          });
        }
      } else if (data.imageMetadata?.url == null && data.iconMetadata?.url == null) {
        final attachment = widget.message.attachments
            .firstWhereOrNull((e) => e?.transferName?.contains("pluginPayloadAttachment") ?? false);
        if (attachment != null) {
          content = AttachmentsSvc.getContent(attachment, autoDownload: true, onComplete: (file) {
            if (mounted) {
              setState(() {
                content = file;
              });
            }
          });
          if (content is PlatformFile) {
            if (mounted) setState(() {});
          }
        } else {
          MetadataFetch.extract((data.url ?? data.originalUrl)!).then((metadata) async {
            if (metadata?.image != null) {
              localImageMetadata = MediaMetadata(size: const Size.square(1), url: metadata!.image);
              if (mounted) setState(() {});
            } else {
              final response = await HttpSvc.dio.get((data.url ?? data.originalUrl)!);
              if (response.headers.value('content-type')?.startsWith("image/") ?? false) {
                localImageMetadata = MediaMetadata(size: const Size.square(1), url: (data.url ?? data.originalUrl)!);
                if (mounted) setState(() {});
              }
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final effectiveImageMetadata = localImageMetadata ?? data.imageMetadata;
    final siteText = widget.file != null
        ? (dataOverride?.siteName ?? "")
        : Uri.tryParse(data.url ?? data.originalUrl ?? "")?.host ?? data.siteName;
    final hasAppleImage = (effectiveImageMetadata?.url == null ||
        (data.iconMetadata?.url == null && effectiveImageMetadata?.size == Size.zero));
    final _data = dataOverride ?? data;
    return InkWell(
      onTap: widget.file != null && _data.url != null
          ? () async {
              await launchUrl(Uri.parse(_data.url!), mode: LaunchMode.externalApplication);
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (effectiveImageMetadata?.url != null && ReplyScope.maybeOf(context) == null)
            Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(effectiveImageMetadata!.url!),
                  fit: BoxFit.cover,
                ),
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: context.height * 0.4),
                      child: Image.network(
                        effectiveImageMetadata.url!,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.none,
                        errorBuilder: (context, object, stacktrace) => Center(
                          heightFactor: 1,
                          child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (content is PlatformFile && hasAppleImage && content?.bytes != null && ReplyScope.maybeOf(context) == null)
            Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: MemoryImage(content!.bytes!),
                  fit: BoxFit.cover,
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: context.height * 0.4),
                    child: Image.memory(
                      content!.bytes!,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (context, object, stacktrace) => Center(
                        heightFactor: 1,
                        child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (content is PlatformFile &&
              hasAppleImage &&
              content?.bytes == null &&
              content?.path != null &&
              file != null &&
              ReplyScope.maybeOf(context) == null)
            Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: FileImage(file!),
                  fit: BoxFit.cover,
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: context.height * 0.4),
                    child: Image.file(
                      file!,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (context, object, stacktrace) => Center(
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 5.0),
                          child: Row(children: [
                            Text("Failed to display image", style: context.theme.textTheme.bodyLarge),
                            const SizedBox(width: 2.0),
                            IconButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(
                                        "URL Preview Stacktrace",
                                        style: context.theme.textTheme.titleLarge,
                                      ),
                                      backgroundColor: context.theme.colorScheme.properSurface,
                                      content: SizedBox(
                                        width: NavigationSvc.width(context) * 3 / 5,
                                        height: context.height * 1 / 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(10.0),
                                          decoration: BoxDecoration(
                                              color: context.theme.colorScheme.background,
                                              borderRadius: const BorderRadius.all(Radius.circular(10))),
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
                                          child: Text("Close",
                                              style: context.theme.textTheme.bodyLarge!
                                                  .copyWith(color: context.theme.colorScheme.primary)),
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(CupertinoIcons.info_circle))
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child:
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      !isNullOrEmpty(_data.title)
                          ? _data.title!
                          : !isNullOrEmpty(siteText)
                              ? siteText!
                              : widget.message.text!,
                      style: context.theme.textTheme.bodyMedium!.apply(fontWeightDelta: 2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isNullOrEmpty(_data.summary)) const SizedBox(height: 5),
                    if (!isNullOrEmpty(_data.summary))
                      Text(_data.summary ?? "",
                          maxLines: ReplyScope.maybeOf(context) == null ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.normal)),
                    if (!isNullOrEmpty(siteText)) const SizedBox(height: 5),
                    if (!isNullOrEmpty(siteText))
                      Text(
                        siteText!,
                        style: context.theme.textTheme.labelMedium!
                            .copyWith(fontWeight: FontWeight.normal, color: context.theme.colorScheme.outline),
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                      ),
                  ]),
                ),
                if (_data.iconMetadata?.url != null) const SizedBox(width: 10),
                if (_data.iconMetadata?.url != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 45,
                    ),
                    child: Image.network(
                      _data.iconMetadata!.url!,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
