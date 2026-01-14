import 'package:bluebubbles/app/components/base/base.dart';
import 'package:bluebubbles/app/layouts/settings/pages/scheduling/create_scheduled_panel.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/utils/string_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;

enum _FetchStatus { loading, success, error }

class ScheduledMessagesPanel extends StatefulWidget {
  const ScheduledMessagesPanel({super.key});

  @override
  State<ScheduledMessagesPanel> createState() => _ScheduledMessagesPanelState();
}

class _ScheduledMessagesPanelState extends OptimizedState<ScheduledMessagesPanel> {
  final RxList<ScheduledMessage> scheduled = <ScheduledMessage>[].obs;
  final Rx<_FetchStatus> fetchStatus = Rx<_FetchStatus>(_FetchStatus.loading);

  @override
  void initState() {
    super.initState();
    getExistingMessages();
  }

  Future<void> getExistingMessages() async {
    fetchStatus.value = _FetchStatus.loading;
    try {
      final response = await HttpSvc.getScheduled();
      if (response.statusCode == 200 && response.data['data'] != null) {
        scheduled.value = (response.data['data'] as List)
            .map((e) => ScheduledMessage.fromJson(e))
            .toList()
            .cast<ScheduledMessage>();
        fetchStatus.value = _FetchStatus.success;
      } else {
        fetchStatus.value = _FetchStatus.error;
      }
    } catch (e) {
      Logger.error('Failed to fetch scheduled messages: $e');
      fetchStatus.value = _FetchStatus.error;
    }
  }

  Future<void> deleteMessage(ScheduledMessage item) async {
    try {
      final response = await HttpSvc.deleteScheduled(item.id);
      if (response.statusCode == 200) {
        scheduled.remove(item);
        showSnackbar("Success", "Scheduled message deleted");
      } else {
        Logger.error(response.data);
        showSnackbar("Error", "Failed to delete scheduled message");
      }
    } catch (e) {
      Logger.error('Failed to delete message: $e');
      showSnackbar("Error", "Something went wrong!");
    }
  }

