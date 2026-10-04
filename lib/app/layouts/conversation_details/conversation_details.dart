import 'package:bluebubbles/app/layouts/conversation_details/material/chat_detail_theme.dart';
import 'package:bluebubbles/app/layouts/conversation_details/material/findmy_location_card.dart';
import 'package:bluebubbles/app/layouts/conversation_details/material/material_chat_header.dart';
import 'package:bluebubbles/app/layouts/conversation_details/material/material_chat_options.dart';
import 'package:bluebubbles/app/layouts/conversation_details/material/material_participants_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/attachments_loader.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/chat_info.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/chat_options.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/sections/documents/documents_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/sections/links/links_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/sections/locations/locations_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/sections/media/media_grid_section.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/participants_list.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/contact_tile.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/profile_scaffold.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ConversationDetails extends StatefulWidget {
  final Chat chat;

  const ConversationDetails({super.key, required this.chat});

  @override
  State<ConversationDetails> createState() => _ConversationDetailsState();
}

class _ConversationDetailsState extends State<ConversationDetails> with WidgetsBindingObserver, ThemeHelpers {
  List<Attachment> media = <Attachment>[];
  List<Attachment> docs = <Attachment>[];
  List<Attachment> locations = <Attachment>[];
  late Chat chat = widget.chat;
  final RxList<String> selected = <String>[].obs;
  bool isLoadingAttachments = true;

  /// OpenBubbles: the rust handles in this chat that can receive a FaceTime call.
  List<String> ftSupportedParticipants = [];

  @override
  void initState() {
    super.initState();
    ChatsSvc.setActiveToDead();
    // OpenBubbles: suppress in-chat overlays (e.g. incoming FaceTime banners)
    // while the details panel is on screen.
    cvc(widget.chat).showingOverlays = true;
    _loadFaceTimeTargets();
  }

  /// OpenBubbles-only: ask rustpush which participants can be FaceTimed. The result
  /// is published through [facetimeSupportedTargets] so ContactTile can read it —
  /// upstream's participants widgets don't pass it down.
  Future<void> _loadFaceTimeTargets() async {
    if (kIsWeb) return;
    try {
      final client = pushService.state?.client;
      if (client == null) return;
      final data = await chat.getConversationData();
      final targets = await api.validateTargetsFacetime(
        state: client,
        targets: data.participants,
        sender: await chat.ensureHandle(),
      );
      facetimeSupportedTargets[chat.guid] = targets;
      if (!mounted) return;
      setState(() {
        ftSupportedParticipants = targets;
      });
    } catch (e, stack) {
      Logger.debug("Failed to validate FaceTime targets", error: e, trace: stack);
    }
  }

  @override
  void dispose() {
    cvc(widget.chat).showingOverlays = false;
    facetimeSupportedTargets.remove(chat.guid);
    if (ChatsSvc.activeChat != null) {
      ChatsSvc.setActiveToAlive();
      cvc(ChatsSvc.activeChat!.chat).lastFocusedNode.requestFocus();
    }
    super.dispose();
  }

  void onAttachmentsLoaded(
    List<Attachment> loadedMedia,
    List<Attachment> loadedDocs,
    List<Attachment> loadedLocations,
  ) {
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
    final chatState = ChatsSvc.getOrCreateChatState(chat);
    return ChatStateScope(
      chatState: chatState,
      child: Obx(() {
        final chatDetailTheme = ChatDetailTheme.resolve(context, chat);
        final iosSkin = SettingsSvc.settings.skin.value == Skins.iOS;

        // iOS skin keeps ChatInfo (1:1 inside ProfileScaffold's poster). Material
        // and Samsung use the expressive header for every chat; for 1:1 it carries
        // the fork's action row (call / FaceTime / mail / info / invite).
        final header = iosSkin
            ? ChatInfo(chat: chat, ftSupportedParticipants: ftSupportedParticipants)
            : ExpressiveChatHeader(chat: chat, ftSupportedParticipants: ftSupportedParticipants);
        final materialLayout = !iosSkin;

        final actions = <Widget>[
              Obx(() {
                if (selected.isNotEmpty) {
                  return IconButton(
                    icon: Icon(iOS ? CupertinoIcons.xmark : Icons.close, color: context.theme.colorScheme.onSurface),
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
                    icon: Icon(
                      iOS ? CupertinoIcons.cloud_download : Icons.file_download,
                      color: context.theme.colorScheme.onSurface,
                    ),
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
        ];

        final slivers = <Widget>[
              // iOS: for 1:1 chats the header is rendered by ProfileScaffold (Apple
              // profile poster), so it isn't repeated in the body.
              if (chat.isGroup || materialLayout)
                SliverToBoxAdapter(
                  child: header,
                ),
              iosSkin ? ParticipantsList(chat: chat) : ExpressiveParticipantsSection(chat: chat),
              // Hidden widget that loads attachments in the background
              SliverToBoxAdapter(
                child: AttachmentsLoader(chat: chat, onAttachmentsLoaded: onAttachmentsLoaded),
              ),
              SliverPadding(padding: EdgeInsets.symmetric(vertical: iosSkin ? 0 : 5)),
              // Material: what you came for first (where they are, photos, links,
              // files), the chat's settings after. iOS keeps upstream's order.
              if (materialLayout) FindMyLocationCard(chat: chat, tileColor: chatDetailTheme.tileColor),
              if (!materialLayout) ChatOptions(chat: chat),
              MediaGridSection(chat: chat, media: media, selected: selected, isLoading: isLoadingAttachments),
              LinksSection(chat: chat),
              LocationsSection(chat: chat, locations: locations, isLoading: isLoadingAttachments),
              DocumentsSection(chat: chat, docs: docs, isLoading: isLoadingAttachments),
              if (materialLayout) ExpressiveChatOptions(chat: chat),
              const SliverPadding(padding: EdgeInsets.only(top: 50)),
        ];

        // iOS skin only: 1:1 chats get the Apple profile/poster scaffold.
        if (iosSkin && !chat.isGroup && chat.participants.isNotEmpty) {
          return Theme(
            data: chatDetailTheme.theme,
            child: ProfileScaffold(
              bodySlivers: slivers,
              handle: chat.participants.first,
              actions: actions,
              chatOptions: header,
            ),
          );
        }

        return Theme(
          data: chatDetailTheme.theme,
          child: SettingsScaffold(
            headerColor: chatDetailTheme.headerColor,
            title: "Details",
            tileColor: chatDetailTheme.tileColor,
            initialHeader: null,
            iosSubtitle: iosSubtitle,
            materialSubtitle: materialSubtitle,
            minimalAppBar: true,
            actions: actions,
            bodySlivers: slivers,
          ),
        );
      }),
    );
  }
}
