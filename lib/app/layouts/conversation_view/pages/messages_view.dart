import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/messages_view_components.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/wrappers/scrollbar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_ml_kit/google_ml_kit.dart' hide Message;
import 'package:path/path.dart' hide context;
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class MessagesView extends StatefulWidget {
  final MessagesService? customService;
  final ConversationViewController controller;

  MessagesView({
    super.key,
    this.customService,
    required this.controller,
  });

  @override
  MessagesViewState createState() => MessagesViewState();
}

class MessagesViewState extends OptimizedState<MessagesView> {
  bool initialized = false;
  bool fetching = false;
  late bool noMoreMessages = widget.customService != null;
  List<Message> _messages = <Message>[];
  
  // Notifier for list structure changes only (add/remove)
  final ValueNotifier<int> _listVersion = ValueNotifier<int>(0);
  
  // Debounce setState calls to prevent rapid rebuilds
  Timer? _setStateDebouncer;

  RxList<Widget> smartReplies = <Widget>[].obs;
  RxMap<String, Widget> internalSmartReplies = <String, Widget>{}.obs;

  late final messageService = widget.customService ?? MessagesSvc(chat.guid)
    ..init(chat, handleNewMessage, handleUpdatedMessage, handleDeletedMessage, jumpToMessage);
  final smartReply = GoogleMlKit.nlp.smartReply();
  final RxBool dragging = false.obs;
  final RxInt numFiles = 0.obs;
  final RxBool latestMessageDeliveredState = false.obs;
  final RxBool jumpingToOldestUnread = false.obs;

  ConversationViewController get controller => widget.controller;

  AutoScrollController get scrollController => controller.scrollController;

  bool get showSmartReplies => SettingsSvc.settings.smartReply.value && !kIsWeb && !kIsDesktop;

  Chat get chat => controller.chat;

