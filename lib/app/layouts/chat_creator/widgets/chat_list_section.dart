import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/layouts/chat_creator/widgets/chat_creator_tile.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/app/components/base/base.dart';

/// Extracted widget for the chat/contact list to isolate rebuilds
/// Only rebuilds when filteredChats or filteredContacts changes
class ChatListSection extends StatelessWidget {
  const ChatListSection({
    super.key,
    required this.filteredChats,
    required this.filteredContacts,
    required this.onChatTap,
    required this.onContactTap,
    required this.selectedContacts,
  });

  final List<Chat> filteredChats;
  final List<Contact> filteredContacts;
  final Function(List<SelectedContact>) onChatTap;
  final Function(SelectedContact) onContactTap;
  final List<SelectedContact> selectedContacts;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: ThemeSwitcher.getScrollPhysics(),
      slivers: <Widget>[
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (filteredChats.isEmpty) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Loading existing chats...",
                      style: context.theme.textTheme.labelLarge,
                    ),
                  ),
                  const BBLoadingIndicator(size: 15),
                ],
              );
            }
            final chat = filteredChats[index];
            final hideInfo = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value;
            String title = chat.properTitle;
            if (hideInfo) {
              title = chat.isGroup ? chat.fakeName : chat.handles[0].fakeName;
            }
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  onChatTap(chat.handles
                      .where((e) => selectedContacts.firstWhereOrNull((c) => c.address == e.address) == null)
                      .map((e) => SelectedContact(
                            displayName: e.displayName,
                            address: e.address,
                            isIMessage: chat.isIMessage,
                          ))
                      .toList());
                },
                child: ChatCreatorTile(
                  key: ValueKey(chat.guid),
                  title: title,
                  subtitle: hideInfo
                      ? ""
                      : !chat.isGroup && chat.handles.isNotEmpty
                          ? (chat.handles.first.formattedAddress ?? chat.handles.first.address)
                          : chat.getChatCreatorSubtitle(),
                  chat: chat,
                ),
              ),
            );
          },
              childCount:
                  filteredChats.length.clamp(ChatsSvc.loadedAllChats.isCompleted ? 0 : 1, double.infinity).toInt()),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final contact = filteredContacts[index];
              contact.phones = getUniqueNumbers(contact.phones);
              contact.emails = getUniqueEmails(contact.emails);
              final hideInfo = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value;
              return Column(
                key: ValueKey(contact.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...contact.phones.map((e) => Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (selectedContacts.firstWhereOrNull((c) => c.address == e) != null) return;
                            onContactTap(SelectedContact(displayName: contact.displayName, address: e));
                          },
                          child: ChatCreatorTile(
                            title: hideInfo ? "Contact" : contact.displayName,
                            subtitle: hideInfo ? "" : e,
                            contact: contact,
                            format: true,
                          ),
                        ),
                      )),
                  ...contact.emails.map((e) => Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (selectedContacts.firstWhereOrNull((c) => c.address == e) != null) return;
                            onContactTap(SelectedContact(displayName: contact.displayName, address: e));
                          },
                          child: ChatCreatorTile(
                            title: hideInfo ? "Contact" : contact.displayName,
                            subtitle: hideInfo ? "" : e,
                            contact: contact,
                          ),
                        ),
                      )),
                ],
              );
            },
            childCount: filteredContacts.length,
          ),
        ),
      ],
    );
  }
}
