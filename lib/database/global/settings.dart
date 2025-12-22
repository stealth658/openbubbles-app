import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/details_menu_action.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/interfaces/prefs_interface.dart';
import 'package:bluebubbles/services/backend/settings/shared_preferences_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart' show Level;
import 'package:universal_io/io.dart';

class Settings {
  final RxInt firstFcmRegisterDate = 0.obs;
  final RxString iCloudAccount = "".obs;
  final RxString guidAuthKey = "".obs;
  final RxString serverAddress = "".obs;
  final RxMap<String, String> customHeaders = <String, String>{}.obs;
  final RxBool finishedSetup = false.obs;
  final RxBool reachedConversationList = false.obs;
  final RxBool autoDownload = true.obs;
  final RxBool onlyWifiDownload = false.obs;
  final RxBool autoSave = false.obs;
  final RxString autoSavePicsLocation = "Pictures".obs;
  final RxString autoSaveDocsLocation = "/storage/emulated/0/Download/".obs;
  final RxBool autoOpenKeyboard = true.obs;
  final RxBool hideTextPreviews = false.obs;
  final RxBool showIncrementalSync = false.obs;
  final RxBool highPerfMode = false.obs;
  final RxInt lastIncrementalSync = 0.obs;
  final RxInt lastIncrementalSyncRowId = 0.obs;
  final RxInt refreshRate = 0.obs;
  final RxBool colorfulAvatars = false.obs;
  final RxBool colorfulBubbles = false.obs;
  final RxBool hideDividers = false.obs;
  final RxDouble scrollVelocity = 1.00.obs;
  final RxBool sendWithReturn = false.obs;
  final RxBool doubleTapForDetails = false.obs;
  final RxBool denseChatTiles = false.obs;
  final RxBool smartReply = false.obs;
  final RxBool showConnectionIndicator = false.obs;
  final RxBool showSyncIndicator = true.obs;
  final RxInt sendDelay = 0.obs;
  final RxBool recipientAsPlaceholder = false.obs;
  final RxBool hideKeyboardOnScroll = false.obs;
  final RxBool moveChatCreatorToHeader = false.obs;
  final RxBool cameraFAB = false.obs;
  final RxBool swipeToCloseKeyboard = false.obs;
  final RxBool swipeToOpenKeyboard = false.obs;
  final RxBool openKeyboardOnSTB = false.obs;
  final RxBool swipableConversationTiles = false.obs;
  final RxBool showDeliveryTimestamps = false.obs;
  final RxBool filteredChatList = false.obs;
  final RxBool startVideosMuted = true.obs;
  final RxBool startVideosMutedFullscreen = true.obs;
  final RxBool use24HrFormat = false.obs;
  final RxBool alwaysShowAvatars = false.obs;
  final RxBool notifyOnChatList = false.obs;
  final RxBool notifyReactions = true.obs;
  final RxBool colorsFromMedia = false.obs;
  final Rx<Monet> monetTheming = Monet.none.obs;
  final RxString globalTextDetection = "".obs;
  final RxBool filterUnknownSenders = false.obs;
  final RxBool tabletMode = true.obs;
  final RxBool highlightSelectedChat = true.obs;
  final RxBool immersiveMode = false.obs;
  final RxDouble avatarScale = 1.0.obs;
  final RxBool askWhereToSave = false.obs;
  final RxBool statusIndicatorsOnChats = false.obs;
  final RxInt apiTimeout = 30000.obs;
  final RxBool allowUpsideDownRotation = false.obs;
  final RxBool cancelQueuedMessages = false.obs;
  final RxBool repliesToPrevious = false.obs;
  final RxnString localhostPort = RxnString(null);
  final RxBool useLocalIpv6 = false.obs;
  final RxnString sendSoundPath = RxnString();
  final RxnString receiveSoundPath = RxnString();
  final RxInt soundVolume = 100.obs;
  final RxBool syncContactsAutomatically = false.obs;
  final RxBool scrollToBottomOnSend = true.obs;
  final RxBool sendEventsToTasker = false.obs;
  final RxBool keepAppAlive = false.obs;
  final RxBool unarchiveOnNewMessage = false.obs;
  final RxBool scrollToLastUnread = false.obs;
  final RxString userName = "You".obs;
  final RxnString userAvatarPath = RxnString();
  final RxBool hideNamesForReactions = false.obs;
  final RxBool replaceEmoticonsWithEmoji = false.obs;

  // final RxString emojiFontFamily;

  // Private API features
  final RxnBool serverPrivateAPI = RxnBool();
  final RxBool enablePrivateAPI = false.obs;
  final RxBool privateSendTypingIndicators = false.obs;
  final RxBool privateMarkChatAsRead = false.obs;
  final RxBool privateManualMarkAsRead = false.obs;
  final RxBool privateSubjectLine = false.obs;
  final RxBool privateAPISend = false.obs;
  final RxBool privateAPIAttachmentSend = false.obs;
  final RxBool editLastSentMessageOnUpArrow = false.obs;
  final RxInt lastReviewRequestTimestamp = 0.obs;

  // Redacted Mode Settings
  final RxBool redactedMode = false.obs;
  final RxBool hideAttachments = true.obs;
  final RxBool hideContactInfo = true.obs;
  final RxBool generateFakeContactNames = false.obs;
  final RxBool generateFakeAvatars = false.obs;
  final RxBool hideMessageContent = false.obs;

  // Unified Push Settings
  final RxBool enableUnifiedPush = false.obs;
  final RxString endpointUnifiedPush = RxString("");

  // Quick tapback settings
  final RxBool enableQuickTapback = false.obs;
  final RxString quickTapbackType = ReactionTypes.toList()[0].obs; // The 'love' reaction