  @override
  void initState() {
    super.initState();

    EventDispatcherSvc.stream.listen((e) async {
      if (e.item1 == "refresh-messagebloc" && e.item2 == chat.guid) {
        // Clear state items
        noMoreMessages = false;
        _messages = [];
        // Reload the state after refreshing
        messageService.reload();
        messageService.init(chat, handleNewMessage, handleUpdatedMessage, handleDeletedMessage, jumpToMessage);
        setState(() {});
      } else if (e.item1 == "add-custom-smartreply") {
        if (e.item2 != null && internalSmartReplies['attach-recent'] == null) {
          internalSmartReplies['attach-recent'] = _buildReply("Attach recent photo", onTap: () async {
            controller.pickedAttachments.add(e.item2);
            internalSmartReplies.clear();
          });
        }
      }
    });

    updateObx(() async {
      if (chat.isIMessage && !chat.isGroup) {
        getFocusState();
      }
      final searchMessage = (messageService.method == null) ? null : messageService.struct.messages.firstOrNull;
      if (messageService.method != null) {
        await messageService.loadSearchChunk(
            messageService.struct.messages.first, messageService.method == "local" ? SearchMethod.local : SearchMethod.network);
      } else if (messageService.struct.isEmpty) {
        final stopwatch = Stopwatch()..start();
        await messageService.loadChunk(0, controller);
        stopwatch.stop();
        Logger.info("Initial chunk loaded in ${stopwatch.elapsedMilliseconds}ms");
      }
      _messages = messageService.struct.messages;
      _messages.sort(Message.sort);
      // Initialize message widget controllers
      _messages.forEach((m) {
        final c = mwc(m);
        c.cvController = controller;
      });
      setState(() {});
      // scroll to message if needed
      if (searchMessage != null) {
        final index = _messages.indexWhere((element) => element.guid == searchMessage.guid);
        await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.middle);
        scrollController.highlight(index, highlightDuration: const Duration(milliseconds: 500));
      } else if (!(_messages.firstOrNull?.isFromMe ?? true)) {
        updateReplies();
      }
      initialized = true;
      if (SettingsSvc.settings.scrollToLastUnread.value && chat.lastReadMessageGuid != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (getActiveMwc(chat.lastReadMessageGuid!)?.built ?? false) return;
          internalSmartReplies['scroll-last-read'] = _buildReply("Jump to oldest unread", onTap: () async {
            if (jumpingToOldestUnread.value) return;
            jumpingToOldestUnread.value = true;
            await jumpToMessage(chat.lastReadMessageGuid!);
            internalSmartReplies.remove('scroll-last-read');
            jumpingToOldestUnread.value = false;
          });
        });
      }
    });
  }

  @override
  void dispose() {
    if (!kIsWeb && !kIsDesktop) smartReply.close();
    chat.lastReadMessageGuid = _messages.first.guid;
    chat.saveAsync(updateLastReadMessageGuid: true);
    messageService.close(force: widget.customService != null);
    for (Message m in _messages) {
      if (m.guid != null) {
        getActiveMwc(m.guid!)?.close();
      }
    }
    _setStateDebouncer?.cancel();
    _listVersion.dispose();
    super.dispose();
  }

  void getFocusState() {
    if (!SettingsSvc.isMinMontereySync) return;
    final recipient = chat.handles.firstOrNull;
    if (recipient != null) {
      HttpSvc.handleFocusState(recipient.address).then((response) {
        final status = response.data['data']['status'];
        controller.recipientNotifsSilenced.value = status != "none";
      }).catchError((error, stack) async {
        Logger.error('Failed to get focus state!', error: error, trace: stack);
      });
    }
  }

  Future<void> jumpToMessage(String guid) async {
    // check if the message is already loaded
    int index = _messages.indexWhere((element) => element.guid == guid);
    if (index != -1) {
      await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.middle);
      scrollController.highlight(index, highlightDuration: const Duration(milliseconds: 500));
      return;
    }
    // otherwise fetch until it is loaded
    final message = Message.findOne(guid: guid);
    final query = (Database.messages.query(Message_.dateDeleted.isNull().and(Message_.dateCreated.notNull()))
          ..link(Message_.chat, Chat_.id.equals(chat.id!))
          ..order(Message_.dateCreated, flags: Order.descending))
        .build();
    final ids = await query.findIdsAsync();
    final pos = ids.indexOf(message!.id!);
    await loadNextChunk(limit: pos + 10);
    index = _messages.indexWhere((element) => element.guid == guid);
    if (index != -1) {
      await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.middle);
      scrollController.highlight(index, highlightDuration: const Duration(milliseconds: 500));
    } else {
      showSnackbar("Error", "Failed to find message!");
    }
  }

  void updateReplies({bool updateConversation = true}) async {
    if (!showSmartReplies || isNullOrEmpty(_messages) || kIsWeb || kIsDesktop || !mounted || !LifecycleSvc.isAlive) return;

    if (updateConversation) {
      _messages.reversed.where((e) => !isNullOrEmpty(e.fullText) && e.dateCreated != null).skip(max(_messages.length - 5, 0)).forEach((message) {
        _addMessageToSmartReply(message);
      });
    }
    Logger.info("Getting smart replies...");
    SmartReplySuggestionResult results = await smartReply.suggestReplies();

    if (results.status == SmartReplySuggestionResultStatus.success) {
      Logger.info("Smart Replies found: ${results.suggestions.length}");
      smartReplies.value = results.suggestions.map((e) => _buildReply(e)).toList();
      Logger.debug(smartReplies.toString());
    } else {
      smartReplies.clear();
    }
  }

  void _addMessageToSmartReply(Message message) {
    if (message.isFromMe ?? false) {
      smartReply.addMessageToConversationFromLocalUser(message.fullText, message.dateCreated!.millisecondsSinceEpoch);
    } else {
      smartReply.addMessageToConversationFromRemoteUser(
          message.fullText, message.dateCreated!.millisecondsSinceEpoch, message.handleRelation.target?.address ?? "participant");
    }
  }

  Future<void> loadNextChunk({int limit = 25}) async {
    if (noMoreMessages || fetching) {
      Logger.debug("loadNextChunk: Skipping - noMoreMessages=$noMoreMessages, fetching=$fetching");
      return;
    }
    fetching = true;
    final previousLength = _messages.length;
    Logger.debug("loadNextChunk: Starting - current messages: $previousLength");

    // Start loading the next chunk of messages
    noMoreMessages = !(await messageService.loadChunk(_messages.length, controller, limit: limit).catchError((e, stack) {
      Logger.error("Failed to fetch message chunk!", error: e, trace: stack);
      fetching = false;
      return true;
    }));

    if (noMoreMessages) {
      Logger.debug("loadNextChunk: No more messages available");
      fetching = false;
      return setState(() {});
    }

    final oldLength = _messages.length;
    final oldMessageGuids = Set<String>.from(_messages.map((m) => m.guid).whereType<String>());
    
    final newMessagesFromService = messageService.struct.messages;
    final newMessages = newMessagesFromService.where((m) => !oldMessageGuids.contains(m.guid)).toList();
    
    Logger.debug("loadNextChunk: Found ${newMessages.length} new messages (old: $oldLength, new: ${newMessagesFromService.length})");
    
    // Initialize message widget controllers for new messages
    for (final newMsg in newMessages) {
      final c = mwc(newMsg);
      c.cvController = controller;
    }
    
    // Update the list and rebuild - let SliverAnimatedList recalculate based on new length
    _messages = newMessagesFromService;
    _messages.sort(Message.sort);
    fetching = false;
    
    Logger.debug("loadNextChunk: Updated _messages list to ${_messages.length} items, calling setState");
    setState(() {});
  }

  void handleNewMessage(Message message) async {
    // Check if widget is still mounted before processing
    if (!mounted) return;
    
    Logger.debug("handleNewMessage: Received new message ${message.guid}, current count: ${_messages.length}");
    
    // Check if message already exists to prevent duplicates
    final existingIndex = _messages.indexWhere((m) => m.guid == message.guid);
    if (existingIndex != -1) {
      Logger.debug("handleNewMessage: Message ${message.guid} already exists at index $existingIndex, skipping duplicate");
      // Trigger update for this specific message via reactivity system
      if (message.guid != null) {
        muc.notifyMessageUpdate(chat.guid, message.guid!);
      }
      return;
    }
    
    _messages.add(message);
    _messages.sort(Message.sort);
    final insertIndex = _messages.indexOf(message);
    
    // Initialize message widget controller
    final c = mwc(message);
    c.cvController = controller;
    
    Logger.debug("handleNewMessage: Added message at index $insertIndex, _messages now has ${_messages.length} items");
    
    // Debounced setState to prevent rapid rebuilds
    _listVersion.value++;
    _setStateDebouncer?.cancel();
    _setStateDebouncer = Timer(const Duration(milliseconds: 16), () {
      if (mounted) setState(() {});
    });

    if (insertIndex == 0 && showSmartReplies) {
      _addMessageToSmartReply(message);
      if (message.isFromMe!) {
        smartReplies.clear();
      } else {
        updateReplies(updateConversation: false);
      }
    }

    if (insertIndex == 0 && !message.isFromMe! && SettingsSvc.settings.receiveSoundPath.value != null) {
      if (kIsDesktop && (cm.getChatController(chat.guid)?.isActive ?? false)) {
        Player player = Player();
        player.stream.completed
            .firstWhere((completed) => completed)
            .then((_) async => Future.delayed(const Duration(milliseconds: 500), () async => await player.dispose()));
        await player.setVolume(SettingsSvc.settings.soundVolume.value.toDouble());
        await player.open(Media(SettingsSvc.settings.receiveSoundPath.value!));
      } else if (cm.isChatActive(chat.guid)) {
        PlayerController controller = PlayerController();
        await controller
            .preparePlayer(path: SettingsSvc.settings.receiveSoundPath.value!, volume: SettingsSvc.settings.soundVolume.value / 100)
            .then((_) => controller.startPlayer());
      }
    }
  }

  void handleUpdatedMessage(Message message, {String? oldGuid}) {
    // Check if widget is still mounted before processing
    if (!mounted) return;
    
    Logger.debug("handleUpdatedMessage: Updating message ${message.guid ?? oldGuid}");
    final index = _messages.indexWhere((e) => e.guid == (oldGuid ?? message.guid));
    if (index != -1) {
      _messages[index] = message;
      Logger.debug("handleUpdatedMessage: Updated message at index $index");
      // Use reactivity system instead of setState to avoid full rebuild
      if (message.guid != null) {
        muc.notifyMessageUpdate(chat.guid, message.guid!);
      }
    } else {
      Logger.warn("handleUpdatedMessage: Message ${message.guid ?? oldGuid} not found in list");
    }
    if (message.wasDeliveredQuietly != latestMessageDeliveredState.value) {
      latestMessageDeliveredState.value = message.wasDeliveredQuietly;
    }
  }

  void handleDeletedMessage(Message message) {
    // Check if widget is still mounted before processing
    if (!mounted) return;
    
    Logger.debug("handleDeletedMessage: Deleting message ${message.guid}");
    final index = _messages.indexWhere((e) => e.guid == message.guid);
    if (index != -1) {
      _messages.removeAt(index);
      Logger.debug("handleDeletedMessage: Removed message at index $index");
      _listVersion.value++;
      _setStateDebouncer?.cancel();
      _setStateDebouncer = Timer(const Duration(milliseconds: 16), () {
        if (mounted) setState(() {});
      });
    } else {
      Logger.warn("handleDeletedMessage: Message ${message.guid} not found in list");
    }
  }

  Widget _buildReply(String text, {Function()? onTap}) => Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(
            width: 2,
            style: BorderStyle.solid,
            color: context.theme.colorScheme.properSurface,
          ),
          borderRadius: BorderRadius.circular(19),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: onTap ??
              () {
                outq.queue(OutgoingItem(
                  type: QueueType.sendMessage,
                  chat: controller.chat,
                  message: Message(
                    text: text,
                    dateCreated: DateTime.now(),
                    hasAttachments: false,
                    isFromMe: true,
                    handleId: 0,
                  ),
                ));
              },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1.5, left: 13.0, right: 13.0),
              child: Obx(() => RichText(
                    text: TextSpan(
                      children: MessageHelper.buildEmojiText(
                        jumpingToOldestUnread.value && text == "Jump to oldest unread" ? "Jumping to oldest unread..." : text,
                        context.theme.extension<BubbleText>()!.bubbleText,
                      ),
                    ),
                  )),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      formats: Platform.isLinux ? Formats.standardFormats : Formats.standardFormats.whereType<FileFormat>().toList(),
      onDropOver: (DropOverEvent event) {
        if (!event.session.allowedOperations.contains(DropOperation.copy)) {
          dragging.value = false;
          return DropOperation.forbidden;
        }
        numFiles.value = event.session.items.where((item) => Formats.standardFormats.whereType<FileFormat>().any((f) => item.canProvide(f))).length;
        if (numFiles.value > 0) {
          dragging.value = true;
          return DropOperation.copy;
        }

        dragging.value = false;
        return DropOperation.forbidden;
      },
      onDropLeave: (_) {
        dragging.value = false;
      },
      onPerformDrop: (PerformDropEvent event) async {
        for (DropItem item in event.session.items) {
          final reader = item.dataReader!;
          FileFormat? format = reader.getFormats(Formats.standardFormats).whereType<FileFormat>().firstOrNull;

          if (format == null) return;

          reader.getFile(format, (file) async {
            Uint8List bytes = await file.readAll();
            String filePath = file.fileName ?? "";
            String fileName = file.fileName ?? "";
            if (Platform.isLinux) {
              filePath = String.fromCharCodes(bytes);
              File _file = File(filePath);
              bytes = await _file.readAsBytes();
              fileName = basename(filePath);
            }
            if (filePath.isEmpty) {
              filePath = "Dragged_File_${controller.pickedAttachments.length + 1}";
            }
            if (fileName.isEmpty) {
              fileName = "Dragged_File_${controller.pickedAttachments.length + 1}";
            }
            controller.pickedAttachments.add(PlatformFile(
              path: filePath,
              name: fileName,
              size: bytes.length,
              bytes: bytes,
            ));
          });
        }
        dragging.value = false;
      },
      child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragUpdate: (details) {
            if (SettingsSvc.settings.skin.value != Skins.Samsung && !kIsWeb && !kIsDesktop) {
              controller.timestampOffset.value += details.delta.dx * 0.3;
            }
          },
          onHorizontalDragEnd: (details) {
            if (SettingsSvc.settings.skin.value != Skins.Samsung) {
              controller.timestampOffset.value = 0;
            }
          },
          onHorizontalDragCancel: () {
            if (SettingsSvc.settings.skin.value != Skins.Samsung) {
              controller.timestampOffset.value = 0;
            }
          },
          child: Stack(
            children: [
              Obx(
                () => AnimatedOpacity(
                  opacity: _messages.isEmpty && widget.customService == null ? 0 : (dragging.value ? 0.3 : 1),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeIn,
                  child: DeferredPointerHandler(
                    child: ScrollbarWrapper(
                      reverse: true,
                      controller: scrollController,
                      showScrollbar: true,
                      child: CustomScrollView(
                        controller: scrollController,
                        reverse: true,
                        physics: ThemeSwitcher.getScrollPhysics(),
                        slivers: <Widget>[
                          if (showSmartReplies || internalSmartReplies.isNotEmpty)
                            SliverToBoxAdapter(
                              child: SmartRepliesRow(
                                smartReplies: smartReplies,
                                internalSmartReplies: internalSmartReplies,
                              ),
                            ),
                          if (!chat.isGroup && chat.isIMessage)
                            SliverToBoxAdapter(
                              child: NotificationsSilencedBanner(
                                controller: controller,
                                chat: chat,
                                latestMessage: _messages.firstOrNull,
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: TypingIndicatorRow(
                              controller: controller,
                              chat: chat,
                            ),
                          ),
                          if (_messages.isEmpty && widget.customService != null)
                            const SliverToBoxAdapter(
                              child: Loader(text: "Loading surrounding message context..."),
                            ),
                          SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (BuildContext context, int index) {
                                try {
                                  
                                  // paginate
                                  if (index >= _messages.length) {
                                    if (!noMoreMessages && initialized && index == _messages.length) {
                                      if (!fetching) {
                                        loadNextChunk();
                                      }
                                      return const Loader();
                                    }

                                    return const SizedBox.shrink();
                                  }

                                  Message? olderMessage;
                                  Message? newerMessage;
                                  if (index + 1 < _messages.length) {
                                    olderMessage = _messages[index + 1];
                                  }
                                  if (index - 1 >= 0) {
                                    newerMessage = _messages[index - 1];
                                  }

                                  final message = _messages[index];
                                  return RepaintBoundary(
                                    child: Padding(
                                      key: ValueKey(message.guid ?? 'unknown-$index'),
                                      padding: const EdgeInsets.only(left: 5.0, right: 5.0),
                                      child: AutoScrollTag(
                                        key: ValueKey("${message.guid ?? 'unknown-$index'}-scrolling"),
                                        index: index,
                                        controller: scrollController,
                                        highlightColor: context.theme.colorScheme.surface.withValues(alpha: 0.7),
                                        child: MessageHolder(
                                          cvController: controller,
                                          message: message,
                                          oldMessageGuid: olderMessage?.guid,
                                          newMessageGuid: newerMessage?.guid,
                                        ),
                                      ),
                                    ),
                                  );
                                } catch (e, stack) {
                                  Logger.error("Error in SliverList itemBuilder at index $index", error: e, trace: stack);
                                  return SizedBox(
                                    key: ValueKey('error-$index'),
                                    height: 50,
                                    child: Center(
                                      child: Text('Error loading message at index $index'),
                                    ),
                                  );
                                }
                              },
                              childCount: _messages.length + 1,
                            ),
                          ),
                          const SliverPadding(
                            padding: EdgeInsets.all(70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              DragDropOverlay(
                dragging: dragging,
                numFiles: numFiles,
              ),
            ],
          )),
    );
  }
}

class Loader extends StatelessWidget {
  const Loader({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            text ?? "Loading more messages...",
            style: context.theme.textTheme.labelLarge!.copyWith(color: context.theme.colorScheme.outline),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SettingsSvc.settings.skin.value == Skins.iOS
              ? Theme(
                  data: ThemeData(
                    cupertinoOverrideTheme: const CupertinoThemeData(brightness: Brightness.dark),
                  ),
                  child: const CupertinoActivityIndicator(),
                )
              : const SizedBox(height: 20, width: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      ],
    );
  }
}
