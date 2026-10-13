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

  @override
  Widget build(BuildContext context) {
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


/// Who reacted, as the header of the Material 3 long-press menu.
///
/// Up to [maxRows] people are listed one per row: avatar, name, their tapback
/// at the end. With more people, or with names hidden in settings, it becomes a
/// single scrolling line of avatars carrying the tapback as a corner badge.
class MenuReactors extends StatelessWidget {
  const MenuReactors({super.key, required this.reactions});

  final List<Message> reactions;

  static const int maxRows = 3;
  static const double rowHeight = 40;
  static const double stripHeight = 52;

  // The setting is read first so that the Obx in build always has an
  // observable to listen to; Obx throws when its builder reads none.
  static bool _asRows(List<Message> reactions) =>
      !SettingsSvc.settings.hideNamesForReactions.value && reactions.length <= maxRows;

  /// The height this header takes for [reactions], divider included. The popup
  /// positions the bubble and the tapback bar from the menu's height, so it
  /// needs this before layout.
  static double heightFor(List<Message> reactions) {
    if (reactions.isEmpty) return 0;
    return (_asRows(reactions) ? reactions.length * rowHeight : stripHeight) + 9;
  }

  static String _nameFor(Message message) {
    final handle = message.handleRelation.target;
    if (message.isFromMe!) return "You";
    if (handle != null) return HandleSvc.getOrCreateHandleState(handle).reactionDisplayName.value ?? "";
    return "";
  }

  Widget _glyph(BuildContext context, Message message, double size, Color color) {
    final type = message.associatedMessageType;
    if (type == ReactionTypes.EMOJI && message.associatedMessageEmoji != null) {
      return Text(message.associatedMessageEmoji!,
          style: TextStyle(fontSize: size, fontFamily: 'Apple Color Emoji', height: 1.1));
    }
    if (useIosTapbacks) {
      return SvgPicture.asset(
        'assets/reactions/$type-black.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(type == "love" ? Colors.pink : color, BlendMode.srcIn),
      );
    }
    final text = Text(ReactionTypes.reactionToEmoji[type] ?? "",
        style: TextStyle(fontSize: size, fontFamily: 'Apple Color Emoji', height: 1.1));
    return type == "dislike"
        ? Transform(transform: Matrix4.identity()..rotateY(pi), alignment: FractionalOffset.center, child: text)
        : text;
  }

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final scheme = context.theme.colorScheme;
    return Obx(() {
      final Widget body;
      if (_asRows(reactions)) {
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reactions)
              SizedBox(
                height: rowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ContactAvatarWidget(
                        handle: r.handleRelation.target,
                        borderThickness: 0.1,
                        editable: false,
                        fontSize: 10,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _nameFor(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _glyph(context, r, 18, scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
          ],
        );
      } else {
        body = SizedBox(
          height: stripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: reactions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: 40,
              height: 36,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ContactAvatarWidget(
                    handle: reactions[i].handleRelation.target,
                    borderThickness: 0.1,
                    editable: false,
                    fontSize: 13,
                    size: 32,
                  ),
                  Positioned(
                    right: 0,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.secondaryContainer,
                        border: Border.all(color: scheme.surfaceContainer, width: 1.5),
                      ),
                      child: _glyph(context, reactions[i], 11, scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: body),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ],
      );
    });
  }
}
