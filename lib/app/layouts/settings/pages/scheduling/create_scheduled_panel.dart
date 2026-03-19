import 'package:animated_size_and_fade/animated_size_and_fade.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:numberpicker/numberpicker.dart';

class CreateScheduledMessage extends StatefulWidget {
  const CreateScheduledMessage({super.key, this.existing});

  final ScheduledMessage? existing;

  @override
  State<CreateScheduledMessage> createState() => _CreateScheduledMessageState();
}

class _CreateScheduledMessageState extends State<CreateScheduledMessage> with ThemeHelpers {
  late final TextEditingController messageController = TextEditingController(text: widget.existing?.payload.message);
  final FocusNode messageNode = FocusNode();
  late final TextEditingController numberController =
      TextEditingController(text: widget.existing?.schedule.interval?.toString() ?? '1');

  late final RxString selectedChat = (widget.existing?.payload.chatGuid ?? ChatsSvc.allChats.first.guid).obs;
  late final RxString schedule = (widget.existing?.schedule.type ?? "once").obs;
  late final RxString frequency = (widget.existing?.schedule.intervalType ?? "daily").obs;
  late final RxInt interval = (widget.existing?.schedule.interval ?? 1).obs;
  late final Rx<DateTime> date = (widget.existing?.scheduledFor ?? DateTime.now()).obs;
  late final RxBool isEmpty = (widget.existing?.payload.message.isNotEmpty ?? false).obs;