  // Slideable action settings
  final Rx<MaterialSwipeAction> materialRightAction = MaterialSwipeAction.pin.obs;
  final Rx<MaterialSwipeAction> materialLeftAction = MaterialSwipeAction.archive.obs;

  // Security settings
  final RxBool shouldSecure = RxBool(false);
  final Rx<SecurityLevel> securityLevel = Rx<SecurityLevel>(SecurityLevel.locked);
  final RxBool incognitoKeyboard = RxBool(false);

  final Rx<Skins> skin = Skins.iOS.obs;
  final Rx<ThemeMode> theme = ThemeMode.system.obs;
  final Rx<SwipeDirection> fullscreenViewerSwipeDir = SwipeDirection.RIGHT.obs;

  // Pin settings
  final RxInt pinRowsPortrait = RxInt(3);
  final RxInt pinColumnsPortrait = RxInt(3);
  final RxInt pinRowsLandscape = RxInt(1);
  final RxInt pinColumnsLandscape = RxInt(4);

  final RxInt maxAvatarsInGroupWidget = RxInt(4);

  // Desktop settings
  final RxBool launchAtStartup = false.obs;
  final RxBool launchAtStartupMinimized = false.obs;
  final RxBool minimizeToTray = false.obs;
  final RxBool closeToTray = true.obs;
  final RxBool spellcheck = true.obs;
  final RxString spellcheckLanguage = "auto".obs;
  final Rx<WindowEffect> windowEffect = WindowEffect.disabled.obs;
  final RxDouble windowEffectCustomOpacityLight = 0.5.obs;
  final RxDouble windowEffectCustomOpacityDark = 0.5.obs;
  final RxBool desktopNotifications = true.obs;
  final RxInt desktopNotificationSoundVolume = 100.obs;
  final RxnString desktopNotificationSoundPath = RxnString();

  // Troubleshooting settings
  final Rx<Level> logLevel = Level.info.obs;

  // Notification actions
  final RxBool showReplyField = true.obs;
  final RxList<int> selectedActionIndices = Platform.isWindows ? [0, 1, 2, 3].obs : [0, 1, 2].obs;
  final RxList<String> actionList = RxList.from([
    "Mark Read",
    ReactionTypes.LOVE,
    ReactionTypes.LIKE,
    ReactionTypes.LAUGH,
    ReactionTypes.EMPHASIZE,
    ReactionTypes.DISLIKE,
    ReactionTypes.QUESTION
  ]);

  // Message options order
  final RxList<DetailsMenuAction> _detailsMenuActions = RxList.from(DetailsMenuAction.values);

  /// Use [setDetailsMenuActions] to set this value
  List<DetailsMenuAction> get detailsMenuActions => _detailsMenuActions;

  // Linux settings
  final RxBool useCustomTitleBar = RxBool(true);

  // Desktop settings
  final RxBool useDesktopAccent = RxBool(false);

  Future<DisplayMode> getDisplayMode() async {
    List<DisplayMode> modes = await FlutterDisplayMode.supported;
    return modes.firstWhereOrNull((element) => element.refreshRate.round() == refreshRate.value) ?? DisplayMode.auto;
  }

  Future<void> _savePref(String key, dynamic value) async {
    if (value is bool) {
      await PrefsSvc.i.setBool(key, value);
    } else if (value is String) {
      await PrefsSvc.i.setString(key, value);
    } else if (value is int) {
      await PrefsSvc.i.setInt(key, value);
    } else if (value is double) {
      await PrefsSvc.i.setDouble(key, value);
    } else if (value is List<DetailsMenuAction>) {
      await PrefsSvc.i.setString(key, jsonEncode(value.map((action) => action.name).toList()));
    } else if (value is List || value is Map) {
      await PrefsSvc.i.setString(key, jsonEncode(value));
    } else if (value == null) {
      await PrefsSvc.i.remove(key);
    }
  }

  Settings save() {
    Map<String, dynamic> map = toMap();
    map.forEach((key, value) async {
      await _savePref(key, value);
    });
    return this;
  }

  Future<Settings> saveAsync() async {
    Map<String, dynamic> map = toMap();

    // Ensure the GlobalIsolate's settings are also updated
    await PrefsInterface.syncAllSettings(settings: map);

    // Wait for each key to be saved before moving on
    await Future.forEach(map.entries, (entry) async {
      await _savePref(entry.key, entry.value);
    });

    return this;
  }

  Future<Settings> saveOneAsync(String key) async {
    Map<String, dynamic> map = toMap();
    if (map.containsKey(key)) {
      // Ensure the GlobalIsolate's settings are also updated
      await PrefsInterface.syncSettings({key: map[key]});
      await _savePref(key, map[key]);
    }

    return this;
  }

  Future<Settings> saveManyAsync(List<String> keys) async {
    Map<String, dynamic> map = toMap();
    map.removeWhere((key, value) => !keys.contains(key));

    // Ensure the GlobalIsolate's settings are also updated
    await PrefsInterface.syncSettings(map);

    for (String key in keys) {
      if (map.containsKey(key)) {
        await _savePref(key, map[key]);
      }
    }

    return this;
  }

  static Settings getSettings() {
    Set<String> keys = PrefsSvc.i.getKeys();

    Map<String, dynamic> items = {};
    for (String s in keys) {
      items[s] = PrefsSvc.i.get(s);
    }
    if (items.isNotEmpty) {
      return Settings.fromMap(items);
    } else {
      return Settings();
    }
  }

