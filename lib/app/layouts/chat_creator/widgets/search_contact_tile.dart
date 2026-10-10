import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart' show SelectedContact;
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator_controller.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A single contact row inside the search results list.
///
/// For each [ContactV2], this widget renders one row per unique phone number
/// and one row per unique email address (duplicates are filtered out by their
/// numeric-only representation, matching the existing [ChatListSection] logic).
class SearchContactTile extends StatelessWidget {
  const SearchContactTile({
    super.key,
    required this.contact,
    required this.controller,
    this.listedChatGuids = const {},
  });

  /// Chats already shown in the Conversations section; an address whose chat
  /// is among them is not repeated here.
  final Set<String> listedChatGuids;

  final ContactV2 contact;
  final ChatCreatorController controller;

  @override
  Widget build(BuildContext context) {
    // Deduplicate phone numbers and email addresses.
    final seenNumbers = <String>{};
    final uniquePhones = contact.phoneNumbers.where((p) => seenNumbers.add(p.number.numericOnly())).toList();

    final seenAddresses = <String>{};
    final uniqueEmails = contact.emailAddresses.where((e) => seenAddresses.add(e.address.trim())).toList();

    if (uniquePhones.isEmpty && uniqueEmails.isEmpty) return const SizedBox.shrink();

    return Obx(() {
      final hideInfo = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value;
      // Email addresses are only valid for iMessage
      final showEmails = controller.selectedService.value.isIMessageService;

      // One entry per address, ranked by when that address was last used:
      // the number you text sits first, a number you have never messaged
      // last. Addresses whose chat is already listed above are left out.
      final entries = <_AddressEntry>[
        for (final p in uniquePhones) _AddressEntry(p.number, p.label, controller.chatForAddress(p.number)),
        if (showEmails)
          for (final e in uniqueEmails) _AddressEntry(e.address, e.label, controller.chatForAddress(e.address)),
      ].where((e) => e.chat == null || !listedChatGuids.contains(e.chat!.guid)).toList();
      if (entries.isEmpty) return const SizedBox.shrink();
      entries.sort((a, b) {
        final da = a.chat == null ? null : controller.lastMessageDate(a.chat!);
        final db = b.chat == null ? null : controller.lastMessageDate(b.chat!);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      return Column(
        key: ValueKey(contact.nativeContactId),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            _ContactAddressRow(
              displayName: hideInfo ? 'Contact' : contact.computedDisplayName,
              address: hideInfo ? '' : entry.address,
              label: hideInfo ? null : entry.label,
              lastUsed: entry.chat == null ? null : controller.lastMessageDate(entry.chat!),
              contact: contact,
              onTap: () {
                if (controller.selectedContacts.firstWhereOrNull((c) => c.address == entry.address) != null) {
                  return;
                }
                controller.addSelected(
                  SelectedContact(
                    displayName: contact.computedDisplayName,
                    address: entry.address,
                  ),
                );
              },
            ),
        ],
      );
    });
  }
}

class _AddressEntry {
  const _AddressEntry(this.address, this.label, this.chat);

  final String address;
  final String? label;
  final Chat? chat;
}

class _ContactAddressRow extends StatelessWidget {
  const _ContactAddressRow({
    required this.displayName,
    required this.address,
    required this.contact,
    required this.onTap,
    this.label,
    this.lastUsed,
  });

  final String displayName;
  final String address;
  final String? label;
  final ContactV2 contact;
  final VoidCallback onTap;

  /// When this address was last messaged, if ever.
  final DateTime? lastUsed;

  @override
  Widget build(BuildContext context) {
    final subtitle = (label != null && label!.isNotEmpty) ? '$address  •  $label' : address;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          dense: SettingsSvc.settings.denseChatTiles.value,
          minVerticalPadding: 10,
          leading: ContactAvatarWidget(
            handle: null,
            contact: contact,
            size: 40,
            borderThickness: 0.1,
          ),
          title: Text(
            displayName,
            style: context.theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: context.theme.colorScheme.outline,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: lastUsed == null
              ? null
              : Text(
                  buildDate(lastUsed),
                  style: context.theme.textTheme.bodySmall?.copyWith(color: context.theme.colorScheme.outline),
                ),
        ),
      ),
    );
  }
}
