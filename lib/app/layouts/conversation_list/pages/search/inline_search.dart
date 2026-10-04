import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/components/bb_chip.dart';
import 'package:bluebubbles/app/layouts/chat_selector_view/chat_selector_view.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/search/inline_search_controller.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/search/search_models.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/layouts/handle_selector_view/handle_selector_view.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// The full-width rounded search bar that takes the header's place while
/// searching: back arrow to leave, the field, a clear button, and a filter
/// button with a count badge.
class InlineSearchBar extends StatelessWidget {
  const InlineSearchBar({super.key, required this.search});

  final InlineSearchController search;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: scheme.surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: "Close search",
                icon: Icon(Icons.arrow_back, color: scheme.onSurface),
                onPressed: search.close,
              ),
              Expanded(
                child: TextField(
                  controller: search.textController,
                  focusNode: search.focusNode,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
                  cursorColor: scheme.primary,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: "Search messages and contacts",
                    hintStyle: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              Obx(() {
                if (search.isSearching.value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                    ),
                  );
                }
                if (search.term.value.isEmpty) return const SizedBox(width: 4);
                return IconButton(
                  tooltip: "Clear",
                  icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    search.textController.clear();
                    search.focusNode.requestFocus();
                  },
                );
              }),
              Obx(() {
                final n = search.filterCount;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: "Filters",
                      icon: Icon(Icons.tune, color: n > 0 ? scheme.primary : scheme.onSurfaceVariant),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        search.focusNode.unfocus();
                        _showFilters(context);
                      },
                    ),
                    if (n > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          child: Text(
                            "$n",
                            style: context.theme.textTheme.labelSmall!.copyWith(color: scheme.onPrimary, fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: context.theme.colorScheme.surfaceContainerLow,
      builder: (ctx) => _FilterSheet(search: search),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.search});

  final InlineSearchController search;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Obx(() {
      final showSender =
          !search.isFromMe.value && !search.isNotFromMe.value && (search.selectedChat.value?.isGroup ?? true);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text("Narrow message results", style: context.theme.textTheme.titleMedium),
                  const Spacer(),
                  if (search.filterCount > 0)
                    TextButton(onPressed: search.clearFilters, child: const Text("Clear all")),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  BBChip(
                    label: const Text("From me"),
                    selected: search.isFromMe.value,
                    showCheckmark: true,
                    onSelected: (v) {
                      search.isFromMe.value = v;
                      if (v) {
                        search.isNotFromMe.value = false;
                        search.selectedHandle.value = null;
                      }
                    },
                  ),
                  BBChip(
                    label: const Text("To me"),
                    selected: search.isNotFromMe.value,
                    showCheckmark: true,
                    onSelected: (v) {
                      search.isNotFromMe.value = v;
                      if (v) search.isFromMe.value = false;
                    },
                  ),
                  BBChip(
                    label: Text(
                      search.selectedChat.value == null
                          ? "In chat…"
                          : "In: ${ChatsSvc.getChatState(search.selectedChat.value!.guid)?.title.value ?? search.selectedChat.value!.getTitle()}",
                    ),
                    selected: search.selectedChat.value != null,
                    onDeleted: search.selectedChat.value == null ? null : () => search.selectedChat.value = null,
                    onPressed: () {
                      NavigationSvc.push(
                        context,
                        ChatSelectorView(
                          onSelect: (chat) {
                            search.selectedChat.value = chat;
                            if (!chat.isGroup) search.selectedHandle.value = null;
                          },
                        ),
                      );
                    },
                  ),
                  if (showSender)
                    BBChip(
                      label: Text(
                        search.selectedHandle.value == null
                            ? "From…"
                            : "From: ${search.selectedHandle.value!.displayName}",
                      ),
                      selected: search.selectedHandle.value != null,
                      onDeleted: search.selectedHandle.value == null ? null : () => search.selectedHandle.value = null,
                      onPressed: () {
                        NavigationSvc.push(
                          context,
                          HandleSelectorView(
                            forChat: search.selectedChat.value,
                            onSelect: (handle) => search.selectedHandle.value = handle,
                          ),
                        );
                      },
                    ),
                  BBChip(
                    label: Text(
                      search.sinceDate.value == null ? "Since…" : "Since ${buildDate(search.sinceDate.value)}",
                    ),
                    selected: search.sinceDate.value != null,
                    onDeleted: search.sinceDate.value == null ? null : () => search.sinceDate.value = null,
                    onPressed: () async {
                      final d = await showTimeframePicker(
                        "Since When?",
                        context,
                        customTimeframes: {
                          "1 Hour": 1,
                          "1 Day": 24,
                          "1 Week": 168,
                          "1 Month": 720,
                          "6 Months": 4320,
                          "1 Year": 8760,
                        },
                        selectionSuffix: "Ago",
                        useTodayYesterday: true,
                      );
                      if (d != null) search.sinceDate.value = d;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Filters apply to message results. Conversations always match by name, number or email.",
                style: context.theme.textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Results body shown in place of the chat list while searching.
class InlineSearchResults extends StatelessWidget {
  const InlineSearchResults({super.key, required this.search});

  final InlineSearchController search;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final term = search.term.value;
      if (term.length < InlineSearchController.minLength) {
        return _hint(context, "Type to search your conversations and messages");
      }
      final chats = search.chatHits;
      final messages = search.messageHits;
      if (search.searched.value && chats.isEmpty && messages.isEmpty && !search.isSearching.value) {
        return _hint(context, "No results for “$term”");
      }
      return CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (chats.isNotEmpty) _header(context, "Conversations"),
          if (chats.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ChatHit(chat: chats[i], term: term),
                childCount: chats.length,
              ),
            ),
          if (messages.isNotEmpty) _header(context, "Messages"),
          if (messages.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _MessageHit(item: messages[i], term: term),
                childCount: messages.length,
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom)),
        ],
      );
    });
  }

  Widget _header(BuildContext context, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(text, style: context.theme.textTheme.titleSmall!.copyWith(color: context.theme.colorScheme.primary)),
    ),
  );

  Widget _hint(BuildContext context, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// Highlights every occurrence of [term] in [text], case-insensitively.
List<InlineSpan> highlight(String text, String term, TextStyle base, TextStyle mark) {
  if (term.isEmpty) return [TextSpan(text: text, style: base)];
  final lower = text.toLowerCase();
  final needle = term.toLowerCase();
  final spans = <InlineSpan>[];
  int i = 0;
  while (true) {
    final at = lower.indexOf(needle, i);
    if (at < 0) {
      spans.add(TextSpan(text: text.substring(i), style: base));
      break;
    }
    if (at > i) spans.add(TextSpan(text: text.substring(i, at), style: base));
    spans.add(TextSpan(text: text.substring(at, at + needle.length), style: mark));
    i = at + needle.length;
  }
  return spans;
}

class _ChatHit extends StatelessWidget {
  const _ChatHit({required this.chat, required this.term});

  final Chat chat;
  final String term;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final state = ChatsSvc.getChatState(chat.guid);
    final title = state?.title.value ?? chat.getTitle();
    final base = context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface);
    final mark = base.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final subtitle = chat.isGroup
        ? "${chat.participants.length} people"
        : (chat.participants.firstOrNull?.formattedAddress ?? chat.participants.firstOrNull?.address ?? "");
    return ListTile(
      leading: ContactAvatarGroupWidget(chat: chat, size: 40, editable: false),
      title: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: highlight(title, term, base, mark)),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: highlight(
                  subtitle,
                  term,
                  context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
                  context.theme.textTheme.bodyMedium!.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
      onTap: () {
        NavigationSvc.pushAndRemoveUntil(context, ConversationView(chat: chat), (route) => route.isFirst);
      },
    );
  }
}

