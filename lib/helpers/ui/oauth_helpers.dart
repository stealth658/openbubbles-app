import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:desktop_webview_auth/desktop_webview_auth.dart';
import 'package:desktop_webview_auth/google.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:universal_io/io.dart';
import 'package:window_manager/window_manager.dart';

Future<String?> googleOAuth(BuildContext context) async {
  String? token;

  final defaultScopes = [
    'https://www.googleapis.com/auth/cloudplatformprojects',
    'https://www.googleapis.com/auth/firebase',
    'https://www.googleapis.com/auth/datastore'
  ];

  // android / web implementation
  if (Platform.isAndroid || kIsWeb) {
    // on web, show a dialog to make sure users allow scopes
    if (kIsWeb) {
      await BBAlertDialog.show(
        context: context,
        config: const BBAlertDialogConfig(barrierDismissible: false),
        title: "Important Notice",
        message:
            'Please make sure to allow BlueBubbles to see, edit, configure, and delete your Google Cloud data after signing in. BlueBubbles will only use this ability to find your server URL.',
        actions: [
          BBDialogAction(
            label: "OK",
            type: BBDialogButtonType.primary,
            onPressed: () {},
          ),
        ],
      );
    }

    // initialize gsi
    final gsi = GoogleSignIn.instance;
    await gsi.initialize(clientId: fdb.getClientId());
    GoogleSignInAccount? account = await gsi.attemptLightweightAuthentication();
    if (account == null) {
      try {
        // sign out then sign in
        await gsi.signOut();
        account = await gsi.authenticate(scopeHint: defaultScopes);
        // get access token
        final auth = account.authentication;
        token = auth.idToken;
        // error if token is not present
        if (token == null) {
          throw Exception("No access token!");
        }
      } catch (e, stack) {
        Logger.error("Failed to sign in with Google (Android/Web)", error: e, trace: stack);
        return null;
      }
    }
    // desktop implementation
  } else {
    final args = GoogleSignInArgs(
      clientId: fdb.getClientId()!,
      redirectUri: 'http://localhost:8641/oauth/callback',
      scope: defaultScopes.join(' '),
    );
    try {
      final width = PrefsSvc.i.getDouble('window-width')?.toInt();
      final height = PrefsSvc.i.getDouble('window-height')?.toInt();
      final result = await DesktopWebviewAuth.signIn(
        args,
        width: width != null ? (width * 0.9).ceil() : null,
        height: height != null ? (height * 0.9).ceil() : null,
      );
      Future.delayed(const Duration(milliseconds: 500), () async => await windowManager.show());
      token = result?.accessToken;
      // error if token is not present
      if (token == null) {
        throw Exception("No access token!");
      }
    } catch (e, stack) {
      Logger.error("Failed to sign in with Google (Desktop)", error: e, trace: stack);
      return null;
    }
  }
  return token;
}

Future<List<Map>> fetchFirebaseProjects(String token) async {
  List<Map> usableProjects = [];
  try {
    // query firebase projects
    final response = await HttpSvc.getFirebaseProjects(token);
    final projects = response.data['results'];
    List<Object> errors = [];
    // find projects with RTDB or cloud firestore
    if (projects.isNotEmpty) {
      for (Map e in projects) {
        if (e['resources']['realtimeDatabaseInstance'] != null) {
          try {
            final serverUrlResponse = await HttpSvc.getServerUrlRTDB(e['resources']['realtimeDatabaseInstance'], token);
            e['serverUrl'] = serverUrlResponse.data['serverUrl'];
            usableProjects.add(e);
          } catch (ex) {
            errors.add("Realtime Database Error: $ex");
          }
        } else {
          try {
            final serverUrlResponse = await HttpSvc.getServerUrlCF(e['projectId'], token);
            e['serverUrl'] = serverUrlResponse.data['fields']['serverUrl']['stringValue'];
            usableProjects.add(e);
          } catch (ex) {
            errors.add("Firestore Database Error: $ex");
          }
        }
      }

      if (usableProjects.isEmpty && errors.isNotEmpty) {
        throw Exception(errors[0]);
      }

      usableProjects.removeWhere((element) => element['serverUrl'] == null);

      return usableProjects;
    }
    return [];
  } catch (e) {
    return [];
  }
}

Future<void> requestPassword(
    BuildContext context, String serverUrl, Future<void> Function(String url, String password) connect) async {
  final TextEditingController passController = TextEditingController();
  final RxBool enabled = false.obs;
  await BBCustomDialog.show(
    context: context,
    title: "Server Password",
    config: const BBCustomDialogConfig(barrierDismissible: false),
    content: Obx(
      () => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: passController,
            decoration: const InputDecoration(
              labelText: "Password",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            obscureText: true,
            autofillHints: [AutofillHints.password],
            onChanged: (str) {
              if (enabled.value ^ str.isNotEmpty) {
                enabled.value = str.isNotEmpty;
              }
            },
            onSubmitted: (str) {
              if (passController.text.isEmpty) {
                return;
              }
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        ],
      ),
    ),
    actions: [
      BBDialogAction(
        label: "Cancel",
        type: BBDialogButtonType.cancel,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
      BBDialogAction(
        label: "OK",
        type: BBDialogButtonType.primary,
        onPressed: () async {
          if (passController.text.isEmpty || !enabled.value) {
            return;
          }
          Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    ],
  );

  await connect(serverUrl, passController.text);
}