  Future<void> editMessage(ScheduledMessage item) async {
    final result = await NavigationSvc.pushSettings(
      context,
      CreateScheduledMessage(existing: item),
    );
    if (result is ScheduledMessage) {
      final index = scheduled.indexWhere((e) => e.id == item.id);
      if (index != -1) {
        scheduled[index] = result;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final oneTime = scheduled.where((e) => e.schedule.type == "once" && e.status == "pending").toList();
      final oneTimeCompleted = scheduled.where((e) => e.schedule.type == "once" && e.status != "pending").toList();
      final recurring = scheduled.where((e) => e.schedule.type == "recurring").toList();
      final isLoading = fetchStatus.value == _FetchStatus.loading;
      final isError = fetchStatus.value == _FetchStatus.error;
      final isEmpty = fetchStatus.value == _FetchStatus.success && scheduled.isEmpty;

      return SettingsScaffold(
        title: "Scheduled Messages",
        initialHeader: null,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        tileColor: tileColor,
        headerColor: headerColor,
        fab: FloatingActionButton(
          backgroundColor: context.theme.colorScheme.primary,
          child: Icon(iOS ? CupertinoIcons.add : Icons.add, color: context.theme.colorScheme.onPrimary, size: 25),
          onPressed: () async {
            final result = await NavigationSvc.pushSettings(
              context,
              const CreateScheduledMessage(),
            );
            if (result is ScheduledMessage) {
              scheduled.add(result);
            }
          },
        ),
        actions: [
          BBIconButton(
            icon: iOS ? CupertinoIcons.arrow_counterclockwise : Icons.refresh,
            color: context.theme.colorScheme.onBackground,
            onPressed: getExistingMessages,
          ),
        ],
        bodySlivers: [
          if (isLoading || isError || isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 400,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isLoading) ...[
                        const BBLoadingIndicator(size: 40),
                        const SizedBox(height: BBSpacing.md),
                        Text(
                          "Loading scheduled messages...",
                          style: context.theme.textTheme.bodyLarge?.copyWith(
                            color: context.theme.colorScheme.outline,
                          ),
                        ),
                      ] else if (isError) ...[
                        Icon(
                          iOS ? CupertinoIcons.exclamationmark_triangle : Icons.error_outline,
                          size: 64,
                          color: context.theme.colorScheme.error,
                        ),
                        const SizedBox(height: BBSpacing.md),
                        Text(
                          "Failed to load scheduled messages",
                          style: context.theme.textTheme.titleMedium?.copyWith(
                            color: context.theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: BBSpacing.sm),
                        BBTextButton(
                          label: "Try Again",
                          onPressed: getExistingMessages,
                        ),
                      ] else ...[
                        Icon(
                          iOS ? CupertinoIcons.clock : Icons.schedule,
                          size: 64,
                          color: context.theme.colorScheme.outline,
                        ),
                        const SizedBox(height: BBSpacing.md),
                        Text(
                          "No scheduled messages",
                          style: context.theme.textTheme.titleMedium?.copyWith(
                            color: context.theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: BBSpacing.xs),
                        Text(
                          "Tap the + button to create one",
                          style: context.theme.textTheme.bodyMedium?.copyWith(
                            color: context.theme.colorScheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: BBSpacing.md),
                
                // One-Time Messages Section
                if (oneTime.isNotEmpty) ...[
                  _SectionHeader(
                    title: "Pending",
                    subtitle: "Messages that will be sent once",
                    icon: iOS ? CupertinoIcons.clock : Icons.schedule_send,
                    count: oneTime.length,
                  ),
                  const SizedBox(height: BBSpacing.sm),
                  ...oneTime.map((item) => Padding(
                    padding: EdgeInsets.only(
                      left: iOS ? BBSpacing.xl : BBSpacing.lg,
                      right: iOS ? BBSpacing.xl : BBSpacing.lg,
                      bottom: BBSpacing.sm,
                    ),
                    child: _ScheduledMessageCard(
                      message: item,
                      onTap: () => editMessage(item),
                      onDelete: () => deleteMessage(item),
                    ),
                  )),
                ],

                // Recurring Messages Section
                if (recurring.isNotEmpty) ...[
                  if (oneTime.isNotEmpty) const SizedBox(height: BBSpacing.lg),
                  _SectionHeader(
                    title: "Recurring",
                    subtitle: "Messages sent on a schedule",
                    icon: iOS ? CupertinoIcons.repeat : Icons.repeat,
                    count: recurring.length,
                  ),
                  const SizedBox(height: BBSpacing.sm),
                  ...recurring.map((item) => Padding(
                    padding: EdgeInsets.only(
                      left: iOS ? BBSpacing.xl : BBSpacing.lg,
                      right: iOS ? BBSpacing.xl : BBSpacing.lg,
                      bottom: BBSpacing.sm,
                    ),
                    child: _ScheduledMessageCard(
                      message: item,
                      isRecurring: true,
                      onTap: () => editMessage(item),
                      onDelete: () => deleteMessage(item),
                    ),
                  )),
                ],

                // Completed Messages Section
                if (oneTimeCompleted.isNotEmpty) ...[
                  if (oneTime.isNotEmpty || recurring.isNotEmpty) const SizedBox(height: BBSpacing.lg),
                  _SectionHeader(
                    title: "Completed",
                    subtitle: "Messages that have been sent",
                    icon: iOS ? CupertinoIcons.checkmark_circle : Icons.check_circle_outline,
                    count: oneTimeCompleted.length,
                  ),
                  const SizedBox(height: BBSpacing.sm),
                  ...oneTimeCompleted.map((item) => Padding(
                    padding: EdgeInsets.only(
                      left: iOS ? BBSpacing.xl : BBSpacing.lg,
                      right: iOS ? BBSpacing.xl : BBSpacing.lg,
                      bottom: BBSpacing.sm,
                    ),
                    child: _ScheduledMessageCard(
                      message: item,
                      isCompleted: true,
                      onDelete: () => deleteMessage(item),
                    ),
                  )),
                ],

                const SizedBox(height: BBSpacing.xxl),
              ]),
            ),
        ],
      );
    });
  }
}

// Section Header Widget
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SettingsSvc.settings.skin.value == Skins.iOS ? BBSpacing.xl : BBSpacing.lg,
        vertical: BBSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(BBSpacing.sm),
            decoration: BoxDecoration(
              color: context.theme.colorScheme.primaryContainer,
              borderRadius: context.radius.mediumBR,
            ),
            child: Icon(
              icon,
              size: 20,
              color: context.theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: BBSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: context.theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: BBSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BBSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.theme.colorScheme.secondaryContainer,
                        borderRadius: context.radius.smallBR,
                      ),
                      child: Text(
                        count.toString(),
                        style: context.theme.textTheme.labelSmall?.copyWith(
                          color: context.theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: context.theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Scheduled Message Card Widget
class _ScheduledMessageCard extends StatelessWidget {
  final ScheduledMessage message;
  final bool isRecurring;
  final bool isCompleted;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _ScheduledMessageCard({
    required this.message,
    this.isRecurring = false,
    this.isCompleted = false,
    this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final chat = ChatsSvc.getChatState(message.payload.chatGuid);
    final chatName = _parseChatName(chat?.chat);
    final isError = message.status == "error";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radius.mediumBR,
        child: Container(
          padding: const EdgeInsets.all(BBSpacing.md),
          decoration: BoxDecoration(
            color: isError
                ? context.theme.colorScheme.errorContainer.withValues(alpha: 0.3)
                : context.theme.colorScheme.surfaceContainerHighest,
            borderRadius: context.radius.mediumBR,
            border: Border.all(
              color: isError
                  ? context.theme.colorScheme.error.withValues(alpha: 0.3)
                  : context.theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Status Icon
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(context, isError).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getStatusIcon(isError),
                      size: 16,
                      color: _getStatusColor(context, isError),
                    ),
                  ),
                  const SizedBox(width: BBSpacing.sm),
                  // Chat Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatName,
                          style: context.theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _getSubtitleText(),
                          style: context.theme.textTheme.bodySmall?.copyWith(
                            color: isError
                                ? context.theme.colorScheme.error
                                : context.theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Delete Button
                  BBIconButton(
                    icon: SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.trash : Icons.delete_outline,
                    color: context.theme.colorScheme.error,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: BBSpacing.sm),
              // Divider
              Container(
                height: 1,
                color: context.theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: BBSpacing.sm),
              // Message Content
              Text(
                message.payload.message,
                style: context.theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(BuildContext context, bool isError) {
    if (isError) return context.theme.colorScheme.error;
    if (isCompleted) return context.theme.colorScheme.tertiary;
    if (isRecurring) return context.theme.colorScheme.secondary;
    return context.theme.colorScheme.primary;
  }

  IconData _getStatusIcon(bool isError) {
    final isIOS = SettingsSvc.settings.skin.value == Skins.iOS;
    if (isError) return isIOS ? CupertinoIcons.exclamationmark_circle : Icons.error_outline;
    if (isCompleted) return isIOS ? CupertinoIcons.checkmark_circle : Icons.check_circle_outline;
    if (isRecurring) return isIOS ? CupertinoIcons.repeat : Icons.repeat;
    return isIOS ? CupertinoIcons.clock : Icons.schedule;
  }

  String _getSubtitleText() {
    if (message.status == "error") {
      return message.error ?? "Failed to send";
    }
    if (isCompleted) {
      return message.sentAt != null ? "Sent ${buildFullDate(message.sentAt!)}" : "Sent";
    }
    if (isRecurring) {
      return "Every ${message.schedule.interval} ${frequencyToText[message.schedule.intervalType]}(s)";
    }
    return "Scheduled for ${buildFullDate(message.scheduledFor)}";
  }

  String _parseChatName(Chat? chat) {
    if (chat != null) {
      return chat.getTitle();
    }

    // Parse the GUID if chat is null
    String guid = message.payload.chatGuid;

    
    // Check if GUID contains the separator
    if (guid.contains(';-;')) {
      // Split and take the second part (index 1)
      final parts = guid.split(';-;');
      if (parts.length > 1) {
        guid = parts[1];
      }
    }

    // Check if it's an email (contains @)
    if (guid.contains('@')) {
      return guid;
    }

    return formatPhoneNumber(cleansePhoneNumber(guid));
  }
}
