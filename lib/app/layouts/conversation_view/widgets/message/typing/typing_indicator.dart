import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/typing/typing_clipper.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.visible,
    this.controller,
    this.scale = 1.0,
  });

  final bool? visible;
  final ConversationViewController? controller;
  final double scale;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin, ThemeHelpers {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  /// Whether the bubble content is present in the tree (false only after the
  /// hide animation has fully completed).
  bool _isShowing = false;

  /// GetX worker that reacts to [ConversationViewController.showTypingIndicator]
  /// changes. Only created when a controller is provided.
  Worker? _visibilityWorker;

  /// OpenBubbles reports typing per participant ([showTypingIndicatorFor]);
  /// the BlueBubbles socket path sets the plain [showTypingIndicator] flag.
  bool get _currentVisibility {
    final controller = widget.controller;
    if (controller == null) return widget.visible ?? false;
    return controller.showTypingIndicator.value || controller.showTypingIndicatorFor.isNotEmpty;
  }

  /// The icon of the iMessage app the (single) other party is typing in, if any.
  Uint8List? get _typingAppIcon {
    final controller = widget.controller;
    if (controller == null || controller.showTypingIndicatorFor.length != 1) return null;
    return controller.typingIndicatorData[controller.showTypingIndicatorFor.first.address]?.$2;
  }

  Widget _appIconBubble(Uint8List icon, {double? height}) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Image.memory(icon),
        ),
      );

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    // After the hide animation finishes, remove the content from the tree so
    // it no longer occupies layout space.
    _scaleController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _isShowing = false);
      }
    });

    _isShowing = _currentVisibility;
    if (_isShowing) {
      _scaleController.forward(from: 0.0);
    }

    // When a controller is provided, use a GetX worker to reliably observe
    // the reactive observable. This is more direct than relying on
    // didUpdateWidget, which can miss repaints for scale-only changes.
    if (widget.controller != null) {
      _visibilityWorker = everAll(
        [widget.controller!.showTypingIndicator, widget.controller!.showTypingIndicatorFor],
        (_) => _onVisibilityChanged(_currentVisibility),
      );
    }
  }

  void _onVisibilityChanged(bool isVisible) {
    if (!mounted) return;
    if (isVisible && !_isShowing) {
      setState(() => _isShowing = true);
      _scaleController.forward(from: 0.0);
    } else if (!isVisible && _isShowing) {
      // _scaleController status listener will set _isShowing = false once dismissed.
      _scaleController.reverse();
    }
  }

  @override
  void dispose() {
    _visibilityWorker?.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Widget _buildBubble(BuildContext context) {
    final appIcon = _typingAppIcon;
    final typingFor = widget.controller?.showTypingIndicatorFor ?? const <Handle>[];
    if (iOS || ChatStateScope.maybeChatOf(context) == null) {
      // The clipped speech bubble grows to fit the app icon when there is one.
      return ClipPath(
        clipper: const TypingClipper(),
        child: Container(
          height: 50,
          width: appIcon == null ? 80 : null,
          color: context.theme.colorScheme.surfaceContainerHighest,
          padding: appIcon == null ? null : const EdgeInsets.fromLTRB(30, 10, 14, 20),
          child: appIcon == null
              ? const Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 15,
                      right: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedDot(index: 2),
                          AnimatedDot(index: 1),
                          AnimatedDot(index: 0),
                        ],
                      ),
                    )
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _appIconBubble(appIcon),
                    const AnimatedDot(index: 2),
                    const AnimatedDot(index: 1),
                    const AnimatedDot(index: 0),
                  ],
                ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, right: 10),
          // OpenBubbles knows exactly who is typing, so show those handles
          // rather than the whole chat. Note this deliberately does NOT use
          // ContactAvatarGroupWidget: inside a ChatStateScope that widget
          // ignores its `handles`/`participants` argument and renders every
          // participant of the chat.
          child: typingFor.isEmpty
              ? ContactAvatarWidget(
                  handle: ChatStateScope.chatOf(context).handles.first,
                  size: 25,
                  fontSize: context.theme.textTheme.bodyMedium!.fontSize!,
                  borderThickness: 0.1,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: typingFor
                      .take(3)
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: ContactAvatarWidget(
                              handle: h,
                              size: 25,
                              editable: false,
                              fontSize: context.theme.textTheme.bodyMedium!.fontSize!,
                              borderThickness: 0.1,
                            ),
                          ))
                      .toList(),
                ),
        ),
        if (appIcon != null) _appIconBubble(appIcon, height: 25),
        const AnimatedDot(index: 2),
        const AnimatedDot(index: 1),
        const AnimatedDot(index: 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _isShowing
          ? ScaleTransition(
              scale: _scaleAnimation,
              // Anchor the grow/shrink at the bottom-left — the tail of the
              // speech bubble — so it feels like a real iMessage bubble.
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _buildBubble(context),
              ))
          : const SizedBox.shrink(),
    );
  }
}

class AnimatedDot extends StatefulWidget {
  final int index;
  const AnimatedDot({super.key, required this.index});

  @override
  State<AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<AnimatedDot> with SingleTickerProviderStateMixin, ThemeHelpers {
  late final AnimationController _controller;
  late final Animation animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700), animationBehavior: AnimationBehavior.preserve);
    _controller.addStatusListener((state) {
      if (state == AnimationStatus.completed && mounted) {
        _controller.forward(from: 0.0);
      }
    });

    animation = Tween(
      begin: 0.0,
      end: math.pi,
    ).animate(_controller);

    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (iOS) {
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final amt = (math.sin(animation.value + (widget.index) * math.pi / 4).abs() * 20).clamp(1, 20).toDouble();
          return Container(
            decoration: BoxDecoration(
              color: ThemeSvc.inDarkMode(context)
                  ? context.theme.colorScheme.surfaceContainerHighest.lightenPercent(amt)
                  : context.theme.colorScheme.surfaceContainerHighest.darkenPercent(amt),
              shape: BoxShape.circle,
            ),
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 2),
          );
        },
      );
    } else {
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: (math.sin(animation.value + (widget.index) * math.pi / 4).abs() * 20).clamp(1, 20).toDouble()),
            child: Container(
              decoration: BoxDecoration(
                color: context.theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
            ),
          );
        },
      );
    }
  }
}
