import 'dart:math';
import 'dart:ui';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PinnedTileTextBubble extends CustomStateful<ConversationTileController> {
  const PinnedTileTextBubble({
    super.key,
    required this.chat,
    required this.size,
    required super.parentController,
  });

  final Chat chat;
  final double size;

  @override
  State<StatefulWidget> createState() => PinnedTileTextBubbleState();
}

class PinnedTileTextBubbleState extends CustomState<PinnedTileTextBubble, void, ConversationTileController> {
  final bool leftSide = Random().nextBool();

  Chat get chat => widget.chat;
  double get size => widget.size;
  bool get showTail => !chat.isGroup;

  @override
  void initState() {
    super.initState();
    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  List<Color> getBubbleColors(Message? lastMessage) {
    List<Color> bubbleColors = [
      context.theme.colorScheme.bubble(context, chat.isIMessage),
      context.theme.colorScheme.bubble(context, chat.isIMessage)
    ];
    if (lastMessage == null) return bubbleColors;
    if (!SettingsSvc.settings.colorfulAvatars.value &&
        SettingsSvc.settings.colorfulBubbles.value &&
        !lastMessage.isFromMe!) {
      if (lastMessage.handleRelation.target?.color == null) {
        bubbleColors = toColorGradient(lastMessage.handleRelation.target?.address);
      } else {
        bubbleColors = [
          HexColor(lastMessage.handleRelation.target!.color!),
          HexColor(lastMessage.handleRelation.target!.color!).lightenAmount(0.075),
        ];
      }
    }
    return bubbleColors;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chatState = ChatsSvc.getChatState(controller.chat.guid);
      final lastMessage = chatState?.latestMessage.value;
      final subtitle = chatState?.subtitle.value ?? '';

      final unread = chatState?.hasUnreadMessage.value ?? false;
      // Null-safe isFromMe: treat null as false (unknown sender → show the bubble)
      final isFromMe = lastMessage?.isFromMe == true;
      if (!unread || lastMessage?.associatedMessageGuid != null || isFromMe || isNullOrEmpty(subtitle)) {
        return const SizedBox.shrink();
      }

      final background = getBubbleColors(lastMessage).first.withValues(alpha: 0.7);
      return Align(
        alignment: showTail
            ? leftSide
                ? Alignment.centerLeft
                : Alignment.centerRight
            : Alignment.center,
        child: Padding(
          padding: EdgeInsets.only(
            left: showTail
                ? leftSide
                    ? size * 0.06
                    : size * 0.02
                : size * 0.04,
            right: showTail
                ? leftSide
                    ? size * 0.02
                    : size * 0.06
                : size * 0.04,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (showTail)
                Positioned(
                  top: -size * 0.08,
                  right: leftSide ? null : size * 0.05,
                  left: leftSide ? size * 0.05 : null,
                  child: CustomPaint(
                    size: Size(size * 0.21, size * 0.105),
                    painter: TailPainter(leftSide: leftSide, background: background),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: showTail ? size * 0.3 : 0),
                child: ClipRRect(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(size * 0.125),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 3.0,
                        horizontal: 6.0,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size * 0.125),
                        color: background,
                      ),
                      child: Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: clampDouble((size ~/ 30).toDouble(), 1, 3).toInt(),
                        textAlign: TextAlign.center,
                        style: context.theme.textTheme.bodySmall!.copyWith(
                            fontSize: (size / 10).clamp(context.theme.textTheme.bodySmall!.fontSize!, double.infinity),
                            color: context.theme.colorScheme
                                .onBubble(context, chat.isIMessage)
                                .withValues(alpha: SettingsSvc.settings.colorfulBubbles.value ? 1 : 0.85)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class TailPainter extends CustomPainter {
  TailPainter({
    Key? key,
    required this.leftSide,
    required this.background,
  });

  final bool leftSide;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = background;
    Path path = Path();

    if (leftSide) {
      path.moveTo(size.width * 0.9355556, size.height * 0.1489091);
      path.cubicTo(size.width, size.height * 0.3262727, size.width * 0.6313889, size.height * 0.5667273,
          size.width * 0.7722222, size.height * 0.8181818);
      path.cubicTo(size.width * 0.8054444, size.height * 0.8875455, size.width * 0.9209444, size.height, size.width,
          size.height);
      path.cubicTo(size.width * 0.7504167, size.height, size.width * 0.2523611, size.height, 0, size.height);
      path.cubicTo(size.width * 0.2253889, size.height * 0.9245455, size.width * 0.2102778, size.height * 0.6476364,
          size.width * 0.5255556, size.height * 0.3018182);
      path.cubicTo(size.width * 0.7247778, size.height * 0.0966364, size.width * 0.8862222, size.height * 0.0308182,
          size.width * 0.9355556, size.height * 0.1489091);
      path.close();
    } else {
      path.moveTo(size.width * 0.0644444, size.height * 0.1489091);
      path.cubicTo(0, size.height * 0.3262727, size.width * 0.3686111, size.height * 0.5667273, size.width * 0.2277778,
          size.height * 0.8181818);
      path.cubicTo(
          size.width * 0.1945556, size.height * 0.8875455, size.width * 0.0790556, size.height, 0, size.height);
      path.cubicTo(size.width * 0.2495833, size.height, size.width * 0.7476389, size.height, size.width, size.height);
      path.cubicTo(size.width * 0.7746111, size.height * 0.9245455, size.width * 0.7987222, size.height * 0.6476364,
          size.width * 0.4744444, size.height * 0.3018182);
      path.cubicTo(size.width * 0.2752222, size.height * 0.0966364, size.width * 0.1137778, size.height * 0.0308182,
          size.width * 0.0644444, size.height * 0.1489091);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    final oldPainter = oldDelegate as TailPainter;
    return leftSide != oldPainter.leftSide || background != oldPainter.background;
  }
}