class _MessageHit extends StatelessWidget {
  const _MessageHit({required this.item, required this.term});

  final SearchResultItem item;
  final String term;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final chat = item.chat;
    final message = item.message;
    final subtitleStyle = context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant, height: 1.4);
    final mark = subtitleStyle.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);

    // Snippet around the first hit, so the match is visible in two lines.
    final full = message.fullText;
    final at = full.toLowerCase().indexOf(term.toLowerCase());
    final start = at < 0 ? 0 : (at - 40).clamp(0, full.length);
    final snippet = (start > 0 ? "…" : "") + full.substring(start);
    final whoPrefix = message.isFromMe == true
        ? "You: "
        : (chat.isGroup ? "${message.getHandle()?.displayName ?? ""}: " : "");

    return ListTile(
      leading: ContactAvatarGroupWidget(chat: chat, size: 40, editable: false),
      title: Row(
        children: [
          Expanded(
            child: Text(
              ChatsSvc.getChatState(chat.guid)?.title.value ?? chat.getTitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            buildDate(message.dateCreated),
            style: context.theme.textTheme.bodySmall!.copyWith(color: scheme.outline),
          ),
        ],
      ),
      subtitle: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            if (whoPrefix.isNotEmpty)
              TextSpan(
                text: whoPrefix,
                style: subtitleStyle.copyWith(color: scheme.onSurface),
              ),
            ...highlight(snippet, term, subtitleStyle, mark),
          ],
        ),
      ),
      onTap: () {
        final service = maybeFindMessagesSvc(chat.guid) ?? MessagesService(chat.guid);
        service.method = SearchMode.local.name;
        service.struct.addMessages([message]);
        NavigationSvc.pushAndRemoveUntil(
          context,
          ConversationView(chat: chat, customService: service, initialScrollToGuid: message.guid),
          (route) => route.isFirst,
        );
      },
    );
  }
}
