import 'dart:math';
import 'dart:ui';

import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

class ReactionDetails extends StatelessWidget {
  const ReactionDetails({
    super.key,
    required this.reactions,
  });

  final List<Message> reactions;

  String? _nameFor(Message message) {
    if (SettingsSvc.settings.hideNamesForReactions.value) return null;
    final handle = message.handleRelation.target;
    if (message.isFromMe!) return SettingsSvc.settings.userName.value;
    if (handle != null) return HandleSvc.getOrCreateHandleState(handle).reactionDisplayName.value;
    return null;
  }

  /// Material 3: a compact card sized to its content, on the same tone and
  /// elevation as the tapback bar. Each person is an avatar with their tapback
  /// as a badge on its corner and their name underneath. No glass.
  Widget _material3(BuildContext context) {
    final scheme = context.theme.colorScheme;

    Widget badge(Message message) {
      final type = message.associatedMessageType;
      final Widget glyph;
      if (type == ReactionTypes.EMOJI && message.associatedMessageEmoji != null) {
        glyph = Text(message.associatedMessageEmoji!,
            style: const TextStyle(fontSize: 13, fontFamily: 'Apple Color Emoji', height: 1.1));
      } else if (useIosTapbacks) {
        glyph = SvgPicture.asset(
          'assets/reactions/$type-black.svg',
          width: 13,
          height: 13,
          colorFilter: ColorFilter.mode(type == "love" ? Colors.pink : scheme.onSecondaryContainer, BlendMode.srcIn),
        );
      } else {
        final text = Text(ReactionTypes.reactionToEmoji[type] ?? "",
            style: const TextStyle(fontSize: 13, fontFamily: 'Apple Color Emoji', height: 1.1));
        glyph = type == "dislike"
            ? Transform(transform: Matrix4.identity()..rotateY(pi), alignment: FractionalOffset.center, child: text)
            : text;
      }
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.secondaryContainer,
          border: Border.all(color: scheme.surfaceContainerHigh, width: 2),
        ),
        child: glyph,
      );
    }

    return Obx(() => Center(
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shadowColor: scheme.shadow,
            surfaceTintColor: Colors.transparent,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < reactions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    ConstrainedBox(
                      key: ValueKey(reactions[i].guid!),
                      constraints: const BoxConstraints(minWidth: 56, maxWidth: 88),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 48,
                            height: 44,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: 4,
                                  top: 0,
                                  child: ContactAvatarWidget(
                                    handle: reactions[i].handleRelation.target,
                                    borderThickness: 0.1,
                                    editable: false,
                                    fontSize: 16,
                                    size: 40,
                                  ),
                                ),
                                Positioned(right: -2, bottom: -2, child: badge(reactions[i])),
                              ],
                            ),
                          ),
                          if ((_nameFor(reactions[i]) ?? "").isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _nameFor(reactions[i])!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.theme.textTheme.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (SettingsSvc.settings.skin.value == Skins.Material) return _material3(context);
    return Obx(
      () => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            alignment: Alignment.center,
            height: 120,
            color: context.theme.colorScheme.surfaceContainerHighest
                .withAlpha(useIosTapbacks ? 150 : 255),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: ListView.separated(
                shrinkWrap: true,
                physics: ThemeSwitcher.getScrollPhysics(),
                scrollDirection: Axis.horizontal,
                findChildIndexCallback: (key) => findChildIndexByKey(reactions, key, (item) => item.guid),
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final message = reactions[index];
                  final handle = message.handleRelation.target;
                  String? reactionName;
                  if (!SettingsSvc.settings.hideNamesForReactions.value) {
                    if (message.isFromMe!) {
                      reactionName = SettingsSvc.settings.userName.value;
                    } else if (handle != null) {
                      reactionName = HandleSvc.getOrCreateHandleState(handle).reactionDisplayName.value;
                    }
                  }
                  return Column(
                    key: ValueKey(message.guid!),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 10),
                        child: ContactAvatarWidget(
                          handle: handle,
                          borderThickness: 0.1,
                          editable: false,
                          fontSize: 22,
                        ),
                      ),
                      if (reactionName != null && reactionName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            reactionName,
                            style: context.theme.textTheme.bodySmall!
                                .copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      else
                        const SizedBox(height: 8),
                      Container(
                        height: 28,
                        width: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: message.isFromMe!
                              ? context.theme.colorScheme.primary
                              : context.theme.colorScheme.surfaceContainerHighest,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 1.0,
                              color: context.theme.colorScheme.outline,
                            )
                          ],
                        ),
                        child: Padding(
                          padding: useIosTapbacks
                              ? const EdgeInsets.only(top: 8.0, left: 7.0, right: 7.0, bottom: 7.0)
                                  .add(EdgeInsets.only(right: message.associatedMessageType == "emphasize" ? 1 : 0))
                              : EdgeInsets.zero,
                          child: useIosTapbacks
                              ? SvgPicture.asset(
                                  'assets/reactions/${message.associatedMessageType}-black.svg',
                                  colorFilter: ColorFilter.mode(
                                    message.associatedMessageType == "love"
                                        ? Colors.pink
                                        : message.isFromMe!
                                            ? context.theme.colorScheme.onPrimary
                                            : context.theme.colorScheme.onSurfaceVariant,
                                    BlendMode.srcIn,
                                  ),
                                )
                              : Center(
                                  child: Builder(builder: (context) {
                                    final text = Text(
                                      ReactionTypes.reactionToEmoji[message.associatedMessageType] ?? "X",
                                      style: const TextStyle(fontSize: 18, fontFamily: 'Apple Color Emoji'),
                                      textAlign: TextAlign.center,
                                    );
                                    if (message.associatedMessageType == "dislike") {
                                      return Transform(
                                        transform: Matrix4.identity()..rotateY(pi),
                                        alignment: FractionalOffset.center,
                                        child: text,
                                      );
                                    }
                                    return text;
                                  }),
                                ),
                        ),
                      )
                    ],
                  );
                },
                itemCount: reactions.length,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
