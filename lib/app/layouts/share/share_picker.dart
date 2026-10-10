import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart' show SelectedContact;
import 'package:bluebubbles/app/layouts/chat_creator/new_chat_creator.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/state/chat_state.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Where content shared from another app lands: a list of recent
/// conversations (same order as the chat list), a search over conversations
/// and contacts, and a compose button for a brand-new chat. Picking a
/// conversation opens it with the shared text/files in the composer through
/// the same path the direct-share shortcuts use, so nothing here sends.
///
/// Modelled on AOSP Messaging's ShareIntentActivity and Google Messages'
/// Share screen.
class SharePicker extends StatefulWidget {
  const SharePicker({super.key, this.text, this.attachments = const []});

  final String? text;
  final List<PlatformFile> attachments;

  @override
  State<SharePicker> createState() => _SharePickerState();
}

/// One contact address, with the chat (if any) it already has.
class _AddressHit {
  _AddressHit({required this.contact, required this.address, this.label, this.chat});

  final ContactV2 contact;
  final String address;
  final String? label;
  final Chat? chat;

  DateTime? get lastDate =>
      chat == null ? null : (ChatsSvc.getChatState(chat!.guid)?.latestMessage.value?.dateCreated ?? chat!.dbOnlyLatestMessageDate);
}