  Map<String, dynamic> toMap({bool includeAll = true}) {
    Map<String, dynamic> map = {
      'autoDownload': autoDownload.value,
      'onlyWifiDownload': onlyWifiDownload.value,
      'autoSave': autoSave.value,
      'autoSavePicsLocation': autoSavePicsLocation.value,
      'autoSaveDocsLocation': autoSaveDocsLocation.value,
      'autoOpenKeyboard': autoOpenKeyboard.value,
      'hideTextPreviews': hideTextPreviews.value,
      'showIncrementalSync': showIncrementalSync.value,
      'highPerfMode': highPerfMode.value,
      'lastIncrementalSync': lastIncrementalSync.value,
      'lastIncrementalSyncRowId': lastIncrementalSyncRowId.value,
      'refreshRate': refreshRate.value,
      'colorfulAvatars': colorfulAvatars.value,
      'colorfulBubbles': colorfulBubbles.value,
      'hideDividers': hideDividers.value,
      'scrollVelocity': scrollVelocity.value,
      'sendWithReturn': sendWithReturn.value,
      'doubleTapForDetails': doubleTapForDetails.value,
      'denseChatTiles': denseChatTiles.value,
      'smartReply': smartReply.value,
      'showConnectionIndicator': showConnectionIndicator.value,
      'showSyncIndicator': showSyncIndicator.value,
      'sendDelay': sendDelay.value,
      'recipientAsPlaceholder': recipientAsPlaceholder.value,
      'hideKeyboardOnScroll': hideKeyboardOnScroll.value,
      'moveChatCreatorToHeader': moveChatCreatorToHeader.value,
      'cameraFAB': cameraFAB.value,
      'swipeToCloseKeyboard': swipeToCloseKeyboard.value,
      'swipeToOpenKeyboard': swipeToOpenKeyboard.value,
      'openKeyboardOnSTB': openKeyboardOnSTB.value,
      'swipableConversationTiles': swipableConversationTiles.value,
      'showDeliveryTimestamps': showDeliveryTimestamps.value,
      'filteredChatList': filteredChatList.value,
      'startVideosMuted': startVideosMuted.value,
      'startVideosMutedFullscreen': startVideosMutedFullscreen.value,
      'use24HrFormat': use24HrFormat.value,
      'alwaysShowAvatars': alwaysShowAvatars.value,
      'notifyOnChatList': notifyOnChatList.value,
      'notifyReactions': notifyReactions.value,
      'globalTextDetection': globalTextDetection.value,
      'filterUnknownSenders': filterUnknownSenders.value,
      'tabletMode': tabletMode.value,
      'immersiveMode': immersiveMode.value,
      'avatarScale': avatarScale.value,
      'launchAtStartup': launchAtStartup.value,
      'launchAtStartupMinimized': launchAtStartupMinimized.value,
      'closeToTray': closeToTray.value,
      'spellcheck': spellcheck.value,
      'spellcheckLanguage': spellcheckLanguage.value,
      'minimizeToTray': minimizeToTray.value,
      'showReplyField': showReplyField.value,
      'selectedActionIndices': selectedActionIndices,
      'actionList': actionList,
      'detailsMenuActions': detailsMenuActions.map((action) => action.name).toList(),
      'askWhereToSave': askWhereToSave.value,
      'indicatorsOnPinnedChats': statusIndicatorsOnChats.value,
      'apiTimeout': apiTimeout.value,
      'allowUpsideDownRotation': allowUpsideDownRotation.value,
      'cancelQueuedMessages': cancelQueuedMessages.value,
      'repliesToPrevious': repliesToPrevious.value,
      'useLocalhost': localhostPort.value,
      'useLocalIpv6': useLocalIpv6.value,
      'soundVolume': soundVolume.value,
      'syncContactsAutomatically': syncContactsAutomatically.value,
      'scrollToBottomOnSend': scrollToBottomOnSend.value,
      'sendEventsToTasker': sendEventsToTasker.value,
      'keepAppAlive': keepAppAlive.value,
      'unarchiveOnNewMessage': unarchiveOnNewMessage.value,
      'scrollToLastUnread': scrollToLastUnread.value,
      'userName': userName.value,
      'privateAPISend': privateAPISend.value,
      'privateAPIAttachmentSend': privateAPIAttachmentSend.value,
      'enableUnifiedPush': enableUnifiedPush.value,
      'endpointUnifiedPush': endpointUnifiedPush.value,
      'highlightSelectedChat': highlightSelectedChat.value,
      'enablePrivateAPI': enablePrivateAPI.value,
      'privateSendTypingIndicators': privateSendTypingIndicators.value,
      'privateMarkChatAsRead': privateMarkChatAsRead.value,
      'privateManualMarkAsRead': privateManualMarkAsRead.value,
      'privateSubjectLine': privateSubjectLine.value,
      'editLastSentMessageOnUpArrow': editLastSentMessageOnUpArrow.value,
      'redactedMode': redactedMode.value,
      'hideMessageContent': hideMessageContent.value,
      'hideAttachments': hideAttachments.value,
      'hideContactInfo': hideContactInfo.value,
      'generateFakeContactNames': generateFakeContactNames.value,
      'generateFakeAvatars': generateFakeAvatars.value,
      'generateFakeMessageContent': hideMessageContent.value,
      'enableQuickTapback': enableQuickTapback.value,
      'quickTapbackType': quickTapbackType.value,
      'materialRightAction': materialRightAction.value.index,
      'materialLeftAction': materialLeftAction.value.index,
      'shouldSecure': shouldSecure.value,
      'securityLevel': securityLevel.value.index,
      'incognitoKeyboard': incognitoKeyboard.value,
      'skin': skin.value.index,
      'theme': theme.value.index,
      'fullscreenViewerSwipeDir': fullscreenViewerSwipeDir.value.index,
      'pinRowsPortrait': pinRowsPortrait.value,
      'pinColumnsPortrait': pinColumnsPortrait.value,
      'pinRowsLandscape': pinRowsLandscape.value,
      'pinColumnsLandscape': pinColumnsLandscape.value,
      'maxAvatarsInGroupWidget': maxAvatarsInGroupWidget.value,
      'useCustomTitleBar': useCustomTitleBar.value,
      'windowEffect': windowEffect.value.name,
      'windowEffectCustomOpacityLight': windowEffectCustomOpacityLight.value,
      'windowEffectCustomOpacityDark': windowEffectCustomOpacityDark.value,
      'desktopNotifications': desktopNotifications.value,
      'desktopNotificationSoundVolume': desktopNotificationSoundVolume.value,
      'useDesktopAccent': useDesktopAccent.value,
      'logLevel': logLevel.value.index,
      'hideNamesForReactions': hideNamesForReactions.value,
      'replaceEmoticonsWithEmoji': replaceEmoticonsWithEmoji.value,
      'lastReviewRequestTimestamp': lastReviewRequestTimestamp.value,
    };
    if (includeAll) {
      map.addAll({
        'iCloudAccount': iCloudAccount.value,
        'guidAuthKey': guidAuthKey.value,
        'serverAddress': serverAddress.value,
        'customHeaders': customHeaders,
        'finishedSetup': finishedSetup.value,
        'reachedConversationList': reachedConversationList.value,
        'colorsFromMedia': colorsFromMedia.value,
        'monetTheming': monetTheming.value.index,
        'userAvatarPath': userAvatarPath.value,
        'firstFcmRegisterDate': firstFcmRegisterDate.value,
        'sendSoundPath': sendSoundPath.value,
        'receiveSoundPath': receiveSoundPath.value,
        'desktopNotificationSoundPath': desktopNotificationSoundPath.value,
      });
    }
    return map;
  }

