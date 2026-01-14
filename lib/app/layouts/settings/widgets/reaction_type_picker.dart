import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:flutter/material.dart';

/// Reusable widget for selecting a reaction type
/// Used in Private API settings and Notification settings
class ReactionTypePicker extends StatefulWidget {
  final String title;
  final String currentValue;
  final List<String> reactions;
  final Function(String?) onChanged;
  final Color secondaryColor;

  const ReactionTypePicker({
    super.key,
    required this.title,
    required this.currentValue,
    required this.reactions,
    required this.onChanged,
    required this.secondaryColor,
  });

  @override
  State<ReactionTypePicker> createState() => _ReactionTypePickerState();
}

class _ReactionTypePickerState extends State<ReactionTypePicker> {
  late String selectedValue;

  @override
  void initState() {
    super.initState();
    selectedValue = widget.currentValue;
  }

  @override
  void didUpdateWidget(ReactionTypePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentValue != oldWidget.currentValue) {
      selectedValue = widget.currentValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the custom widgets list on each build to reflect the current selection
    final customWidgets = widget.reactions
        .map((reaction) => Padding(
              key: ValueKey('$reaction-${selectedValue == reaction}'),
              padding: const EdgeInsets.symmetric(vertical: 7.5),
              child: ReactionWidget(
                key: ValueKey('reaction-$reaction-${selectedValue == reaction}'),
                reaction: Message(
                  guid: "",
                  associatedMessageType: reaction,
                  isFromMe: selectedValue != reaction,
                ),
                message: null,
              ),
            ))
        .toList();

    return BBSettingsDropdown<String>(
      title: widget.title,
      options: widget.reactions,
      cupertinoCustomWidgets: customWidgets,
      value: selectedValue,
      textProcessing: (val) => val,
      onChanged: (val) {
        setState(() {
          selectedValue = val!;
        });
        widget.onChanged(val);
      },
    );
  }
}
