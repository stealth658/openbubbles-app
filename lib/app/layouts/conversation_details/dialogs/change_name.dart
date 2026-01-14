import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

void showChangeName(Chat chat, String method, BuildContext context) async {
  final newName = await BBInputDialog.text(
    context: context,
    title: "Change Name",
    placeholder: "Chat Name",
    initialValue: chat.displayName,
  );
  
  if (newName == null) return; // User cancelled
  
  if (method == "private-api") {
    BBProgressDialog.show(
      context: context,
      title: newName.isEmpty ? "Removing name..." : "Changing name...",
      message: newName.isEmpty ? "" : "Changing name to $newName",
    );
    
    final response = await HttpSvc.updateChat(chat.guid, newName);
    Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
    
    if (response.statusCode == 200) {
      chat.changeNameAsync(newName);
      showSnackbar("Notice", "Updated name successfully!");
    } else {
      showSnackbar("Error", "Failed to update name!");
    }
  } else {
    chat.changeNameAsync(newName);
  }
}