  static void updateFromMap(Map<String, dynamic> map) {
    SettingsSvc.settings.autoDownload.value = map['autoDownload'] ?? true;
    SettingsSvc.settings.onlyWifiDownload.value = map['onlyWifiDownload'] ?? false;
    SettingsSvc.settings.autoSave.value = map['autoSave'] ?? false;
    SettingsSvc.settings.autoSavePicsLocation.value = map['autoSavePicsLocation'] ?? "Pictures";
    SettingsSvc.settings.autoSaveDocsLocation.value = map['autoSaveDocsLocation'] ?? "/storage/emulated/0/Download/";
    SettingsSvc.settings.autoOpenKeyboard.value = map['autoOpenKeyboard'] ?? true;
    SettingsSvc.settings.hideTextPreviews.value = map['hideTextPreviews'] ?? false;
    SettingsSvc.settings.showIncrementalSync.value = map['showIncrementalSync'] ?? false;
    SettingsSvc.settings.highPerfMode.value = map['highPerfMode'] ?? false;
    SettingsSvc.settings.refreshRate.value = map['refreshRate'] ?? 0;
    SettingsSvc.settings.colorfulAvatars.value = map['colorfulAvatars'] ?? false;
    SettingsSvc.settings.colorfulBubbles.value = map['colorfulBubbles'] ?? false;
    SettingsSvc.settings.hideDividers.value = map['hideDividers'] ?? false;
    SettingsSvc.settings.scrollVelocity.value = map['scrollVelocity']?.toDouble() ?? 1;
    SettingsSvc.settings.sendWithReturn.value = map['sendWithReturn'] ?? false;
    SettingsSvc.settings.doubleTapForDetails.value = map['doubleTapForDetails'] ?? false;
    SettingsSvc.settings.denseChatTiles.value = map['denseChatTiles'] ?? false;
    SettingsSvc.settings.smartReply.value = map['smartReply'] ?? false;
    SettingsSvc.settings.showConnectionIndicator.value = map['showConnectionIndicator'] ?? false;
    SettingsSvc.settings.showSyncIndicator.value = map['showSyncIndicator'] ?? true;
    SettingsSvc.settings.sendDelay.value = map['sendDelay'] ?? 0;
    SettingsSvc.settings.recipientAsPlaceholder.value = map['recipientAsPlaceholder'] ?? false;
    SettingsSvc.settings.hideKeyboardOnScroll.value = map['hideKeyboardOnScroll'] ?? false;
    SettingsSvc.settings.moveChatCreatorToHeader.value = map['moveChatCreatorToHeader'] ?? false;
    SettingsSvc.settings.cameraFAB.value = map['cameraFAB'] ?? false;
    SettingsSvc.settings.swipeToCloseKeyboard.value = map['swipeToCloseKeyboard'] ?? false;
    SettingsSvc.settings.swipeToOpenKeyboard.value = map['swipeToOpenKeyboard'] ?? false;
    SettingsSvc.settings.openKeyboardOnSTB.value = map['openKeyboardOnSTB'] ?? false;
    SettingsSvc.settings.swipableConversationTiles.value = map['swipableConversationTiles'] ?? false;
    SettingsSvc.settings.showDeliveryTimestamps.value = map['showDeliveryTimestamps'] ?? false;
    SettingsSvc.settings.filteredChatList.value = map['filteredChatList'] ?? false;
    SettingsSvc.settings.startVideosMuted.value = map['startVideosMuted'] ?? true;
    SettingsSvc.settings.startVideosMutedFullscreen.value = map['startVideosMutedFullscreen'] ?? true;
    SettingsSvc.settings.use24HrFormat.value = map['use24HrFormat'] ?? false;
    SettingsSvc.settings.alwaysShowAvatars.value = map['alwaysShowAvatars'] ?? false;
    SettingsSvc.settings.notifyOnChatList.value = map['notifyOnChatList'] ?? false;
    SettingsSvc.settings.notifyReactions.value = map['notifyReactions'] ?? true;
    SettingsSvc.settings.globalTextDetection.value = map['globalTextDetection'] ?? "";
    SettingsSvc.settings.filterUnknownSenders.value = map['filterUnknownSenders'] ?? false;
    SettingsSvc.settings.tabletMode.value = kIsDesktop || (map['tabletMode'] ?? true);
    SettingsSvc.settings.immersiveMode.value = map['immersiveMode'] ?? false;
    SettingsSvc.settings.avatarScale.value = map['avatarScale']?.toDouble() ?? 1.0;
    SettingsSvc.settings.launchAtStartup.value = map['launchAtStartup'] ?? false;
    SettingsSvc.settings.launchAtStartupMinimized.value = map['launchAtStartupMinimized'] ?? false;
    SettingsSvc.settings.closeToTray.value = map['closeToTray'] ?? true;
    SettingsSvc.settings.spellcheck.value = map['spellcheck'] ?? true;
    SettingsSvc.settings.spellcheckLanguage.value = map['spellcheckLanguage'] ?? 'auto';
    SettingsSvc.settings.minimizeToTray.value = map['minimizeToTray'] ?? false;
    SettingsSvc.settings.askWhereToSave.value = map['askWhereToSave'] ?? false;
    SettingsSvc.settings.statusIndicatorsOnChats.value = map['indicatorsOnPinnedChats'] ?? false;
    SettingsSvc.settings.apiTimeout.value = map['apiTimeout'] ?? 15000;
    SettingsSvc.settings.allowUpsideDownRotation.value = map['allowUpsideDownRotation'] ?? false;
    SettingsSvc.settings.cancelQueuedMessages.value = map['cancelQueuedMessages'] ?? false;
    SettingsSvc.settings.repliesToPrevious.value = map['repliesToPrevious'] ?? false;
    SettingsSvc.settings.localhostPort.value = map['useLocalhost'];
    SettingsSvc.settings.useLocalIpv6.value = map['useLocalIpv6'] ?? false;
    SettingsSvc.settings.sendSoundPath.value = map['sendSoundPath'];
    SettingsSvc.settings.receiveSoundPath.value = map['receiveSoundPath'];
    SettingsSvc.settings.soundVolume.value = map['soundVolume'] ?? 100;
    SettingsSvc.settings.syncContactsAutomatically.value = map['syncContactsAutomatically'] ?? false;
    SettingsSvc.settings.scrollToBottomOnSend.value = map['scrollToBottomOnSend'] ?? true;
    SettingsSvc.settings.sendEventsToTasker.value = map['sendEventsToTasker'] ?? true;
    SettingsSvc.settings.keepAppAlive.value = map['keepAppAlive'] ?? false;
    SettingsSvc.settings.unarchiveOnNewMessage.value = map['unarchiveOnNewMessage'] ?? false;
    SettingsSvc.settings.scrollToLastUnread.value = map['scrollToLastUnread'] ?? false;
    SettingsSvc.settings.userName.value = map['userName'] ?? "You";
    SettingsSvc.settings.privateAPISend.value = map['privateAPISend'] ?? false;
    SettingsSvc.settings.privateAPIAttachmentSend.value = map['privateAPIAttachmentSend'] ?? false;
    SettingsSvc.settings.enablePrivateAPI.value = map['enablePrivateAPI'] ?? false;
    SettingsSvc.settings.privateSendTypingIndicators.value = map['privateSendTypingIndicators'] ?? false;
    SettingsSvc.settings.privateMarkChatAsRead.value = map['privateMarkChatAsRead'] ?? false;
    SettingsSvc.settings.privateManualMarkAsRead.value = map['privateManualMarkAsRead'] ?? false;
    SettingsSvc.settings.privateSubjectLine.value = map['privateSubjectLine'] ?? false;
    SettingsSvc.settings.editLastSentMessageOnUpArrow.value = map['editLastSentMessageOnUpArrow'] ?? false;
    SettingsSvc.settings.redactedMode.value = map['redactedMode'] ?? false;
    SettingsSvc.settings.hideMessageContent.value = map['hideMessageContent'] ?? true;
    SettingsSvc.settings.hideAttachments.value = map['hideAttachments'] ?? true;
    SettingsSvc.settings.hideContactInfo.value = map['hideContactInfo'] ?? true;
    SettingsSvc.settings.generateFakeContactNames.value = map['generateFakeContactNames'] ?? false;
    SettingsSvc.settings.generateFakeAvatars.value = map['generateFakeAvatars'] ?? false;
    SettingsSvc.settings.hideMessageContent.value = map['generateFakeMessageContent'] ?? false;
    SettingsSvc.settings.enableUnifiedPush.value = map['enableUnifiedPush'] ?? false;
    SettingsSvc.settings.endpointUnifiedPush.value = map['endpointUnifiedPush'] ?? "";
    SettingsSvc.settings.enableQuickTapback.value = map['enableQuickTapback'] ?? false;
    SettingsSvc.settings.quickTapbackType.value = map['quickTapbackType'] ?? ReactionTypes.toList()[0];
    SettingsSvc.settings.materialRightAction.value = map['materialRightAction'] != null
        ? MaterialSwipeAction.values[map['materialRightAction']]
        : MaterialSwipeAction.pin;
    SettingsSvc.settings.materialLeftAction.value = map['materialLeftAction'] != null
        ? MaterialSwipeAction.values[map['materialLeftAction']]
        : MaterialSwipeAction.archive;
    SettingsSvc.settings.shouldSecure.value = map['shouldSecure'] ?? false;
    SettingsSvc.settings.securityLevel.value =
        map['securityLevel'] != null ? SecurityLevel.values[map['securityLevel']] : SecurityLevel.locked;
    SettingsSvc.settings.incognitoKeyboard.value = map['incognitoKeyboard'] ?? false;
    SettingsSvc.settings.skin.value = map['skin'] != null ? Skins.values[map['skin']] : Skins.iOS;
    SettingsSvc.settings.theme.value = map['theme'] != null ? ThemeMode.values[map['theme']] : ThemeMode.system;
    SettingsSvc.settings.fullscreenViewerSwipeDir.value = map['fullscreenViewerSwipeDir'] != null
        ? SwipeDirection.values[map['fullscreenViewerSwipeDir']]
        : SwipeDirection.RIGHT;
    SettingsSvc.settings.pinRowsPortrait.value = map['pinRowsPortrait'] ?? 3;
    SettingsSvc.settings.pinColumnsPortrait.value = map['pinColumnsPortrait'] ?? 3;
    SettingsSvc.settings.pinRowsLandscape.value = map['pinRowsLandscape'] ?? 1;
    SettingsSvc.settings.pinColumnsLandscape.value = map['pinColumnsLandscape'] ?? 4;
    SettingsSvc.settings.maxAvatarsInGroupWidget.value = map['maxAvatarsInGroupWidget'] ?? 4;
    SettingsSvc.settings.useCustomTitleBar.value = map['useCustomTitleBar'] ?? true;

    SettingsSvc.settings.showReplyField.value = map['showReplyField'] ?? true;
    SettingsSvc.settings.selectedActionIndices.value = _processSelectedActionIndices(map['selectedActionIndices'], SettingsSvc.settings.showReplyField.value);
    SettingsSvc.settings.actionList.value = _processActionList(map['actionList']);
    SettingsSvc.settings._detailsMenuActions.value = _processDetailsMenuActions(map['detailsMenuActions'], SettingsSvc.settings.detailsMenuActions);

    SettingsSvc.settings.windowEffect.value = kIsDesktop && Platform.isWindows
        ? WindowEffect.values.firstWhereOrNull((e) => e.name == map['windowEffect']) ?? WindowEffect.disabled
        : WindowEffect.disabled;
    SettingsSvc.settings.windowEffectCustomOpacityLight.value = map['windowEffectCustomOpacityLight']?.toDouble() ?? 0.5;
    SettingsSvc.settings.windowEffectCustomOpacityDark.value = map['windowEffectCustomOpacityDark']?.toDouble() ?? 0.5;
    SettingsSvc.settings.desktopNotifications.value = map['desktopNotifications'] ?? true;
    SettingsSvc.settings.desktopNotificationSoundVolume.value = map['desktopNotificationSoundVolume'] ?? 100;
    SettingsSvc.settings.desktopNotificationSoundPath.value = map['desktopNotificationSoundPath'];
    SettingsSvc.settings.useDesktopAccent.value = map['useDesktopAccent'] ?? map['useWindowsAccent'] ?? false;
    SettingsSvc.settings.firstFcmRegisterDate.value = map['firstFcmRegisterDate'] ?? 0;
    SettingsSvc.settings.logLevel.value = map['logLevel'] != null ? Level.values[map['logLevel']] : Level.info;
    SettingsSvc.settings.hideNamesForReactions.value = map['hideNamesForReactions'] ?? false;
    SettingsSvc.settings.replaceEmoticonsWithEmoji.value = map['replaceEmoticonsWithEmoji'] ?? false;
    SettingsSvc.settings.save();

    eventDispatcher.emit("theme-update", null);
  }

