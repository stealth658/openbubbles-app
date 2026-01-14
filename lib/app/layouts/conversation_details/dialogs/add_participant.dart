import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/utils/string_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slugify/slugify.dart';
import 'package:tuple/tuple.dart';

void showAddParticipant(BuildContext context, Chat chat) {
  final TextEditingController participantController = TextEditingController();
  BBCustomDialog.show(
      context: context,
      title: "Add Participant",
      content: TextField(
        controller: participantController,
        decoration: const InputDecoration(
          labelText: "Phone Number / Email",
          border: OutlineInputBorder(),
        ),
        autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
      ),
      actions: [
        BBDialogAction(
          label: "Cancel",
          type: BBDialogButtonType.cancel,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        BBDialogAction(
          label: "Pick Contact",
          type: BBDialogButtonType.secondary,
          onPressed: () async {
            final contacts = <Tuple2<String, String>>[];
            final cache = [];
            String slugText(String text) {
              return slugify(text, delimiter: '').toString().replaceAll('-', '');
            }

            final allContacts = await ContactsSvcV2.getAllContacts();
            for (ContactV2 contact in allContacts) {
              // ContactV2 stores all addresses (phones and emails) in a single list
              for (String address in contact.addresses) {
                String cleansed = slugText(address);

                if (!cache.contains(cleansed)) {
                  cache.add(cleansed);
                  contacts.add(Tuple2(address, contact.displayName));
                }
              }
            }
            contacts.sort((c1, c2) => c1.item2.compareTo(c2.item2));
            final selected = await BBListDialog.showSingle<Tuple2<String, String>>(
              context: context,
              title: "Pick Contact",
              items: contacts.map((c) => BBListItem(
                value: c,
                label: c.item2,
                subtitle: c.item1,
              )).toList(),
            );
            if (selected != null && selected.item1.isNotEmpty) {
              if (!selected.item1.isEmail) {
                participantController.text = cleansePhoneNumber(selected.item1);
              } else {
                participantController.text = selected.item1;
              }
            }
          },
        ),
        BBDialogAction(
          label: "OK",
          type: BBDialogButtonType.primary,
          onPressed: () async {
            if (participantController.text.isEmpty ||
                (!participantController.text.isEmail && !participantController.text.isPhoneNumber)) {
              showSnackbar("Error", "Enter a valid address!");
              return;
            }
            BBProgressDialog.show(
              context: context,
              title: "Adding Participant",
              message: "Adding ${participantController.text}...",
            );
            final response = await HttpSvc.chatParticipant("add", chat.guid, participantController.text);
            Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
            if (response.statusCode == 200) {
              Navigator.of(context, rootNavigator: true).pop(); // Close input dialog
              showSnackbar("Notice", "Added ${participantController.text} successfully!");
            } else {
              Navigator.of(context, rootNavigator: true).pop();
              showSnackbar("Error", "Failed to add ${participantController.text}!");
            }
          },
        ),
      ]);
}
