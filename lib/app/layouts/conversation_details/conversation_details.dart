import 'dart:async';

import 'package:bluebubbles/app/layouts/conversation_details/widgets/attachments_loader.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/chat_info.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/chat_options.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/documents_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/links_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/locations_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/media_grid_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/participants_list.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class ConversationDetails extends StatefulWidget {
  final Chat chat;

  const ConversationDetails({super.key, required this.chat});

  @override
  State<ConversationDetails> createState() => _ConversationDetailsState();
}

class _ConversationDetailsState extends OptimizedState<ConversationDetails> with WidgetsBindingObserver {
  List<Attachment> media = <Attachment>[];
  List<Attachment> docs = <Attachment>[];
  List<Attachment> locations = <Attachment>[];
  late Chat chat = widget.chat;
  late StreamSubscription sub;
  final RxList<String> selected = <String>[].obs;
  bool isLoadingAttachments = true;

  @override
  void initState() {
    super.initState();

    ChatsSvc.setActiveToDead();

    if (!kIsWeb) {
      final chatQuery = Database.chats.query(Chat_.guid.equals(chat.guid)).watch();
      sub = chatQuery.listen((Query<Chat> query) async {
        final _chat = await runAsync(() {
          return Database.chats.get(chat.id!);
        });
        if (_chat != null) {
          final update = _chat.getTitle() != chat.title || _chat.handles.length != chat.handles.length;
          chat = _chat.merge(chat);
          if (update) {
            setState(() {});
          }
        }
      });
    } else {
      sub = WebListeners.chatUpdate.listen((_chat) {
        final update = _chat.getTitle() != chat.title || _chat.handles.length != chat.handles.length;
        chat = _chat.merge(chat);
        if (update) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    sub.cancel();
    if (ChatsSvc.activeChat != null) {
      ChatsSvc.setActiveToAlive();
      cvc(ChatsSvc.activeChat!.chat).lastFocusedNode.requestFocus();
    }
    super.dispose();
  }

  void onAttachmentsLoaded(
      List<Attachment> loadedMedia, List<Attachment> loadedDocs, List<Attachment> loadedLocations) {
    if (mounted) {
      setState(() {
        media = loadedMedia;
        docs = loadedDocs;
        locations = loadedLocations;
        isLoadingAttachments = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: SettingsSvc.settings.immersiveMode.value
            ? Colors.transparent
            : context.theme.colorScheme.background, // navigation bar color
        systemNavigationBarIconBrightness: context.theme.colorScheme.brightness.opposite,
        statusBarColor: Colors.transparent, // status bar color
        statusBarIconBrightness: context.theme.colorScheme.brightness.opposite,
      ),
      child: Theme(
          data: context.theme.copyWith(
            // in case some components still use legacy theming
            primaryColor: context.theme.colorScheme.bubble(context, chat.isIMessage),
            colorScheme: context.theme.colorScheme.copyWith(
              primary: context.theme.colorScheme.bubble(context, chat.isIMessage),
              onPrimary: context.theme.colorScheme.onBubble(context, chat.isIMessage),
              surface: SettingsSvc.settings.monetTheming.value == Monet.full
                  ? null
                  : (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor,
              onSurface: SettingsSvc.settings.monetTheming.value == Monet.full
                  ? null
                  : (context.theme.extensions[BubbleColors] as BubbleColors?)?.onReceivedBubbleColor,
            ),
          ),
          child: Obx(() => SettingsScaffold(
                headerColor: headerColor,
                title: "Details",
                tileColor: tileColor,
                initialHeader: null,
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                actions: [
                  Obx(() {
                    if (selected.isNotEmpty) {
                      return IconButton(
                        icon: Icon(iOS ? CupertinoIcons.xmark : Icons.close,
                            color: context.theme.colorScheme.onBackground),
                        onPressed: () {
                          selected.clear();
                        },
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  }),
                  Obx(() {
                    if (selected.isNotEmpty) {
                      return IconButton(
                        icon: Icon(iOS ? CupertinoIcons.cloud_download : Icons.file_download,
                            color: context.theme.colorScheme.onBackground),
                        onPressed: () {
                          final attachments = media.where((e) => selected.contains(e.guid!));
                          for (Attachment a in attachments) {
                            final file = AttachmentsSvc.getContent(a, autoDownload: false);
                            if (file is PlatformFile) {
                              AttachmentsSvc.saveToDisk(file);
                            }
                          }
                        },
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  }),
                ],
                bodySlivers: [
                  SliverToBoxAdapter(
                    child: ChatInfo(chat: chat),
                  ),
                  ParticipantsList(chat: chat),
                  // Hidden widget that loads attachments in the background
                  SliverToBoxAdapter(
                    child: AttachmentsLoader(
                      chat: chat,
                      onAttachmentsLoaded: onAttachmentsLoaded,
                    ),
                  ),
                  if (chat.handles.length > 2 &&
                      SettingsSvc.settings.enablePrivateAPI.value &&
                      SettingsSvc.serverDetailsSync().item4 >= 226)
                    SliverToBoxAdapter(
                      child: Builder(builder: (context) {
                        return ListTile(
                          mouseCursor: MouseCursor.defer,
                          title: Text("Leave ${iOS ? "Chat" : "chat"}",
                              style:
                                  context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.error)),
                          leading: Container(
                            width: 40 * SettingsSvc.settings.avatarScale.value,
                            height: 40 * SettingsSvc.settings.avatarScale.value,
                            decoration: BoxDecoration(
                                color: !iOS ? null : context.theme.colorScheme.properSurface,
                                shape: BoxShape.circle,
                                border: iOS ? null : Border.all(color: context.theme.colorScheme.error, width: 3)),
                            child: Icon(Icons.error_outline, color: context.theme.colorScheme.error, size: 20),
                          ),
                          onTap: () async {
                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    backgroundColor: context.theme.colorScheme.properSurface,
                                    title: Text(
                                      "Leaving chat...",
                                      style: context.theme.textTheme.titleLarge,
                                    ),
                                    content: SizedBox(
                                      height: 70,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          backgroundColor: context.theme.colorScheme.properSurface,
                                          valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                        ),
                                      ),
                                    ),
                                  );
                                });
                            final response = await HttpSvc.leaveChat(chat.guid);
                            if (response.statusCode == 200) {
                              Navigator.of(context, rootNavigator: true).pop();
                              showSnackbar("Notice", "Left chat successfully!");
                            } else {
                              Navigator.of(context, rootNavigator: true).pop();
                              showSnackbar("Error", "Failed to leave chat!");
                            }
                          },
                        );
                      }),
                    ),
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  ChatOptions(chat: chat),
                  MediaGridSection(media: media, selected: selected, isLoading: isLoadingAttachments),
                  LinksSection(chat: chat),
                  LocationsSection(locations: locations, isLoading: isLoadingAttachments),
                  DocumentsSection(docs: docs, isLoading: isLoadingAttachments),
                  const SliverPadding(
                    padding: EdgeInsets.only(top: 50),
                  ),
                ],
              ))),
    );
  }
}
