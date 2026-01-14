import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import 'package:bluebubbles/app/components/base/base.dart';
import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/app/components/settings/bb_settings_subtitle.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/message_options_order_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/data/database/models.dart' hide PlatformFile;
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

class _ConversationPanelState extends OptimizedState<ConversationPanel> {
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
              BBSettingsSection(
                backgroundColor: tileColor,
                children: [
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.showDeliveryTimestamps.value = val;
                          await SettingsSvc.settings.saveOneAsync('showDeliveryTimestamps');
                        },
                        value: SettingsSvc.settings.showDeliveryTimestamps.value,
                        title: "Show Delivery Timestamps",
                      )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.recipientAsPlaceholder.value = val;
                          await SettingsSvc.settings.saveOneAsync('recipientAsPlaceholder');
                        },
                        value: SettingsSvc.settings.recipientAsPlaceholder.value,
                        title: "Show Chat Name as Placeholder",
                        subtitle: "Changes the default hint text in the message box to display the recipient name",
                        isThreeLine: true,
                      )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.alwaysShowAvatars.value = val;
                          await SettingsSvc.settings.saveOneAsync('alwaysShowAvatars');
                        },
                        value: SettingsSvc.settings.alwaysShowAvatars.value,
                        title: "Show Avatars in DM Chats",
                        subtitle: "Shows contact avatars in direct messages rather than just in group messages",
                        isThreeLine: true,
                      )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.smartReply.value = val;
                            await SettingsSvc.settings.saveOneAsync('smartReply');
                          },
                          value: SettingsSvc.settings.smartReply.value,
                          title: "Smart Suggestions",
                          subtitle:
                              "Shows smart reply suggestions above the message text field and detects various interactive content in message text",
                          isThreeLine: true,
                        )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.repliesToPrevious.value = val;
                          await SettingsSvc.settings.saveOneAsync('repliesToPrevious');
                        },
                        value: SettingsSvc.settings.repliesToPrevious.value,
                        title: "Show Replies To Previous Message",
                        subtitle: "Shows replies to the previous message in the thread rather than the original",
                        isThreeLine: true,
                      )),
                  if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb)
                    BBSettingsTile(
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
                    BBSettingsTile(
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
                  if (!kIsWeb)
                    const BBSettingsSubtitle(
                      text: "Note: Overrides any custom avatars set for group chats.",
                    ),
                  if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.scrollToLastUnread.value = val;
                            await SettingsSvc.settings.saveOneAsync('scrollToLastUnread');
                          },
                          value: SettingsSvc.settings.scrollToLastUnread.value,
                          title: "Store Last Read Message",
                          subtitle:
                              "Remembers the last opened message and allows automatically scrolling back to it if out of view",
                          isThreeLine: true,
                        )),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) {
                          SettingsSvc.settings.hideNamesForReactions.value = val;
                          SettingsSvc.settings.saveOneAsync("hideNamesForReactions");
                        },
                        value: SettingsSvc.settings.hideNamesForReactions.value,
                        title: "Hide Names in Reaction Details",
                        subtitle:
                            "Enable this to hide names under participant avatars when you view a message's reactions",
                      )),
                ],
              ),
              if (!kIsWeb)
                const BBSettingsHeader(
                  text: "Sounds",
                ),
              if (!kIsWeb)
                Obx(
                  () => BBSettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      BBSettingsTile(
                        title: "${SettingsSvc.settings.sendSoundPath.value == null ? "Add" : "Change"} Send Sound",
                        subtitle: SettingsSvc.settings.sendSoundPath.value != null
                            ? basename(SettingsSvc.settings.sendSoundPath.value!).substring("send-".length)
                            : "Adds a sound to be played when sending a message",
                        onTap: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
                          if (result != null) {
                            PlatformFile platformFile = result.files.first;
                            String path = "${FilesystemSvc.appDocDir.path}/sounds/${"send-"}${platformFile.name}";
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
                                  BBIconButton(
                                      icon: playingSendSound.value
                                          ? (SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.stop
                                              : Icons.stop_outlined)
                                          : (SettingsSvc.settings.skin.value == Skins.iOS
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
                                  BBIconButton(
                                    icon: SettingsSvc.settings.skin.value == Skins.iOS
                                        ? CupertinoIcons.trash
                                        : Icons.delete_outline,
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
                      BBSettingsTile(
                        title:
                            "${SettingsSvc.settings.receiveSoundPath.value == null ? "Add" : "Change"} Receive Sound",
                        subtitle: SettingsSvc.settings.receiveSoundPath.value != null
                            ? basename(SettingsSvc.settings.receiveSoundPath.value!).substring("receive-".length)
                            : "Adds a sound to be played when receiving a message",
                        onTap: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
                          if (result != null) {
                            PlatformFile platformFile = result.files.first;
                            String path = "${FilesystemSvc.appDocDir.path}/sounds/${"receive-"}${platformFile.name}";
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
                                  BBIconButton(
                                      icon: playingReceiveSound.value
                                          ? (SettingsSvc.settings.skin.value == Skins.iOS
                                              ? CupertinoIcons.stop
                                              : Icons.stop_outlined)
                                          : (SettingsSvc.settings.skin.value == Skins.iOS
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
                                  BBIconButton(
                                    icon: SettingsSvc.settings.skin.value == Skins.iOS
                                        ? CupertinoIcons.trash
                                        : Icons.delete_outline,
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
                      const BBSettingsTile(
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
                ),
              const BBSettingsHeader(
                text: "Gestures",
              ),
              BBSettingsSection(
                backgroundColor: tileColor,
                children: [
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.autoOpenKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('autoOpenKeyboard');
                          },
                          value: SettingsSvc.settings.autoOpenKeyboard.value,
                          title: "Auto-open Keyboard",
                          subtitle: "Automatically open the keyboard when entering a chat",
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.swipeToCloseKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('swipeToCloseKeyboard');
                          },
                          value: SettingsSvc.settings.swipeToCloseKeyboard.value,
                          title: "Swipe Message Box to Close Keyboard",
                          subtitle: "Swipe down on the message box to hide the keyboard",
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.swipeToOpenKeyboard.value = val;
                            await SettingsSvc.settings.saveOneAsync('swipeToOpenKeyboard');
                          },
                          value: SettingsSvc.settings.swipeToOpenKeyboard.value,
                          title: "Swipe Message Box to Open Keyboard",
                          subtitle: "Swipe up on the message box to show the keyboard",
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.hideKeyboardOnScroll.value = val;
                            await SettingsSvc.settings.saveOneAsync('hideKeyboardOnScroll');
                          },
                          value: SettingsSvc.settings.hideKeyboardOnScroll.value,
                          title: "Hide Keyboard When Scrolling",
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsWeb && !kIsDesktop)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.openKeyboardOnSTB.value = val;
                            await SettingsSvc.settings.saveOneAsync('openKeyboardOnSTB');
                          },
                          value: SettingsSvc.settings.openKeyboardOnSTB.value,
                          title: "Open Keyboard After Tapping Scroll To Bottom",
                        )),
                  if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.doubleTapForDetails.value = val;
                          if (val && SettingsSvc.settings.enableQuickTapback.value) {
                            SettingsSvc.settings.enableQuickTapback.value = false;
                            await SettingsSvc.settings.saveManyAsync(['doubleTapForDetails', 'enableQuickTapback']);
                          } else {
                            await SettingsSvc.settings.saveOneAsync('doubleTapForDetails');
                          }
                        },
                        value: SettingsSvc.settings.doubleTapForDetails.value,
                        title: "Double-${kIsWeb || kIsDesktop ? "Click" : "Tap"} Message for Details",
                        subtitle:
                            "Opens the message details popup when double ${kIsWeb || kIsDesktop ? "click" : "tapp"}ing a message",
                        isThreeLine: true,
                      )),
                  if (!kIsDesktop && !kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (!kIsDesktop && !kIsWeb)
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.sendWithReturn.value = val;
                            await SettingsSvc.settings.saveOneAsync('sendWithReturn');
                          },
                          value: SettingsSvc.settings.sendWithReturn.value,
                          title: "Send Message with Enter",
                        )),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  Obx(() => BBSettingsSwitch(
                        onChanged: (bool val) async {
                          SettingsSvc.settings.scrollToBottomOnSend.value = val;
                          await SettingsSvc.settings.saveOneAsync('scrollToBottomOnSend');
                        },
                        value: SettingsSvc.settings.scrollToBottomOnSend.value,
                        title: "Scroll To Bottom When Sending Messages",
                        subtitle: "Scroll to the most recent messages in the chat when sending a new text",
                      )),
                ],
              ),
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
