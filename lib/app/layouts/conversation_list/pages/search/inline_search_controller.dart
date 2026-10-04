import 'dart:async';

import 'package:bluebubbles/app/layouts/conversation_list/pages/search/search_models.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/search/search_query_helper.dart';
import 'package:bluebubbles/app/state/chat_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// State for the search bar that expands in place inside the conversation
/// list header (Material skin).
///
/// Search runs as you type: a short debounce after the last keystroke, from two
/// characters, with stale queries discarded. Results come in two groups:
/// conversations whose name or participants match, then messages whose text
/// matches. Filters narrow the message group the way the Search page's drawer
/// did.
class InlineSearchController {
  static const Duration debounce = Duration(milliseconds: 250);
  static const int minLength = 2;
  static const int maxChatHits = 8;

  final RxBool active = false.obs;
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  final RxString term = "".obs;
  final RxBool isSearching = false.obs;
  final RxList<Chat> chatHits = <Chat>[].obs;
  final RxList<SearchResultItem> messageHits = <SearchResultItem>[].obs;

  /// True once a query for the current [term] has completed (distinguishes
  /// "nothing found" from "not searched yet").
  final RxBool searched = false.obs;

  // Filters (message group only).
  final Rx<Chat?> selectedChat = Rx<Chat?>(null);
  final Rx<Handle?> selectedHandle = Rx<Handle?>(null);
  final RxBool isFromMe = false.obs;
  final RxBool isNotFromMe = false.obs;
  final Rx<DateTime?> sinceDate = Rx<DateTime?>(null);

  int get filterCount =>
      (selectedChat.value != null ? 1 : 0) +
      (selectedHandle.value != null ? 1 : 0) +
      (isFromMe.value ? 1 : 0) +
      (isNotFromMe.value ? 1 : 0) +
      (sinceDate.value != null ? 1 : 0);

  Timer? _debounce;
  int _sequence = 0;

  InlineSearchController() {
    textController.addListener(_onTextChanged);
    // Any filter change re-runs the current term.
    for (final rx in [selectedChat, selectedHandle, isFromMe, isNotFromMe, sinceDate]) {
      ever(rx, (_) => _schedule(immediate: true));
    }
  }

  void open() {
    active.value = true;
    // Focus after the bar has been built.
    WidgetsBinding.instance.addPostFrameCallback((_) => focusNode.requestFocus());
  }

  void close() {
    _debounce?.cancel();
    _sequence++;
    focusNode.unfocus();
    textController.clear();
    term.value = "";
    chatHits.clear();
    messageHits.clear();
    searched.value = false;
    isSearching.value = false;
    active.value = false;
  }

  void clearFilters() {
    selectedChat.value = null;
    selectedHandle.value = null;
    isFromMe.value = false;
    isNotFromMe.value = false;
    sinceDate.value = null;
  }

  void _onTextChanged() {
    final t = textController.text.trim();
    if (t == term.value) return;
    term.value = t;
    searched.value = false;
    _schedule();
  }

  void _schedule({bool immediate = false}) {
    _debounce?.cancel();
    if (term.value.length < minLength) {
      _sequence++;
      chatHits.clear();
      messageHits.clear();
      isSearching.value = false;
      return;
    }
    _debounce = Timer(immediate ? Duration.zero : debounce, _run);
  }

  Future<void> _run() async {
    final seq = ++_sequence;
    final t = term.value;
    if (t.length < minLength) return;
    isSearching.value = true;
    try {
      final chats = _matchChats(t);
      final messages = await SearchQueryHelper.runLocal(
        term: t,
        selectedChat: selectedChat.value,
        selectedHandle: selectedHandle.value,
        isFromMe: isFromMe.value,
        isNotFromMe: isNotFromMe.value,
        sinceDate: sinceDate.value,
      );
      if (seq != _sequence) return; // a newer keystroke won
      chatHits.assignAll(chats);
      messageHits.assignAll(messages);
      searched.value = true;
    } catch (e, s) {
      Logger.error("Inline search failed", error: e, trace: s);
      if (seq == _sequence) {
        chatHits.clear();
        messageHits.clear();
        searched.value = true;
      }
    } finally {
      if (seq == _sequence) isSearching.value = false;
    }
  }

  /// Conversations whose title, participant names or addresses contain the
  /// term. Uses the in-memory chat states (every loaded chat), so contact
  /// names count, not only the stored chat title.
  List<Chat> _matchChats(String t) {
    if (selectedChat.value != null) return const [];
    final needle = t.toLowerCase();
    final digits = needle.replaceAll(RegExp(r'\D'), "");
    final hits = <ChatState>[];
    for (final state in ChatsSvc.chatStates.values) {
      final chat = state.chat;
      if (chat.dateDeleted != null || chat.isRoutingStub) continue;
      if (_chatMatches(state, needle, digits)) hits.add(state);
    }
    hits.sort((a, b) => Chat.sort(a.chat, b.chat));
    return hits.take(maxChatHits).map((s) => s.chat).toList();
  }

  bool _chatMatches(ChatState state, String needle, String digits) {
    final title = (state.title.value ?? state.chat.getTitle()).toLowerCase();
    if (title.contains(needle)) return true;
    for (final p in state.participants) {
      final name = p.displayName.value?.toLowerCase();
      if (name != null && name.contains(needle)) return true;
      final address = p.handle.address.toLowerCase();
      if (address.contains(needle)) return true;
      if (digits.length >= 3 && address.replaceAll(RegExp(r'\D'), "").contains(digits)) return true;
    }
    return false;
  }

  void dispose() {
    _debounce?.cancel();
    textController.dispose();
    focusNode.dispose();
  }
}