  static Settings fromMap(Map<String, dynamic> map) {
    Settings s = Settings();
    s.iCloudAccount.value = map['iCloudAccount'] ?? "";
    s.guidAuthKey.value = map['guidAuthKey'] ?? "";
    s.serverAddress.value = map['serverAddress'] ?? "";
    s.customHeaders.value = _processCustomHeaders(map['customHeaders']);
    s.finishedSetup.value = map['finishedSetup'] ?? false;
    s.autoDownload.value = map['autoDownload'] ?? true;
    s.autoSave.value = map['autoSave'] ?? false;
    s.autoSavePicsLocation.value = map['autoSavePicsLocation'] ?? "Pictures";
    s.autoSaveDocsLocation.value = map['autoSaveDocsLocation'] ?? "/storage/emulated/0/Download/";
    s.onlyWifiDownload.value = map['onlyWifiDownload'] ?? false;
    s.autoOpenKeyboard.value = map['autoOpenKeyboard'] ?? true;
    s.hideTextPreviews.value = map['hideTextPreviews'] ?? false;
    s.showIncrementalSync.value = map['showIncrementalSync'] ?? false;
    s.highPerfMode.value = map['highPerfMode'] ?? false;
    s.lastIncrementalSync.value = map['lastIncrementalSync'] ?? 0;
    s.lastIncrementalSyncRowId.value = map['lastIncrementalSyncRowId'] ?? 0;
    s.refreshRate.value = map['refreshRate'] ?? 0;
    s.colorfulAvatars.value = map['colorfulAvatars'] ?? false;
    s.colorfulBubbles.value = map['colorfulBubbles'] ?? false;
    s.hideDividers.value = map['hideDividers'] ?? false;
    s.scrollVelocity.value = map['scrollVelocity']?.toDouble() ?? 1;
    s.sendWithReturn.value = map['sendWithReturn'] ?? false;
    s.doubleTapForDetails.value = map['doubleTapForDetails'] ?? false;
    s.denseChatTiles.value = map['denseChatTiles'] ?? false;
    s.smartReply.value = map['smartReply'] ?? false;
    s.showConnectionIndicator.value = map['showConnectionIndicator'] ?? false;
    s.showSyncIndicator.value = map['showSyncIndicator'] ?? true;
    s.sendDelay.value = map['sendDelay'] ?? 0;
    s.recipientAsPlaceholder.value = map['recipientAsPlaceholder'] ?? false;
    s.hideKeyboardOnScroll.value = map['hideKeyboardOnScroll'] ?? false;
    s.moveChatCreatorToHeader.value = map['moveChatCreatorToHeader'] ?? false;
    s.cameraFAB.value = map['cameraFAB'] ?? false;
    s.swipeToCloseKeyboard.value = map['swipeToCloseKeyboard'] ?? false;
    s.swipeToOpenKeyboard.value = map['swipeToOpenKeyboard'] ?? false;
    s.openKeyboardOnSTB.value = map['openKeyboardOnSTB'] ?? false;
    s.swipableConversationTiles.value = map['swipableConversationTiles'] ?? false;
    s.showDeliveryTimestamps.value = map['showDeliveryTimestamps'] ?? false;
    s.filteredChatList.value = map['filteredChatList'] ?? false;
    s.startVideosMuted.value = map['startVideosMuted'] ?? true;
    s.startVideosMutedFullscreen.value = map['startVideosMutedFullscreen'] ?? true;
    s.use24HrFormat.value = map['use24HrFormat'] ?? false;
    s.alwaysShowAvatars.value = map['alwaysShowAvatars'] ?? false;
    s.notifyOnChatList.value = map['notifyOnChatList'] ?? false;
    s.notifyReactions.value = map['notifyReactions'] ?? true;
    s.colorsFromMedia.value = map['colorsFromMedia'] ?? false;
    s.monetTheming.value = map['monetTheming'] != null ? Monet.values[map['monetTheming']] : Monet.none;
    s.globalTextDetection.value = map['globalTextDetection'] ?? "";
    s.filterUnknownSenders.value = map['filterUnknownSenders'] ?? false;
    s.tabletMode.value = kIsDesktop || (map['tabletMode'] ?? true);
    s.highlightSelectedChat.value = map['highlightSelectedChat'] ?? true;
    s.immersiveMode.value = map['immersiveMode'] ?? false;
    s.avatarScale.value = map['avatarScale']?.toDouble() ?? 1.0;
    s.launchAtStartup.value = map['launchAtStartup'] ?? false;
    s.launchAtStartupMinimized.value = map['launchAtStartupMinimized'] ?? false;
    s.closeToTray.value = map['closeToTray'] ?? true;
    s.spellcheck.value = map['spellcheck'] ?? true;
    s.spellcheckLanguage.value = map['spellcheckLanguage'] ?? 'auto';
    s.minimizeToTray.value = map['minimizeToTray'] ?? false;
    s.askWhereToSave.value = map['askWhereToSave'] ?? false;
    s.statusIndicatorsOnChats.value = map['indicatorsOnPinnedChats'] ?? false;
    s.apiTimeout.value = map['apiTimeout'] ?? 15000;
    s.allowUpsideDownRotation.value = map['allowUpsideDownRotation'] ?? false;
    s.cancelQueuedMessages.value = map['cancelQueuedMessages'] ?? false;
    s.repliesToPrevious.value = map['repliesToPrevious'] ?? false;
    s.localhostPort.value = map['useLocalhost'];
    s.useLocalIpv6.value = map['useLocalIpv6'] ?? false;
    s.sendSoundPath.value = map['sendSoundPath'];
    s.receiveSoundPath.value = map['receiveSoundPath'];
    s.soundVolume.value = map['soundVolume'] ?? 100;
    s.syncContactsAutomatically.value = map['syncContactsAutomatically'] ?? false;
    s.scrollToBottomOnSend.value = map['scrollToBottomOnSend'] ?? true;
    s.sendEventsToTasker.value = map['sendEventsToTasker'] ?? false;
    s.keepAppAlive.value = map['keepAppAlive'] ?? false;
    s.unarchiveOnNewMessage.value = map['unarchiveOnNewMessage'] ?? false;
    s.scrollToLastUnread.value = map['scrollToLastUnread'] ?? false;
    s.userName.value = map['userName'] ?? "You";
    s.userAvatarPath.value = map['userAvatarPath'];
    s.privateAPISend.value = map['privateAPISend'] ?? false;
    s.privateAPIAttachmentSend.value = map['privateAPIAttachmentSend'] ?? false;
    s.enablePrivateAPI.value = map['enablePrivateAPI'] ?? false;
    s.privateSendTypingIndicators.value = map['privateSendTypingIndicators'] ?? false;
    s.privateMarkChatAsRead.value = map['privateMarkChatAsRead'] ?? false;
    s.privateManualMarkAsRead.value = map['privateManualMarkAsRead'] ?? false;
    s.privateSubjectLine.value = map['privateSubjectLine'] ?? false;
    s.editLastSentMessageOnUpArrow.value = map['editLastSentMessageOnUpArrow'] ?? false;
    s.redactedMode.value = map['redactedMode'] ?? false;
    s.hideMessageContent.value = map['hideMessageContent'] ?? true;
    s.hideAttachments.value = map['hideAttachments'] ?? true;
    s.hideContactInfo.value = map['hideContactInfo'] ?? true;
    s.generateFakeContactNames.value = map['generateFakeContactNames'] ?? false;
    s.generateFakeAvatars.value = map['generateFakeAvatars'] ?? false;
    s.hideMessageContent.value = map['generateFakeMessageContent'] ?? false;
    s.enableUnifiedPush.value = map['enableUnifiedPush'] ?? false;
    s.endpointUnifiedPush.value = map['endpointUnifiedPush'] ?? "";
    s.enableQuickTapback.value = map['enableQuickTapback'] ?? false;
    s.quickTapbackType.value = map['quickTapbackType'] ?? ReactionTypes.toList()[0];
    s.materialRightAction.value = map['materialRightAction'] != null
        ? MaterialSwipeAction.values[map['materialRightAction']]
        : MaterialSwipeAction.pin;
    s.materialLeftAction.value = map['materialLeftAction'] != null
        ? MaterialSwipeAction.values[map['materialLeftAction']]
        : MaterialSwipeAction.archive;
    s.shouldSecure.value = map['shouldSecure'] ?? false;
    s.securityLevel.value =
        map['securityLevel'] != null ? SecurityLevel.values[map['securityLevel']] : SecurityLevel.locked;
    s.incognitoKeyboard.value = map['incognitoKeyboard'] ?? false;
    s.skin.value = map['skin'] != null ? Skins.values[map['skin']] : Skins.iOS;
    s.theme.value = map['theme'] != null ? ThemeMode.values[map['theme']] : ThemeMode.system;
    s.fullscreenViewerSwipeDir.value = map['fullscreenViewerSwipeDir'] != null
        ? SwipeDirection.values[map['fullscreenViewerSwipeDir']]
        : SwipeDirection.RIGHT;
    s.pinRowsPortrait.value = map['pinRowsPortrait'] ?? 3;
    s.pinColumnsPortrait.value = map['pinColumnsPortrait'] ?? 3;
    s.pinRowsLandscape.value = map['pinRowsLandscape'] ?? 1;
    s.pinColumnsLandscape.value = map['pinColumnsLandscape'] ?? 4;
    s.maxAvatarsInGroupWidget.value = map['maxAvatarsInGroupWidget'] ?? 4;
    s.useCustomTitleBar.value = map['useCustomTitleBar'] ?? true;

    s.showReplyField.value = map['showReplyField'] ?? true;
    s.selectedActionIndices.value = _processSelectedActionIndices(map['selectedActionIndices'], s.showReplyField.value);
    s.actionList.value = _processActionList(map['actionList']);
    s._detailsMenuActions.value = _processDetailsMenuActions(map['detailsMenuActions'], DetailsMenuAction.values);

    s.windowEffect.value = (kIsDesktop && Platform.isWindows)
        ? WindowEffect.values.firstWhereOrNull((e) => e.name == map['windowEffect']) ?? WindowEffect.disabled
        : WindowEffect.disabled;
    s.windowEffectCustomOpacityLight.value = map['windowEffectCustomOpacityLight']?.toDouble() ?? 0.5;
    s.windowEffectCustomOpacityDark.value = map['windowEffectCustomOpacityDark']?.toDouble() ?? 0.5;
    s.desktopNotifications.value = map['desktopNotifications'] ?? true;
    s.desktopNotificationSoundVolume.value = map['desktopNotificationSoundVolume'] ?? 100;
    s.desktopNotificationSoundPath.value = map['desktopNotificationSoundPath'];
    s.useDesktopAccent.value = map['useDesktopAccent'] ?? map['useWindowsAccent'] ?? false;
    s.firstFcmRegisterDate.value = map['firstFcmRegisterDate'] ?? 0;
    s.logLevel.value = map['logLevel'] != null ? Level.values[map['logLevel']] : Level.info;
    s.hideNamesForReactions.value = map['hideNamesForReactions'] ?? false;
    s.replaceEmoticonsWithEmoji.value = map['replaceEmoticonsWithEmoji'] ?? false;
    s.lastReviewRequestTimestamp.value = map['lastReviewRequestTimestamp'] ?? 0;
    return s;
  }