class _SharePickerState extends State<SharePicker> with ThemeHelpers {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  List<ContactV2> _contacts = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    ContactsSvcV2.getAllContacts().then((c) {
      if (mounted) setState(() => _contacts = c);
    }).catchError((e, s) {
      Logger.warn("Share picker could not load contacts", error: e, trace: s, tag: "SharePicker");
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  String get _summary {
    final parts = <String>[];
    if (widget.attachments.isNotEmpty) {
      parts.add("${widget.attachments.length} file${widget.attachments.length == 1 ? "" : "s"}");
    }
    if (widget.text != null && widget.text!.trim().isNotEmpty) parts.add(widget.text!.trim());
    return parts.join("  •  ");
  }

  /// Chats shown in the list: the real conversations, in chat-list order.
  List<Chat> get _recentChats =>
      ChatsSvc.allChats.where((c) => !c.isRoutingStub && c.dateDeleted == null).toList();

  // ---------------------------------------------------------------------------
  // Matching

  static String _digits(String s) => s.replaceAll(RegExp(r"[^0-9]"), "");

  bool _chatMatches(Chat chat, String q, String qDigits) {
    if (chat.getTitle().toLowerCase().contains(q)) return true;
    for (final h in chat.handles) {
      if (h.displayName.toLowerCase().contains(q)) return true;
      if (h.address.toLowerCase().contains(q)) return true;
      if (qDigits.length >= 3 && _digits(h.address).contains(qDigits)) return true;
    }
    return false;
  }

  /// The 1:1 chat for [address], if one exists in the list.
  Chat? _chatForAddress(String address) {
    final isEmail = address.isEmail;
    final digits = isEmail ? "" : _digits(address);
    for (final c in _recentChats) {
      if (c.handles.length != 1) continue;
      final h = c.handles.first.address;
      if (isEmail) {
        if (h.toLowerCase() == address.toLowerCase()) return c;
      } else if (digits.length >= 7 && _digits(h).endsWith(digits)) {
        return c;
      }
    }
    return null;
  }

  List<_AddressHit> _contactHits(String q, String qDigits) {
    final hits = <_AddressHit>[];
    for (final c in _contacts) {
      final nameMatch =
          c.computedDisplayName.toLowerCase().contains(q) || (c.nickname?.toLowerCase().contains(q) ?? false);
      final seen = <String>{};
      for (final p in c.phoneNumbers) {
        if (!seen.add(_digits(p.number))) continue;
        if (nameMatch || (qDigits.length >= 3 && _digits(p.number).contains(qDigits))) {
          hits.add(_AddressHit(contact: c, address: p.number, label: p.label, chat: _chatForAddress(p.number)));
        }
      }
      for (final e in c.emailAddresses) {
        if (!seen.add(e.address.toLowerCase())) continue;
        if (nameMatch || e.address.toLowerCase().contains(q)) {
          hits.add(_AddressHit(contact: c, address: e.address, label: e.label, chat: _chatForAddress(e.address)));
        }
      }
    }
    // Addresses you actually talk to first, most recent first; the rest keep
    // contact order.
    hits.sort((a, b) {
      final da = a.lastDate, db = b.lastDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return hits;
  }

  // ---------------------------------------------------------------------------
  // Actions

  Future<void> _openChat(Chat chat) async {
    Logger.info("Share picker: opening chat ${chat.guid} with ${widget.attachments.length} file(s), text ${widget.text?.shorten(20) ?? 'none'}",
        tag: "SharePicker");
    ChatsSvc.getOrCreateChatState(chat);
    final controller = cvc(chat);
    if (widget.attachments.isNotEmpty) controller.pickedAttachments.value = List.of(widget.attachments);
    if (widget.text != null && widget.text!.isNotEmpty) controller.textController.text = widget.text!;
    await NavigationSvc.pushAndRemoveUntil(context, ConversationView(chat: chat), (route) => route.isFirst);
  }

  void _openNewChat({SelectedContact? preselected}) {
    NavigationSvc.pushAndRemoveUntil(
      context,
      NewChatCreator(
        initialText: widget.text,
        initialAttachments: widget.attachments,
        initialSelected: preselected == null ? const [] : [preselected],
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _onAddressTap(_AddressHit hit) async {
    if (hit.chat != null) return _openChat(hit.chat!);
    _openNewChat(preselected: SelectedContact(displayName: hit.contact.computedDisplayName, address: hit.address));
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final qDigits = _digits(q);
    final scheme = context.theme.colorScheme;

    return Scaffold(
      backgroundColor: samsung ? scheme.surfaceContainer : scheme.surface,
      appBar: _appBar(context, scheme),
      floatingActionButton: _fab(context, scheme),
      body: Obx(() {
        ChatsSvc.chatListVersion.value;
        final chats = _recentChats;
        final List<Chat> shownChats = q.isEmpty ? chats : chats.where((c) => _chatMatches(c, q, qDigits)).toList();
        final hits = q.isEmpty ? const <_AddressHit>[] : _contactHits(q, qDigits);
        // Contacts whose chat is already listed are not repeated.
        final listedGuids = shownChats.map((c) => c.guid).toSet();
        final contactRows = hits.where((h) => h.chat == null || !listedGuids.contains(h.chat!.guid)).toList();

        return CustomScrollView(
          slivers: [
            if (_summary.isNotEmpty) SliverToBoxAdapter(child: _sharedPreview(scheme)),
            if (shownChats.isNotEmpty) _header(q.isEmpty ? "Recent conversations" : "Conversations", scheme),
            _block(
              scheme,
              SliverList.separated(
                itemCount: shownChats.length,
                separatorBuilder: (_, __) => _divider(scheme),
                itemBuilder: (context, i) => _ChatRow(chat: shownChats[i], onTap: () => _openChat(shownChats[i])),
              ),
            ),
            if (contactRows.isNotEmpty) _header("Contacts", scheme),
            if (contactRows.isNotEmpty)
              _block(
                scheme,
                SliverList.separated(
                  itemCount: contactRows.length,
                  separatorBuilder: (_, __) => _divider(scheme),
                  itemBuilder: (context, i) => _ContactRow(hit: contactRows[i], onTap: () => _onAddressTap(contactRows[i])),
                ),
              ),
            if (q.isNotEmpty && shownChats.isEmpty && contactRows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text("No matches", style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.outline)),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        );
      }),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, ColorScheme scheme) {
    final searchField = TextField(
      controller: _query,
      focusNode: _queryFocus,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: "Search conversations and contacts",
        hintStyle: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    return AppBar(
      backgroundColor: samsung ? scheme.surfaceContainer : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(iOS ? CupertinoIcons.back : Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: _searching
          ? searchField
          : Text("Share to", style: context.theme.textTheme.titleLarge!.copyWith(color: scheme.onSurface)),
      actions: [
        IconButton(
          tooltip: _searching ? "Close search" : "Search",
          icon: Icon(_searching ? Icons.close : (iOS ? CupertinoIcons.search : Icons.search)),
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            });
            if (_searching) _queryFocus.requestFocus();
          },
        ),
      ],
    );
  }

  /// The compose button, drawn like each skin's chat-list button.
  Widget _fab(BuildContext context, ColorScheme scheme) {
    if (material) {
      final isMonet = ThemeSvc.isAnyMaterialYouSelected;
      final bg = isMonet ? scheme.primaryContainer : scheme.primary;
      final fg = isMonet ? scheme.onPrimaryContainer : scheme.onPrimary;
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        child: InkWell(
          onTap: _openNewChat,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.bubble_left, color: fg, size: 24),
                  const SizedBox(width: 10),
                  Text("New chat",
                      style: context.theme.textTheme.labelLarge!.copyWith(color: fg, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return FloatingActionButton(
      backgroundColor: scheme.primary,
      onPressed: _openNewChat,
      child: Icon(iOS ? CupertinoIcons.pencil : Icons.message, color: scheme.onPrimary, size: 25),
    );
  }

  Widget _sharedPreview(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(widget.attachments.isNotEmpty ? Icons.attach_file : Icons.notes, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text, ColorScheme scheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(samsung ? 24 : 16, 14, 16, 6),
        child: Text(
          text,
          style: context.theme.textTheme.labelLarge!.copyWith(
            color: iOS ? scheme.outline : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Samsung gets its rounded block; the others a plain list.
  Widget _block(ColorScheme scheme, Widget sliver) {
    if (!samsung) return sliver;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(26)),
        sliver: SliverPadding(padding: const EdgeInsets.symmetric(vertical: 6), sliver: sliver),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => iOS
      ? Padding(
          padding: const EdgeInsets.only(left: 72),
          child: Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant),
        )
      : const SizedBox.shrink();
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.onTap});

  final Chat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ChatState state = ChatsSvc.getOrCreateChatState(chat);
    final scheme = context.theme.colorScheme;
    return ChatStateScope(
      chatState: state,
      child: Obx(() {
        final latest = state.latestMessage.value;
        final subtitle = state.subtitle.value ?? "";
        final date = latest == null ? "" : buildDate(latest.chatViewDate);
        return ListTile(
          onTap: onTap,
          minVerticalPadding: 10,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: ContactAvatarGroupWidget(chat: chat, size: 44, editable: false),
          title: Text(
            state.title.value ?? chat.getTitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface).apply(fontSizeFactor: 1.05),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
                ),
          trailing: date.isEmpty
              ? null
              : Text(date, style: context.theme.textTheme.bodySmall!.copyWith(color: scheme.outline)),
        );
      }),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.hit, required this.onTap});

  final _AddressHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final last = hit.lastDate;
    final sub = [
      hit.address.isEmail ? hit.address : formatPhoneNumber(hit.address),
      if (hit.label != null && hit.label!.isNotEmpty) hit.label!,
    ].join("  •  ");
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: ContactAvatarWidget(handle: null, contact: hit.contact, size: 44, borderThickness: 0.1),
      title: Text(
        hit.contact.computedDisplayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface).apply(fontSizeFactor: 1.05),
      ),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: last == null
          ? null
          : Text(buildDate(last), style: context.theme.textTheme.bodySmall!.copyWith(color: scheme.outline)),
    );
  }
}
