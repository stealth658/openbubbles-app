import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/layouts/setup/pages/page_template.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

class RequestContacts extends StatelessWidget {
  const RequestContacts({super.key});

  @override
  Widget build(BuildContext context) {
    return SetupPageTemplate(
      title: "Contacts Permission",
      subtitle: "We'd like to access your contacts to show contact info in the app.",
      belowSubtitle: FutureBuilder<PermissionStatus>(
        future: Permission.contacts.status,
        initialData: PermissionStatus.denied,
        builder: (context, snapshot) {
          bool granted = snapshot.data! == PermissionStatus.granted;
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Permission Status: ${granted ? "Granted" : "Denied"}",
                  style: context.theme.textTheme.bodyLarge!
                      .apply(
                        fontSizeDelta: 1.5,
                        color: granted ? Colors.green : context.theme.colorScheme.error,
                      )
                      .copyWith(height: 2)),
            ),
          );
        },
      ),
      onNextPressed: () async {
        bool hasPermission = await ContactsSvcV2.hasContactAccess;
        if (Platform.isAndroid && !hasPermission) {
          hasPermission = await ContactsSvcV2.requestContactPermission();
        }

        if (!hasPermission) {
          final bool confirmed = await BBAlertDialog.confirm(
            context: context,
            title: "Notice",
            message: "We weren't able to access your contacts.\n\nAre you sure you want to proceed without contacts?",
            confirmLabel: "Yes",
            cancelLabel: "No",
          );
          return confirmed;
        } else {
          return true;
        }
      },
    );
  }
}
