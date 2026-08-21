import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/apple_pay.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/find_my.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/passwords.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/polls.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/embedded_media.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/game_pigeon.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/photo_slideshow.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/supported_interactive.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/unsupported_interactive.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/url_preview.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/tail_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_holder.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart' hide PayloadType;
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class InteractiveHolder extends StatefulWidget {
  const InteractiveHolder({
    super.key,
    required this.message,
  });

  final MessagePart message;

  @override
  State<StatefulWidget> createState() => _InteractiveHolderState();
}

class _InteractiveHolderState extends State<InteractiveHolder> with AutomaticKeepAliveClientMixin, ThemeHelpers {
  late MessageState _ms;
  MessageState get controller => _ms;

  MessagePart get part => widget.message;
  Message get message => controller.message;
  PayloadData? get payloadData => message.payloadData;

  /// OpenBubbles: base64 app icon carried on the payload for iMessage apps.
  Uint8List? appIcon;

  @override
  void initState() {
    super.initState();
    _ms = MessageStateScope.readStateOnce(context);
    final icon = payloadData?.appData?.first.icon;
    if (icon != null) {
      appIcon = base64Decode(icon);
    }
  }

  @override
  bool get wantKeepAlive => true;

  /// OpenBubbles: overlays the iMessage app's icon on top of the preview image.
  Widget _withAppIcon(Widget child) {
    final appData = payloadData?.appData?.firstOrNull;
    final showIcon = appIcon != null &&
        (message.dbAttachments.isNotEmpty || ((appData?.isLive ?? false) && (appData?.isSupported ?? false)));
    if (!showIcon) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 7,
          left: 7,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Image.memory(appIcon!, width: 30),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // OpenBubbles: an iMessage app "session" (amkSessionId) supersedes its
    // earlier updates - only the newest item in a session renders as a bubble,
    // the rest collapse into a one-line "app name did X" summary.
    final amkSessionId = message.amkSessionId;
    if (amkSessionId != null && es.getLatest(amkSessionId).firstOrNull != (message.stagingGuid ?? message.guid)) {
      final latestItems = es.getLatest(amkSessionId);
      if (!latestItems.contains(message.stagingGuid ?? message.guid)) {
        return const SizedBox.shrink();
      }
      final appData = payloadData!.appData!.first;
      return Padding(
        padding:
            EdgeInsets.only(left: message.isFromMe! ? 0 : 10, right: message.isFromMe! ? 10 : 0, top: 10, bottom: 10),
        child: Row(
          children: [
            if (appIcon != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.memory(appIcon!, width: 30),
              ),
            const SizedBox(width: 5),
            Text(
              appData.ldText ?? "",
              style: context.theme.textTheme.labelMedium!
                  .copyWith(fontWeight: FontWeight.normal, color: context.theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }
    return Obx(() {
      // Observe selection state
      final selected = !iOS && (controller.cvController?.selected.any((m) => m.guid == message.guid) ?? false);

      return ColorFiltered(
        colorFilter: ColorFilter.mode(
            !selected ? Colors.transparent : context.theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
            BlendMode.srcOver),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: (payloadData == null && !message.isLegacyUrlPreview)
                ? null
                : () async {
                    String? url;
                    if (payloadData == null) {
                      url = message.url;
                    } else if (payloadData!.type == PayloadType.url) {
                      url = payloadData!.urlData!.first.originalUrl ?? payloadData!.urlData!.first.url;
                    } else {
                      url = payloadData!.appData!.first.url;
                    }
                    // OpenBubbles: if we actually have the iMessage app extension
                    // installed, open it instead of falling back to a web URL.
                    final appId = payloadData?.appData?.firstOrNull?.appId;
                    if (url != null && appId != null && es.isAppSupported(appId)) {
                      es.engageApp(message);
                      return;
                    }
                    // Live Location is handled inline by the FindMy widget.
                    if (message.interactiveText == "Live Location") return;
                    if (url != null && Uri.tryParse(url) != null) {
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
            child: CustomPaint(
              painter: iOS
                  ? null
                  : TailPainter(
                      isFromMe: message.isFromMe!,
                      showTail: false,
                      color: (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor ??
                          context.theme.colorScheme.surfaceContainerHighest,
                      width: 1.5,
                    ),
              child: Ink(
                color: (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor ??
                    context.theme.colorScheme.surfaceContainerHighest,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: NavigationSvc.width(context) * (NavigationSvc.isTabletMode(context) ? 0.5 : 0.6),
                    maxHeight: context.height * 0.6,
                    minHeight: 40,
                    minWidth: 40,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(left: message.isFromMe! ? 0 : 10, right: message.isFromMe! ? 10 : 0),
                    child: Center(
                      heightFactor: 1,
                      widthFactor: 1,
                      child: _withAppIcon(_ms.shouldHideAttachments.value
                          ? const Padding(padding: EdgeInsets.all(15), child: Text("Interactive Message"))
                          : Obx(() {
                              final isTempMessage = controller.isSending.value;
                              return Opacity(
                                  opacity: isTempMessage ? 0.5 : 1,
                                  child: Builder(builder: (context) {
                                    if (payloadData == null && !(message.isLegacyUrlPreview)) {
                                      switch (message.interactiveText) {
                                        case "Handwriten Message":
                                        case "Handwritten Message":
                                        case "Digital Touch Message":
                                          // rustpush renders handwriting / Digital
                                          // Touch natively; the BlueBubbles server
                                          // path still needs PAPI + v1.6.0.
                                          if (usingRustPush ||
                                              (SettingsSvc.settings.enablePrivateAPI.value &&
                                                  SettingsSvc.serverDetails.isMinBigSur &&
                                                  SettingsSvc.serverDetails.supportsGroupChatManagement)) {
                                            return const EmbeddedMedia();
                                          } else {
                                            return const UnsupportedInteractive(
                                              payloadData: null,
                                            );
                                          }
                                        default:
                                          return const UnsupportedInteractive(
                                            payloadData: null,
                                          );
                                      }
                                    } else if (payloadData?.type == PayloadType.url || message.isLegacyUrlPreview) {
                                      final urlData =
                                          payloadData?.urlData?.first ?? UrlPreviewData(originalUrl: message.url);
                                      return UrlPreview(data: urlData);
                                    } else {
                                      final data = payloadData!.appData!.first;
                                      if (message.isPhotoSlideshow) {
                                        return PhotoSlideshow(
                                          data: data,
                                        );
                                      }
                                      switch (message.interactiveText) {
                                        // OpenBubbles-only interactive messages.
                                        case "Polls":
                                          return Polls(
                                            data: data,
                                            message: message,
                                          );
                                        case "Live Location":
                                          return FindMy(
                                            data: data,
                                            message: message,
                                            isPopup: PopupScope.maybeOf(context) != null,
                                          );
                                        case "com.openbubbles.passwords":
                                          return SharedPasswords(
                                            data: data,
                                            message: message,
                                          );
                                        case "YouTube":
                                        case "OpenTable":
                                        case "iMessage Poll":
                                        case "Shazam":
                                        case "Google Maps":
                                          return SupportedInteractive(
                                            data: data,
                                          );
                                        case "GamePigeon":
                                          return GamePigeon(
                                            data: data,
                                          );
                                        case "Apple Pay":
                                          return ApplePay(
                                            data: data,
                                          );
                                        default:
                                          // OpenBubbles: rustpush knows about more
                                          // apps than the hardcoded list above.
                                          if (data.isSupported) {
                                            return SupportedInteractive(
                                              data: data,
                                            );
                                          }
                                          return UnsupportedInteractive(
                                            payloadData: data,
                                          );
                                      }
                                    }
                                  }));
                            })),
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
