import 'package:bluebubbles/app/layouts/conversation_details/dialogs/add_participant.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/contact_tile.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Widget that handles rendering the participants list with show more/less functionality
class ParticipantsList extends StatefulWidget {
  final Chat chat;

  const ParticipantsList({
    super.key,
    required this.chat,
  });

  @override
  State<ParticipantsList> createState() => _ParticipantsListState();
}

class _ParticipantsListState extends OptimizedState<ParticipantsList> {
  bool showMoreParticipants = false;

  bool get shouldShowMore => widget.chat.participants.length > 5;
  
  List<Handle> get clippedParticipants => showMoreParticipants
      ? widget.chat.participants
      : widget.chat.participants.take(5).toList();

  @override
  Widget build(BuildContext context) {
    if (!widget.chat.isGroup) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final addMember = ListTile(
            mouseCursor: MouseCursor.defer,
            title: Text(
              "Add ${iOS ? "Member" : "people"}",
              style: context.theme.textTheme.bodyLarge!.copyWith(
                color: context.theme.colorScheme.primary,
              ),
            ),
            leading: Container(
              width: 40 * SettingsSvc.settings.avatarScale.value,
              height: 40 * SettingsSvc.settings.avatarScale.value,
              decoration: BoxDecoration(
                color: !iOS ? null : context.theme.colorScheme.properSurface,
                shape: BoxShape.circle,
                border: iOS
                    ? null
                    : Border.all(
                        color: context.theme.colorScheme.primary,
                        width: 3,
                      ),
              ),
              child: Icon(
                Icons.add,
                color: context.theme.colorScheme.primary,
                size: 20,
              ),
            ),
            onTap: () {
              showAddParticipant(context, widget.chat);
            },
          );

          if (index > clippedParticipants.length) {
            if (SettingsSvc.settings.enablePrivateAPI.value &&
                widget.chat.isIMessage &&
                widget.chat.isGroup &&
                shouldShowMore) {
              return addMember;
            } else {
              return const SizedBox.shrink();
            }
          }
          
          if (index == clippedParticipants.length) {
            if (shouldShowMore) {
              return ListTile(
                mouseCursor: SystemMouseCursors.click,
                onTap: () {
                  setState(() {
                    showMoreParticipants = !showMoreParticipants;
                  });
                },
                title: Text(
                  showMoreParticipants ? "Show less" : "Show more",
                  style: context.theme.textTheme.bodyLarge!.copyWith(
                    color: context.theme.colorScheme.primary,
                  ),
                ),
                leading: Container(
                  width: 40 * SettingsSvc.settings.avatarScale.value,
                  height: 40 * SettingsSvc.settings.avatarScale.value,
                  decoration: BoxDecoration(
                    color: !iOS ? null : context.theme.colorScheme.properSurface,
                    shape: BoxShape.circle,
                    border: iOS
                        ? null
                        : Border.all(
                            color: context.theme.colorScheme.primary,
                            width: 3,
                          ),
                  ),
                  child: Icon(
                    Icons.more_horiz,
                    color: context.theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              );
            } else if (SettingsSvc.settings.enablePrivateAPI.value &&
                widget.chat.isIMessage &&
                widget.chat.isGroup) {
              return addMember;
            } else {
              return const SizedBox.shrink();
            }
          }

          return ContactTile(
            key: Key(widget.chat.participants[index].address),
            handle: widget.chat.participants[index],
            chat: widget.chat,
            canBeRemoved: widget.chat.isGroup &&
                SettingsSvc.settings.enablePrivateAPI.value &&
                widget.chat.isIMessage,
          );
        },
        childCount: clippedParticipants.length + 2,
      ),
    );
  }
}
