import 'dart:math';
import 'dart:ui';

import 'package:palette_generator/palette_generator.dart';
import 'package:universal_io/io.dart';

import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MessageSender extends StatelessWidget {
  const MessageSender({super.key, required this.olderMessage, this.googleStyle = false, this.showAvatar = false});

  final Message? olderMessage;

  /// Google Messages layout: a small avatar beside the name, the name in the
  /// contact's colour, above the bubble (no avatar beside the bubble).
  final bool googleStyle;
  final bool showAvatar;

  static final Map<String, Color?> _photoColors = {};

  /// Dominant colour of a contact photo, computed once per path.
  static Future<Color?> _photoColor(String path) async {
    if (_photoColors.containsKey(path)) return _photoColors[path];
    Color? c;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(FileImage(File(path)), width: 48, height: 48),
        maximumColorCount: 6,
      );
      c = palette.dominantColor?.color;
    } catch (_) {}
    _photoColors[path] = c;
    return c;
  }

  /// [c] nudged darker (light theme) or lighter (dark theme) until it has at
  /// least 4.5:1 contrast with [bg].
  static Color _readable(Color c, Color bg) {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    final darkBg = bg.computeLuminance() < 0.5;
    var hsl = HSLColor.fromColor(c);
    for (var i = 0; i < 20 && contrast(hsl.toColor(), bg) < 4.5; i++) {
      hsl = hsl.withLightness((hsl.lightness + (darkBg ? 0.04 : -0.04)).clamp(0.0, 1.0));
    }
    return hsl.toColor();
  }

  @override
  Widget build(BuildContext context) {
    final state = MessageStateScope.maybeOf(context);
    if (state == null) return const SizedBox.shrink();
    final chatState = ChatStateScope.maybeOf(context);
    if (googleStyle) {
      return Padding(
        padding: const EdgeInsets.only(left: 5, right: 25, bottom: 4, top: 2),
        child: Obx(() {
          // The name takes the colour of the avatar it sits beside: the
          // contact photo's dominant colour when there is a photo (contact
          // tiles are often coloured monogram photos), else the custom or
          // address-gradient colour; then darkened/lightened until it reads
          // against the background.
          final handle = state.sender?.handle ?? state.message.handleRelation.target;
          final hex = state.sender?.color.value ?? handle?.color;
          final base = hex != null ? HexColor(hex) : toColorGradient(handle?.address).first;
          final photo = state.sender?.avatarPath.value;
          final bg = context.theme.colorScheme.surface;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAvatar) ...[
                ContactAvatarWidget(
                  handle: state.message.handleRelation.target,
                  size: 28,
                  fontSize: 12,
                  borderThickness: 0.1,
                  editable: false,
                  scaleSize: false,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FutureBuilder<Color?>(
                  future: photo == null ? null : _photoColor(photo),
                  initialData: photo == null ? null : _photoColors[photo],
                  builder: (context, snap) => Text(
                    state.senderDisplayName,
                    style: context.theme.textTheme.labelLarge!
                        .copyWith(color: _readable(snap.data ?? base, bg), fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );
        }),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25).add(const EdgeInsets.only(bottom: 3)),
      // Obx makes the sender name reactive: updates when contact data syncs.
      child: Obx(() {
        final hasCustomBackground = chatState?.hasCustomWallpaper ?? false;
        final text = Text(
          state.senderDisplayName,
          style: context.theme.textTheme.labelMedium!.copyWith(
            color: hasCustomBackground ? context.theme.colorScheme.onSurface : context.theme.colorScheme.outline,
            fontWeight: FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (!hasCustomBackground) return text;
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1.0,
          child: IntrinsicWidth(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: context.theme.colorScheme.surface.withValues(alpha: 0.5),
                  child: text,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
