import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';

/// Stateful widget that animates a reaction pop-in only once
class _ReactionAnimator extends StatefulWidget {
  const _ReactionAnimator({
    super.key,
    required this.stableKey,
    required this.child,
  });

  final String stableKey;
  final Widget child;

  @override
  State<_ReactionAnimator> createState() => _ReactionAnimatorState();
}

class _ReactionAnimatorState extends State<_ReactionAnimator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    // Animate in once
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}

class ReactionHolder extends StatefulWidget {
  const ReactionHolder({
    super.key,
    required this.reactions,
    required this.message,
  });

  final Iterable<Message> reactions;
  final Message message;

  @override
  State<ReactionHolder> createState() => _ReactionHolderState();
}

class _ReactionHolderState extends OptimizedState<ReactionHolder> {
  Iterable<Message> get reactions => getUniqueReactionMessages(widget.reactions.toList());

  // Cache the unique reactions to prevent unnecessary rebuilds
  late List<Message> _cachedReactions;

  @override
  void initState() {
    super.initState();
    _cachedReactions = reactions.toList();
  }

  @override
  void didUpdateWidget(ReactionHolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild if reactions actually changed
    if (!_reactionsEqual(oldWidget.reactions, widget.reactions)) {
      _cachedReactions = reactions.toList();
    }
  }

  /// Check if two reaction lists are equal by comparing GUIDs
  /// This prevents unnecessary rebuilds when the same data is passed
  bool _reactionsEqual(Iterable<Message> a, Iterable<Message> b) {
    final listA = a.toList();
    final listB = b.toList();
    if (listA.length != listB.length) return false;
    for (int i = 0; i < listA.length; i++) {
      if (listA[i].guid != listB[i].guid) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // If the reactions are empty, return nothing
    if (_cachedReactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 35,
      width: 35,
      child: Stack(
        clipBehavior: Clip.none,
        children: _cachedReactions
            .asMap()
            .entries
            .map((entry) {
              final i = entry.key;
              final e = entry.value;
              // Use a stable key based on parent + reaction type + sender
              // This prevents re-animation when temp GUID -> real GUID replacement happens
              final sender = e.handleId ?? '0';
              final stableKey = '${e.associatedMessageGuid}-${e.associatedMessageType}-$sender';
              
              return Positioned(
                key: ValueKey(stableKey),
                top: 0,
                left: !widget.message.isFromMe! ? null : -i * 2.0,
                right: widget.message.isFromMe! ? null : -i * 2.0,
                child: _ReactionAnimator(
                  key: ValueKey(stableKey),
                  stableKey: stableKey,
                  child: DeferPointer(
                    child: ReactionWidget(
                      message: widget.message,
                      reaction: e,
                      reactions: _cachedReactions,
                    ),
                  ),
                ),
              );
            })
            .toList()
            .reversed
            .toList(),
      ),
    );
  }
}