  @override
  void initState() {
    super.initState();
    if (messageController.text.isEmpty && !isEmpty.value) {
      isEmpty.value = true;
    } else if (isEmpty.value) {
      isEmpty.value = false;
    }
    messageController.addListener(() {
      if (messageController.text.isEmpty && !isEmpty.value) {
        isEmpty.value = true;
      } else if (isEmpty.value) {
        isEmpty.value = false;
      }
    });
    numberController.addListener(() {
      final value = int.tryParse(numberController.text) ?? 1;
      if (interval.value != value) {
        interval.value = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool isFutureTime = date.value.isBefore(DateTime.now());
      String? error;
      if (isEmpty.value) {
        error = "Please enter a message!";
      } else if (isFutureTime) {
        error = "Please pick a date in the future!";
      }

      return SettingsScaffold(
        title: widget.existing != null ? "Edit Existing" : "Create New",
        initialHeader: "Message Info",
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        tileColor: tileColor,
        headerColor: headerColor,
        fab: error != null
            ? null
            : FloatingActionButton(
                backgroundColor: context.theme.colorScheme.primary,
                child: Icon(iOS ? CupertinoIcons.check_mark : Icons.done,
                    color: context.theme.colorScheme.onPrimary, size: 25),
                onPressed: () async {
                  if (date.value.isBefore(DateTime.now())) return showSnackbar("Error", "Pick a date in the future!");
                  showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: context.theme.colorScheme.properSurface,
                          title: Text(
                            "Scheduling message...",
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
                  Response? response;
                  if (widget.existing != null) {
                    response = await HttpSvc.updateScheduled(
                        widget.existing!.id,
                        selectedChat.value,
                        messageController.text,
                        date.value.toUtc(),
                        schedule.value == "once"
                            ? {
                                "type": "once",
                              }
                            : {
                                "type": "recurring",
                                "interval": interval.value,
                                "intervalType": frequency.value,
                              });
                  } else {
                    response = await HttpSvc.createScheduled(
                        selectedChat.value,
                        messageController.text,
                        date.value.toUtc(),
                        schedule.value == "once"
                            ? {
                                "type": "once",
                              }
                            : {
                                "type": "recurring",
                                "interval": interval.value,
                                "intervalType": frequency.value,
                              });
                  }
                  if (kIsDesktop) {
                    Get.close(1);
                  } else {
                    Navigator.of(context).pop();
                  }
                  if (response.statusCode == 200 && response.data != null) {
                    final data = widget.existing != null ? widget.existing!.toJson() : response.data['data'];
                    // merge new with old
                    if (widget.existing != null) {
                      for (String k in response.data['data'].keys) {
                        data[k] = response.data['data'][k];
                      }
                    }
                    final message = ScheduledMessage.fromJson(data);
                    Navigator.of(context).pop(message);
                  } else {
                    Logger.error("Scheduled message error: ${response.statusCode}");
                    Logger.error(response.data);
                    showSnackbar("Error", "Something went wrong!");
                  }
                },
              ),
        bodySlivers: [
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsSection(backgroundColor: tileColor, children: [
                SettingsOptions<Chat>(
                  initial: ChatsSvc.findChatByGuid(selectedChat.value)!,
                  options: ChatsSvc.allChats,
                  onChanged: (Chat? val) {
                    if (val == null) return;
                    selectedChat.value = val.guid;
                  },
                  title: "Select Chat",
                  secondaryColor: headerColor,
                  textProcessing: (val) => val.toString(),
                  useCupertino: false,
                  clampWidth: false,
                  materialCustomWidgets: (chat) => Row(
                    children: [
                      ContactAvatarGroupWidget(
                        chat: chat,
                        size: 35,
                        editable: false,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 15.0),
                          child: Text(
                            chat.getTitle(),
                            style: context.theme.textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: TextField(
                    textCapitalization: TextCapitalization.sentences,
                    focusNode: messageNode,
                    autocorrect: true,
                    controller: messageController,
                    style: context.theme.extension<BubbleText>()!.bubbleText,
                    keyboardType: TextInputType.multiline,
                    maxLines: 14,
                    minLines: 1,
                    selectionControls: SettingsSvc.settings.skin.value == Skins.iOS
                        ? cupertinoTextSelectionControls
                        : materialTextSelectionControls,
                    enableIMEPersonalizedLearning: !SettingsSvc.settings.incognitoKeyboard.value,
                    textInputAction: TextInputAction.newline,
                    cursorColor: context.theme.colorScheme.primary,
                    cursorHeight: context.theme.extension<BubbleText>()!.bubbleText.fontSize! * 1.25,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(iOS ? 10 : 12.5),
                      isDense: true,
                      isCollapsed: true,
                      hintText: "Message",
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.theme.colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(samsung ? 25 : 10)),
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.theme.colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(samsung ? 25 : 10)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.theme.colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(samsung ? 25 : 10)),
                      ),
                      fillColor: Colors.transparent,
                      hintStyle: context.theme
                          .extension<BubbleText>()!
                          .bubbleText
                          .copyWith(color: context.theme.colorScheme.outline),
                    ),
                    onTap: () {
                      HapticFeedback.selectionClick();
                    },
                    onSubmitted: (String value) {
                      messageNode.unfocus();
                    },
                  ),
                ),
              ]),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Schedule",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  SettingsOptions<String>(
                    initial: schedule.value,
                    options: ["once", "recurring"],
                    onChanged: (String? val) {
                      if (val == null) return;
                      schedule.value = val;
                    },
                    title: "Schedule",
                    secondaryColor: headerColor,
                    textProcessing: (val) => val.capitalizeFirst!,
                  ),
                  AnimatedSizeAndFade.showHide(
                    show: schedule.value == "recurring",
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 15.0),
                            child: Text("Repeat every:", style: context.theme.textTheme.bodyLarge!),
                          ),
                          if (kIsWeb || kIsDesktop) const Spacer(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 15.0),
                              child: kIsWeb || kIsDesktop
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                                      child: TextField(
                                        controller: numberController,
                                        decoration: const InputDecoration(
                                          labelText: "1-100",
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter.allow(RegExp(r'^[1-9]\d?$|^100$|^$'),
                                              replacementString: numberController.text),
                                        ],
                                      ),
                                    )
                                  : NumberPicker(
                                      value: interval.value,
                                      minValue: 1,
                                      maxValue: 100,
                                      itemWidth: 50,
                                      haptics: true,
                                      axis: Axis.horizontal,
                                      textStyle: context.theme.textTheme.bodyLarge!,
                                      selectedTextStyle: context.theme.textTheme.headlineMedium!
                                          .copyWith(color: context.theme.colorScheme.primary),
                                      onChanged: (value) => interval.value = value,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5.0),
                        child: SettingsOptions<String>(
                          title: "With frequency:",
                          options: ["hourly", "daily", "weekly", "monthly", "yearly"],
                          initial: frequency.value,
                          textProcessing: (val) =>
                              "${frequencyToText[val]!.capitalizeFirst!}${interval.value == 1 ? "" : "s"}",
                          onChanged: (val) {
                            if (val == null) return;
                            frequency.value = val;
                          },
                          secondaryColor: headerColor,
                        ),
                      ),
                    ]),
                  ),
                  SettingsTile(
                    title: "Pick date and time",
                    subtitle: "Current: ${buildSeparatorDateSamsung(date.value)} at ${buildTime(date.value)}",
                    onTap: () async {
                      final newDate = await showTimeframePicker("Pick date and time", context, presetsAhead: true);
                      if (newDate == null) return;
                      if (newDate.isBefore(DateTime.now())) return showSnackbar("Error", "Pick a date in the future!");
                      date.value = newDate;
                    },
                  ),
                ],
              ),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Summary",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: ValueListenableBuilder(
                      valueListenable: messageController,
                      builder: (context, value, _) {
                        if (error != null) return Text(error, style: const TextStyle(color: Colors.red));
                        return Text(
                            "Scheduling \"${messageController.text}\" to ${ChatsSvc.findChatByGuid(selectedChat.value)!.getTitle()}.\nScheduling ${schedule.value}${schedule.value == "recurring" ? " every ${interval.value} ${frequencyToText[frequency.value]}(s) starting" : ""} on ${buildSeparatorDateSamsung(date.value)} at ${buildTime(date.value)}.");
                      },
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ],
      );
    });
  }
}
