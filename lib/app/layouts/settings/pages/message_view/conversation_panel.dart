import 'package:animated_size_and_fade/animated_size_and_fade.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import 'package:bluebubbles/app/layouts/settings/widgets/reaction_type_picker.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/message_options_order_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/text_field_buttons_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/database/models.dart' hide PlatformFile;
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:path/path.dart';
import 'package:universal_io/io.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<StatefulWidget> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> with ThemeHelpers {
  final RxnBool gettingIcons = RxnBool(null);
  final RxBool playingSendSound = false.obs;
  final RxBool playingReceiveSound = false.obs;
  late final dynamic sendPlayer;
  late final dynamic receivePlayer;

  bool sendPrepared = false;
  bool receivePrepared = false;

  @override
  void initState() {
    super.initState();

    if (kIsDesktop) {
      sendPlayer = Player();
      receivePlayer = Player();
      (sendPlayer as Player).stream.playing.listen((value) => playingSendSound.value = value);
      (receivePlayer as Player).stream.playing.listen((value) => playingReceiveSound.value = value);
    } else {
      sendPlayer = aw.PlayerController();
      receivePlayer = aw.PlayerController();
      (sendPlayer as aw.PlayerController)
          .onPlayerStateChanged
          .listen((value) => playingSendSound.value = value == aw.PlayerState.playing);
      (receivePlayer as aw.PlayerController)
          .onPlayerStateChanged
          .listen((value) => playingReceiveSound.value = value == aw.PlayerState.playing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: "Conversations",
      initialHeader: "Customization",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            <Widget>[
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.showDeliveryTimestamps.value = val;
                          await SettingsSvc.settings.saveOneAsync('showDeliveryTimestamps');
                        },
                        initialVal: SettingsSvc.settings.showDeliveryTimestamps.value,
                        title: "Show Delivery Timestamps",
                        backgroundColor: tileColor,
                      )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  // Only meaningful off the iOS skin, which always uses this menu.
                  if (SettingsSvc.settings.skin.value != Skins.iOS) ...[
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.materialIosMessageMenu.value = val;
                            await SettingsSvc.settings.saveOneAsync('materialIosMessageMenu');
                          },
                          initialVal: SettingsSvc.settings.materialIosMessageMenu.value,
                          title: "iOS-Style Tapback Menu",
                          subtitle: "Long-press a message for the iOS tapback glyphs and options list",
                          backgroundColor: tileColor,
                        )),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  ],
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.recipientAsPlaceholder.value = val;
                          await SettingsSvc.settings.saveOneAsync('recipientAsPlaceholder');
                        },
                        initialVal: SettingsSvc.settings.recipientAsPlaceholder.value,
                        title: "Show Chat Name as Placeholder",
                        subtitle: "Changes the default hint text in the message box to display the recipient name",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                      )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.alwaysShowAvatars.value = val;
                          await SettingsSvc.settings.saveOneAsync('alwaysShowAvatars');
                        },
                        initialVal: SettingsSvc.settings.alwaysShowAvatars.value,
                        title: "Show Avatars in DM Chats",
                        subtitle: "Shows contact avatars in direct messages rather than just in group messages",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                      )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.smartReply.value = val;
                            await SettingsSvc.settings.saveOneAsync('smartReply');
                          },
                          initialVal: SettingsSvc.settings.smartReply.value,
                          title: "Smart Suggestions",
                          subtitle:
                              "Shows reply suggestions in the composer and detects various interactive content in message text",
                          backgroundColor: tileColor,
                          isThreeLine: true,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => AnimatedSizeAndFade.showHide(
                          show: SettingsSvc.settings.smartReply.value,
                          child: SettingsSwitch(
                            onChanged: (bool val) async {
                              SettingsSvc.settings.inlineReplySuggestions.value = val;
                              await SettingsSvc.settings.saveOneAsync('inlineReplySuggestions');
                            },
                            initialVal: SettingsSvc.settings.inlineReplySuggestions.value,
                            title: "Suggestions Inside the Text Field",
                            subtitle:
                                "Shows one suggestion as faint text in the box instead of a row of chips. Tap it to use it, swipe it to see the next one.",
                            backgroundColor: tileColor,
                            isThreeLine: true,
                          ),
                        )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  // OpenBubbles: on-device generative AI (Gemini Nano).
                  if (GenAi.supported) ...[
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.onDeviceAi.value = val;
                            await SettingsSvc.settings.saveOneAsync('onDeviceAi');
                            if (val) await GenAi.refreshStatus();
                          },
                          initialVal: SettingsSvc.settings.onDeviceAi.value,
                          title: "On-device AI (Gemini Nano)",
                          subtitle:
                              "Rewrite and proofread drafts, summarize a conversation, and get Gemini reply suggestions. Runs entirely on this phone; nothing is sent anywhere.",
                          backgroundColor: tileColor,
                          isThreeLine: true,
                        )),
                    Obx(() {
                      if (!SettingsSvc.settings.onDeviceAi.value) return const SizedBox.shrink();
                      final st = GenAi.status;
                      String label(String f) => switch (st[f]) {
                            'available' => 'ready',
                            'downloadable' => 'not downloaded',
                            'downloading' => 'downloading…',
                            null => 'checking…',
                            _ => 'not supported on this device',
                          };
                      final needs = GenAi.features.where((f) => st[f] == 'downloadable' || st[f] == 'downloading').toList();
                      return SettingsTile(
                        title: "AI models",
                        subtitle: "Summaries: ${label('summarize')} · Proofread: ${label('proofread')} · "
                            "Rewrite: ${label('rewrite')} · Reply suggestions: ${label('prompt')}",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                        trailing: needs.isEmpty
                            ? IconButton(icon: const Icon(Icons.refresh), onPressed: GenAi.refreshStatus)
                            : TextButton(
                                child: const Text("Download"),
                                onPressed: () async {
                                  showSnackbar("Downloading", "Fetching ${needs.length} model${needs.length == 1 ? '' : 's'} in the background…");
                                  for (final f in needs) {
                                    try {
                                      await GenAi.download(f);
                                    } catch (e) {
                                      Logger.warn("GenAI download of $f failed: $e", tag: 'GenAI');
                                    }
                                  }
                                  await GenAi.refreshStatus();
                                },
                              ),
                        onTap: GenAi.refreshStatus,
                      );
                    }),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  ],
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.repliesToPrevious.value = val;
                          await SettingsSvc.settings.saveOneAsync('repliesToPrevious');
                        },
                        initialVal: SettingsSvc.settings.repliesToPrevious.value,
                        title: "Show Replies To Previous Message",
                        subtitle: "Shows replies to the previous message in the thread rather than the original",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                      )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  // One tile: a static title/description header, styled like
                  // `SettingsTile`, with the toggle underneath rather than beside
                  // it. `SettingsOptions` gets an empty title so it renders no
                  // label of its own on any skin — the iOS segmented control was
                  // otherwise unlabeled entirely, and Material's inline label sat
                  // beside the control rather than above it either way.
                  //
                  // Both pieces have to live inside one `Column` here, as a single
                  // entry in `SettingsSection.children` — on Material/Samsung,
                  // `M3ESection` gives every *top-level* child its own rounded
                  // corners and a gap from its neighbors, so two separate entries
                  // rendered as two visually distinct tiles despite having no
                  // divider between them. iOS didn't show the seam because its
                  // `SettingsSection` just stacks every child in one card.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 0.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Load Link Previews", style: context.theme.textTheme.bodyLarge),
                            const SizedBox(height: 4.0),
                            Text(
                              "Loading a preview visits the link, which can reveal your IP address and roughly "
                              "when you read the message to whoever controls it.",
                              style: context.theme.textTheme.bodySmall!.copyWith(
                                  color: context.theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75)),
                            ),
                          ],
                        ),
                      ),
                      Obx(() => SettingsOptions<LinkPreviewPolicy>(
                            initial: SettingsSvc.settings.linkPreviewPolicy.value,
                            onChanged: (val) async {
                              if (val == null) return;
                              SettingsSvc.settings.linkPreviewPolicy.value = val;
                              await SettingsSvc.settings.saveOneAsync('linkPreviewPolicy');
                            },
                            options: LinkPreviewPolicy.values,
                            textProcessing: (val) => val.label,
                            capitalize: false,
                            title: "",
                            secondaryColor: headerColor,
                            useModernMenu: true,
                            clampWidth: false
                          )),
                    ],
                  ),
                  if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb)
                    SettingsTile(
                      title: "Message Options Order",
                      subtitle:
                          "Set the order for the options when ${SettingsSvc.settings.doubleTapForDetails.value ? "double-tapping" : "pressing and holding"} a message",
                      onTap: () {
                        NavigationSvc.pushSettings(
                          context,
                          const MessageOptionsOrderPanel(),
                        );
                      },
                      trailing: const NextButton(),
                    ),
                  if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb)
                    SettingsTile(
                      title: "Text Field Buttons",
                      subtitle: "Choose which buttons appear next to the message text field, and their order",
                      onTap: () {
                        NavigationSvc.pushSettings(context, const TextFieldButtonsPanel());
                      },
                      trailing: const NextButton(),
                    ),
                  if (!kIsWeb && backend.getRemoteService() != null)
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && backend.getRemoteService() != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsTile(
                          title: "Sync Group Chat Icons",
                          trailing: Obx(() => gettingIcons.value == null
                              ? const SizedBox.shrink()
                              : gettingIcons.value == true
                                  ? Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 20,
                                        maxWidth: 20,
                                      ),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                      ))
                                  : Icon(Icons.check, color: context.theme.colorScheme.outline)),
                          onTap: () async {
                            gettingIcons.value = true;
                            for (Chat c in ChatsSvc.groupChats) {
                              await Chat.getIcon(c, force: true);
                            }
                            gettingIcons.value = false;
                          },
                          subtitle: "Get iMessage group chat icons from the server",
                        ),
                        const SettingsSubtitle(
                          subtitle: "Note: Overrides any custom avatars set for group chats.",
                        ),
                      ],
                    ),
                  if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.scrollToLastUnread.value = val;
                            await SettingsSvc.settings.saveOneAsync('scrollToLastUnread');
                          },
                          initialVal: SettingsSvc.settings.scrollToLastUnread.value,
                          title: "Store Last Read Message",
                          subtitle:
                              "Remembers the last opened message and allows automatically scrolling back to it if out of view",
                          backgroundColor: tileColor,
                          isThreeLine: true,
                        )),
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) {
                          SettingsSvc.settings.hideNamesForReactions.value = val;
                          SettingsSvc.settings.saveOneAsync("hideNamesForReactions");
                        },
                        initialVal: SettingsSvc.settings.hideNamesForReactions.value,
                        title: "Hide Names in Reaction Details",
                        subtitle:
                            "Enable this to hide names under participant avatars when you view a message's reactions",
                        backgroundColor: tileColor,
                      )),
                ],
              ),
              if (!kIsWeb)
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Sounds",
                ),
              if (!kIsWeb)
                Obx(
                  () => SettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      SettingsTile(
                        title: "Download Sounds",
                        subtitle: "Downloads the official send/receive sounds",
                        onTap: () async {
                          // Capture the navigator that owns the dialog up front.
                          // Get.back() consults Get.isSnackbarOpen first and, when
                          // one is showing, closes the snackbar instead of popping
                          // the route, which left this dialog on screen forever.
                          // Closing through the captured navigator in a finally
                          // block makes the dismissal unconditional, and it runs
                          // before the settings save so a slow or hung write can
                          // no longer hold the dialog open either.
                          final NavigatorState dialogNav = Navigator.of(context, rootNavigator: true);
                          bool dialogClosed = false;
                          void closeDialog() {
                            if (dialogClosed) return;
                            dialogClosed = true;
                            if (dialogNav.canPop()) dialogNav.pop();
                          }

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                                title: Text(
                                  "Downloading sounds...",
                                  style: context.theme.textTheme.titleLarge,
                                ),
                                content: SizedBox(
                                  height: 70,
                                  child: Center(child: buildProgressIndicator(context)),
                                ),
                              );
                            },
                          );
                          try {
                            final sendmsgaudio = await HttpSvc.downloadFromUrl(
                              "https://chatsupport.apple.com/WebAPI801/sound/send-message-audio.m4a",
                              progress: (current, total) {},
                            );
                            final recvmsgaudio = await HttpSvc.downloadFromUrl(
                              "https://chatsupport.apple.com/WebAPI801/sound/received-message-audio.m4a",
                              progress: (current, total) {},
                            );
                            String path = join(FilesystemSvc.soundsPath, "send-message-audio.m4a");
                            await File(path).create(recursive: true);
                            await File(path).writeAsBytes(sendmsgaudio.data!);
                            SettingsSvc.settings.sendSoundPath.value = path;
                            String path2 = join(FilesystemSvc.soundsPath, "receive-message-audio.m4a");
                            await File(path2).create(recursive: true);
                            await File(path2).writeAsBytes(recvmsgaudio.data!);
                            SettingsSvc.settings.receiveSoundPath.value = path2;
                            // Both files are on disk and the paths are set; the
                            // dialog has nothing left to wait for, so drop it
                            // before the save rather than after it.
                            closeDialog();
                            await SettingsSvc.settings.saveManyAsync(["sendSoundPath", "receiveSoundPath"]);
                          } catch (e, s) {
                            Logger.error("Failed to fetch message sounds", error: e, trace: s);
                            showSnackbar("Error", "Failed to fetch audio");
                          } finally {
                            closeDialog();
                          }
                        },
                      ),
                      SettingsTile(
                        title: "${SettingsSvc.settings.sendSoundPath.value == null ? "Add" : "Change"} Send Sound",
                        subtitle: SettingsSvc.settings.sendSoundPath.value != null
                            ? basename(SettingsSvc.settings.sendSoundPath.value!).substring("send-".length)
                            : "Adds a sound to be played when sending a message",
                        onTap: () async {
                          FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
                          if (result != null) {
                            PlatformFile platformFile = result.files.first;
                            String path = join(FilesystemSvc.soundsPath, "send-${platformFile.name}");
                            await File(path).create(recursive: true);
                            await File(path).writeAsBytes(platformFile.bytes!);
                            SettingsSvc.settings.sendSoundPath.value = path;
                            await SettingsSvc.settings.saveOneAsync('sendSoundPath');
                          }
                        },
                        trailing: (SettingsSvc.settings.sendSoundPath.value == null)
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      icon: playingSendSound.value
                                          ? Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.stop
                                              : Icons.stop_outlined)
                                          : Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.play
                                              : Icons.play_arrow_outlined),
                                      onPressed: () async {
                                        if (sendPlayer is Player) {
                                          final Player _sendPlayer = sendPlayer as Player;
                                          if (playingSendSound.value) {
                                            await _sendPlayer.stop();
                                          } else {
                                            await _sendPlayer
                                                .setVolume(SettingsSvc.settings.soundVolume.value.toDouble());
                                            await _sendPlayer.open(Media(SettingsSvc.settings.sendSoundPath.value!));
                                          }
                                        } else if (sendPlayer is aw.PlayerController) {
                                          final aw.PlayerController _sendPlayer = sendPlayer as aw.PlayerController;
                                          if (playingSendSound.value) {
                                            await _sendPlayer.pausePlayer();
                                          } else {
                                            if (!sendPrepared) {
                                              await _sendPlayer.preparePlayer(
                                                  path: SettingsSvc.settings.sendSoundPath.value!,
                                                  volume: SettingsSvc.settings.soundVolume.value.toDouble() / 100);
                                              sendPrepared = true;
                                            }
                                            _sendPlayer.setFinishMode(finishMode: aw.FinishMode.pause);
                                            await _sendPlayer.startPlayer();
                                          }
                                        }
                                      }),
                                  IconButton(
                                    icon: Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                        ? CupertinoIcons.trash
                                        : Icons.delete_outline),
                                    onPressed: () async {
                                      File file = File(SettingsSvc.settings.sendSoundPath.value!);
                                      if (await file.exists()) {
                                        await file.delete();
                                      }
                                      SettingsSvc.settings.sendSoundPath.value = null;
                                      await SettingsSvc.settings.saveOneAsync('sendSoundPath');
                                    },
                                  ),
                                ],
                              ),
                      ),
                      const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                      SettingsTile(
                        title:
                            "${SettingsSvc.settings.receiveSoundPath.value == null ? "Add" : "Change"} Receive Sound",
                        subtitle: SettingsSvc.settings.receiveSoundPath.value != null
                            ? basename(SettingsSvc.settings.receiveSoundPath.value!).substring("receive-".length)
                            : "Adds a sound to be played when receiving a message",
                        onTap: () async {
                          FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
                          if (result != null) {
                            PlatformFile platformFile = result.files.first;
                            String path = join(FilesystemSvc.soundsPath, "receive-${platformFile.name}");
                            await File(path).create(recursive: true);
                            await File(path).writeAsBytes(platformFile.bytes!);
                            SettingsSvc.settings.receiveSoundPath.value = path;
                            await SettingsSvc.settings.saveOneAsync('receiveSoundPath');
                          }
                        },
                        trailing: (SettingsSvc.settings.receiveSoundPath.value == null)
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      icon: playingReceiveSound.value
                                          ? Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.stop
                                              : Icons.stop_outlined)
                                          : Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.play
                                              : Icons.play_arrow_outlined),
                                      onPressed: () async {
                                        if (receivePlayer is Player) {
                                          final Player _receivePlayer = receivePlayer as Player;
                                          if (playingReceiveSound.value) {
                                            await _receivePlayer.stop();
                                          } else {
                                            await _receivePlayer
                                                .setVolume(SettingsSvc.settings.soundVolume.value.toDouble());
                                            await _receivePlayer
                                                .open(Media(SettingsSvc.settings.receiveSoundPath.value!));
                                          }
                                        } else if (receivePlayer is aw.PlayerController) {
                                          final aw.PlayerController _receivePlayer =
                                              receivePlayer as aw.PlayerController;
                                          if (playingReceiveSound.value) {
                                            await _receivePlayer.pausePlayer();
                                          } else {
                                            if (!receivePrepared) {
                                              await _receivePlayer.preparePlayer(
                                                  path: SettingsSvc.settings.receiveSoundPath.value!,
                                                  volume: SettingsSvc.settings.soundVolume.value / 100);
                                              receivePrepared = true;
                                            }
                                            _receivePlayer.setFinishMode(finishMode: aw.FinishMode.pause);
                                            await _receivePlayer.startPlayer();
                                          }
                                        }
                                      }),
                                  IconButton(
                                    icon: Icon(SettingsSvc.settings.skin.value == Skins.iOS
                                        ? CupertinoIcons.trash
                                        : Icons.delete_outline),
                                    onPressed: () async {
                                      File file = File(SettingsSvc.settings.receiveSoundPath.value!);
                                      if (await file.exists()) {
                                        await file.delete();
                                      }
                                      SettingsSvc.settings.receiveSoundPath.value = null;
                                      await SettingsSvc.settings.saveOneAsync('receiveSoundPath');
                                    },
                                  ),
                                ],
                              ),
                      ),
                      const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SettingsTile(
                            title: "Send/Receive Sound Volume",
                            subtitle: "Controls the volume of the send and receive sounds",
                          ),
                          Obx(() => SettingsSlider(
                                startingVal: SettingsSvc.settings.soundVolume.value.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 100,
                                formatValue: (val) => "${val.toInt()}",
                                update: (val) => SettingsSvc.settings.soundVolume.value = val.toInt(),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Gestures",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.autoOpenKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('autoOpenKeyboard');
                          },
                          initialVal: SettingsSvc.settings.autoOpenKeyboard.value,
                          title: "Auto-open Keyboard",
                          subtitle: "Automatically open the keyboard when entering a chat",
                          backgroundColor: tileColor,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.swipeToCloseKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('swipeToCloseKeyboard');
                          },
                          initialVal: SettingsSvc.settings.swipeToCloseKeyboard.value,
                          title: "Swipe Message Box to Close Keyboard",
                          subtitle: "Swipe down on the message box to hide the keyboard",
                          backgroundColor: tileColor,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.swipeToOpenKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('swipeToOpenKeyboard');
                          },
                          initialVal: SettingsSvc.settings.swipeToOpenKeyboard.value,
                          title: "Swipe Message Box to Open Keyboard",
                          subtitle: "Swipe up on the message box to show the keyboard",
                          backgroundColor: tileColor,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.hideKeyboardOnScroll.value = val;
                            await SettingsSvc.settings.saveOneAsync('hideKeyboardOnScroll');
                          },
                          initialVal: SettingsSvc.settings.hideKeyboardOnScroll.value,
                          title: "Hide Keyboard When Scrolling",
                          backgroundColor: tileColor,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.openKeyboardOnSTB.value = val;
                            await SettingsSvc.settings.saveOneAsync('openKeyboardOnSTB');
                          },
                          initialVal: SettingsSvc.settings.openKeyboardOnSTB.value,
                          title: "Open Keyboard After Tapping Scroll To Bottom",
                          backgroundColor: tileColor,
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.doubleTapForDetails.value = val;
                          if (val && SettingsSvc.settings.enableQuickTapback.value) {
                            SettingsSvc.settings.enableQuickTapback.value = false;
                            await SettingsSvc.settings.saveManyAsync(['doubleTapForDetails', 'enableQuickTapback']);
                          } else {
                            await SettingsSvc.settings.saveOneAsync('doubleTapForDetails');
                          }
                        },
                        initialVal: SettingsSvc.settings.doubleTapForDetails.value,
                        title: "Double-${kIsWeb || kIsDesktop ? "Click" : "Tap"} Message for Details",
                        subtitle:
                            "Opens the message details popup when double ${kIsWeb || kIsDesktop ? "click" : "tapp"}ing a message",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                      )),
                  if (!kIsDesktop && !kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsDesktop && !kIsWeb)
                    Obx(() => SettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.sendWithReturn.value = val;
                            await SettingsSvc.settings.saveOneAsync('sendWithReturn');
                          },
                          initialVal: SettingsSvc.settings.sendWithReturn.value,
                          title: "Send Message with Enter",
                          backgroundColor: tileColor,
                        )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.scrollToBottomOnSend.value = val;
                          await SettingsSvc.settings.saveOneAsync('scrollToBottomOnSend');
                        },
                        initialVal: SettingsSvc.settings.scrollToBottomOnSend.value,
                        title: "Scroll To Bottom When Sending Messages",
                        subtitle: "Scroll to the most recent messages in the chat when sending a new text",
                        backgroundColor: tileColor,
                      )),
                ],
              ),

              SettingsHeader(
                  iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Interaction Settings"),
              Obx(() => SettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      SettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.privateSendTypingIndicators.value = val;
                          await SettingsSvc.settings.saveOneAsync('privateSendTypingIndicators');
                        },
                        initialVal: SettingsSvc.settings.privateSendTypingIndicators.value,
                        title: "Send Typing Indicators",
                        subtitle: "Sends typing indicators to other iMessage users",
                        backgroundColor: tileColor,
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.keyboard_chevron_compact_down,
                          materialIcon: Icons.keyboard_alt_outlined,
                          containerColor: Colors.green,
                        ),
                      ),
                      AnimatedSizeAndFade(
                        child: !SettingsSvc.settings.privateManualMarkAsRead.value
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SettingsDivider(),
                                  SettingsSwitch(
                                      onChanged: (bool val) async {
                                        SettingsSvc.settings.privateMarkChatAsRead.value = val;
                                        final toSave = ['privateMarkChatAsRead'];
                                        if (val) {
                                          SettingsSvc.settings.privateManualMarkAsRead.value = false;
                                          toSave.add('privateManualMarkAsRead');
                                        }
                                        await SettingsSvc.settings.saveManyAsync(toSave);
                                      },
                                      initialVal: SettingsSvc.settings.privateMarkChatAsRead.value,
                                      title: "Automatic Mark Read / Send Read Receipts",
                                      subtitle:
                                          "Marks chats read in the iMessage app on your server and sends read receipts to other iMessage users",
                                      backgroundColor: tileColor,
                                      isThreeLine: true,
                                      leading: const SettingsLeadingIcon(
                                        iosIcon: CupertinoIcons.rectangle_fill_badge_checkmark,
                                        materialIcon: Icons.playlist_add_check,
                                        containerColor: Colors.blueAccent,
                                      )),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      AnimatedSizeAndFade.showHide(
                        show: !SettingsSvc.settings.privateMarkChatAsRead.value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SettingsDivider(),
                            SettingsSwitch(
                              onChanged: (bool val) async {
                                SettingsSvc.settings.privateManualMarkAsRead.value = val;
                                await SettingsSvc.settings.saveOneAsync('privateManualMarkAsRead');
                              },
                              initialVal: SettingsSvc.settings.privateManualMarkAsRead.value,
                              title: "Manual Mark Read / Send Read Receipts",
                              subtitle: "Only mark a chat read when pressing the manual mark read button",
                              backgroundColor: tileColor,
                              isThreeLine: true,
                              leading: const SettingsLeadingIcon(
                                iosIcon: CupertinoIcons.check_mark_circled,
                                materialIcon: Icons.check_circle_outline,
                                containerColor: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        title: "Double-${kIsWeb || kIsDesktop ? "Click" : "Tap"} Message for Quick Tapback",
                        initialVal: SettingsSvc.settings.enableQuickTapback.value,
                        onChanged: (bool val) async {
                          SettingsSvc.settings.enableQuickTapback.value = val;
                          final toSave = ['enableQuickTapback'];
                          if (val && SettingsSvc.settings.doubleTapForDetails.value) {
                            SettingsSvc.settings.doubleTapForDetails.value = false;
                            toSave.add('doubleTapForDetails');
                          }
                          await SettingsSvc.settings.saveManyAsync(toSave);
                        },
                        subtitle:
                            "Send a tapback of your choosing when double ${kIsWeb || kIsDesktop ? "click" : "tapp"}ing a message",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.rays,
                          materialIcon: Icons.touch_app_outlined,
                          containerColor: Colors.purple,
                        ),
                      ),
                      AnimatedSizeAndFade.showHide(
                        show: SettingsSvc.settings.enableQuickTapback.value,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5.0),
                          child: Obx(() => ReactionTypePicker(
                                title: "Quick Tapback",
                                currentValue: SettingsSvc.settings.quickTapbackType.value,
                                reactions: ReactionTypes.toList().take(6).toList(),
                                onChanged: (val) async {
                                  if (val == null) return;
                                  SettingsSvc.settings.quickTapbackType.value = val;
                                  await SettingsSvc.settings.saveOneAsync('quickTapbackType');
                                },
                                secondaryColor: headerColor,
                                useModernMenu: true,
                              )),
                        ),
                      ),
                      AnimatedSizeAndFade.showHide(
                        show: backend.canEditUnsend(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SettingsDivider(),
                            SettingsSwitch(
                              title: "Up Arrow for Quick Edit",
                              initialVal: SettingsSvc.settings.editLastSentMessageOnUpArrow.value,
                              onChanged: (bool val) async {
                                SettingsSvc.settings.editLastSentMessageOnUpArrow.value = val;
                                await SettingsSvc.settings.saveOneAsync('editLastSentMessageOnUpArrow');
                              },
                              subtitle: "Press the Up Arrow to begin editing the last message you sent",
                              backgroundColor: tileColor,
                              leading: const SettingsLeadingIcon(
                                iosIcon: CupertinoIcons.arrow_up_square,
                                materialIcon: Icons.arrow_circle_up,
                                containerColor: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSizeAndFade.showHide(
                        show: backend.canSendSubject(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SettingsDivider(),
                            SettingsSwitch(
                              onChanged: (bool val) async {
                                SettingsSvc.settings.privateSubjectLine.value = val;
                                await SettingsSvc.settings.saveOneAsync('privateSubjectLine');
                              },
                              initialVal: SettingsSvc.settings.privateSubjectLine.value,
                              title: "Send Subject Lines",
                              subtitle: "Show the subject line field when sending a message",
                              backgroundColor: tileColor,
                              isThreeLine: true,
                              leading: const SettingsLeadingIcon(
                                iosIcon: CupertinoIcons.textformat,
                                materialIcon: Icons.text_format_rounded,
                                containerColor: Colors.blueAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSizeAndFade.showHide(
                        show: !kIsWeb && !kIsDesktop && Platform.isAndroid,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SettingsDivider(),
                            SettingsSwitch(
                              onChanged: (bool val) async {
                                await pushService.setupZenMode(val);
                              },
                              initialVal: SettingsSvc.settings.enableShareZen.value,
                              title: "Share Status",
                              subtitle: "Other users will see when you have notifications silenced.",
                              backgroundColor: tileColor,
                              isThreeLine: true,
                              leading: const SettingsLeadingIcon(
                                iosIcon: CupertinoIcons.moon_fill,
                                materialIcon: CupertinoIcons.moon_fill,
                                containerColor: Colors.deepPurple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ))
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (kIsDesktop) {
      (sendPlayer as Player).dispose();
      (receivePlayer as Player).dispose();
    } else {
      (sendPlayer as aw.PlayerController).dispose();
      (receivePlayer as aw.PlayerController).dispose();
    }
    super.dispose();
  }
}