  /// function to set detailsMenuActions from a subset of allActions
  void setDetailsMenuActions(List<DetailsMenuAction> actions) {
    SettingsSvc.settings._detailsMenuActions.value = _filterDetailsMenuActions(actions, SettingsSvc.settings.detailsMenuActions);
    SettingsSvc.settings.save();
  }

  void resetDetailsMenuActions() {
    SettingsSvc.settings._detailsMenuActions.value = DetailsMenuAction.values;
    SettingsSvc.settings.save();
  }
}

Map<String, String> _processCustomHeaders(dynamic rawJson) {
  try {
    return (rawJson is Map ? rawJson : jsonDecode(rawJson) as Map).cast<String, String>();
  } catch (e) {
    debugPrint("Using default customHeaders");
    return {};
  }
}

List<int> _processSelectedActionIndices(dynamic rawJson, bool showReplyField) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List).cast<int>().take(Platform.isWindows ? (showReplyField ? 4 : 5) : 3).sorted(Comparable.compare);
  } catch (e) {
    debugPrint("Using default selectedActionIndices");
    return [0, 1, 2, 3, 4].take(Platform.isWindows ? (showReplyField ? 4 : 5) : 3).sorted(Comparable.compare);
  }
}

List<String> _processActionList(dynamic rawJson) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List).cast<String>();
  } catch (e) {
    debugPrint("Using default actionList");
    return [
      "Mark Read",
      ReactionTypes.LOVE,
      ReactionTypes.LIKE,
      ReactionTypes.LAUGH,
      ReactionTypes.EMPHASIZE,
      ReactionTypes.DISLIKE,
      ReactionTypes.QUESTION
    ];
  }
}

List<DetailsMenuAction> _processDetailsMenuActions(dynamic rawJson, List<DetailsMenuAction> allActions) {
  try {
    List<DetailsMenuAction> actions = (rawJson is List ? rawJson : jsonDecode(rawJson) as List)
        .cast<String>()
        .map((s) => DetailsMenuAction.values.firstWhereOrNull((action) => action.name == s))
        .nonNulls
        .toList();
    return _filterDetailsMenuActions(actions, allActions);
  } catch (e) {
    debugPrint("Using default detailsMenuActions");
    return DetailsMenuAction.values;
  }
}

List<DetailsMenuAction> _filterDetailsMenuActions(List<DetailsMenuAction> actions, List<DetailsMenuAction> allActions) {
  // Keep existing order of other keys
  List<(DetailsMenuAction, int)> remainingIndexed = allActions.mapIndexed((i, action) => (action, i)).whereNot((mapEntry) => actions.contains(mapEntry.$1)).toList();

  for ((DetailsMenuAction, int) item in remainingIndexed) {
    actions.insert(item.$2, item.$1);
  }

  return actions;
}
