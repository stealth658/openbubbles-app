import 'dart:isolate';
import 'dart:ui' hide window;

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' hide Platform;
import 'dart:io' show Platform;
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
LifecycleService get LifecycleSvc => GetIt.I<LifecycleService>();

class LifecycleService with WidgetsBindingObserver {
  bool isBubble = false;
  bool isUiThread = true;
  bool windowFocused = true;
  bool? wasActiveAliveBefore;
  bool get isAlive => kIsWeb ? !(window.document.hidden ?? false)
      : kIsDesktop ? windowFocused : (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed
        || IsolateNameServer.lookupPortByName('bg_isolate') != null);

  AppLifecycleState? get currentState => WidgetsBinding.instance.lifecycleState;

  List<AppLifecycleState> statesSinceLastResume = [];

  bool get wasPaused => statesSinceLastResume.contains(AppLifecycleState.paused);
  bool get wasHidden => statesSinceLastResume.contains(AppLifecycleState.inactive) || statesSinceLastResume.contains(AppLifecycleState.detached);
  bool get hasResumed => statesSinceLastResume.contains(AppLifecycleState.resumed);

  Future<void> init({bool headless = false, bool isBubble = false}) async {
    Logger.debug("Initializing LifecycleService${headless ? " in headless mode" : ""}");
    
    // Only add observer if we're on the UI thread
    if (!headless) {
      WidgetsBinding.instance.addObserver(this);
    }

    isUiThread = !headless;
    this.isBubble = isBubble;

    // Only handle foreground service on UI thread
    if (!headless) {
      handleForegroundService(AppLifecycleState.resumed);
    }
    Logger.debug("LifecycleService initialized");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    Logger.debug("App State changed to $state");

    // If the current state is resume, and we've already had a resume, remove all states up to the last resume.
    if (state == AppLifecycleState.resumed && statesSinceLastResume.contains(AppLifecycleState.resumed)) {
      // Remove states up to the last resume
      while (statesSinceLastResume.isNotEmpty && statesSinceLastResume.first != AppLifecycleState.resumed) {
        statesSinceLastResume.removeAt(0);
      }
    } else {
      statesSinceLastResume.add(state);
    }

    if (state == AppLifecycleState.resumed) {
      await Database.waitForInit();
      open();
    } else if (state != AppLifecycleState.inactive) {
      // UI-dependent: Keyboard management
      if (isUiThread) {
        SystemChannels.textInput.invokeMethod('TextInput.hide').catchError((e, stack) {
          Logger.error("Error caught while hiding keyboard!", error: e, trace: stack);
        });
      }
      
      if (isBubble) {
        closeBubble();
      } else {
        close();
      }
    }

    handleForegroundService(state);
  }

  void handleForegroundService(AppLifecycleState state) async {
    // If an isolate is invoking this, we don't want to start/stop the foreground service.
    // It should already be running. We don't need to stop it because the socket service
    // is not started when in headless mode.
    if (!isUiThread) return;

    if ([AppLifecycleState.inactive, AppLifecycleState.hidden].contains(state)) return;

    // This may get called before the settings service is initialized
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool keepAlive = prefs.getBool("keepAppAlive") ?? false;

    if (Platform.isAndroid && keepAlive) {
      // We only want the foreground service to run when the app is not active
      if (state == AppLifecycleState.resumed) {
        Logger.info(tag: "LifecycleService", "Stopping foreground service");
        MethodChannelSvc.invokeMethod("stop-foreground-service");
      } else if ([AppLifecycleState.paused, AppLifecycleState.detached].contains(state)) {
        Logger.info(tag: "LifecycleService", "Starting foreground service");
        MethodChannelSvc.invokeMethod("start-foreground-service");
      }
    }
  }

  void open() {
    // Only add observer if we're on the UI thread
    if (isUiThread) {
      WidgetsBinding.instance.addObserver(this);
    }

    // UI-dependent: Chat controller management
    if (isUiThread) {
      if (!kIsDesktop || wasActiveAliveBefore != false) {
        cm.setActiveToAlive();
      }
      if (cm.activeChat != null) {
        cm.activeChat!.chat.toggleHasUnread(false);
        ConversationViewController _cvc = cvc(cm.activeChat!.chat);
        if (!_cvc.showingOverlays && _cvc.editing.isEmpty) {
          _cvc.lastFocusedNode.requestFocus();
        }
      }
    }

    if (HttpSvc.originOverride == null) {
      NetworkTasks.detectLocalhost();
    }
    if (!kIsDesktop && !kIsWeb) {
      if (!isBubble) {
        createFakePort();
      }
      
      SocketSvc.reconnect();
    }

    if (kIsDesktop && isUiThread) {
      windowFocused = true;
    }
  }

  // clever trick so we can see if the app is active in an isolate or not
  void createFakePort() {
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping('bg_isolate');
    IsolateNameServer.registerPortWithName(port.sendPort, 'bg_isolate');
  }

  void close() {
    // Only remove observer if we're on the UI thread
    if (isUiThread) {
      WidgetsBinding.instance.removeObserver(this);
    }

    // UI-dependent: Chat controller management
    if (isUiThread) {
      if (kIsDesktop) {
        wasActiveAliveBefore = cm.activeChat?.isAlive;
      }
      if (!kIsDesktop || wasActiveAliveBefore != false) {
        cm.setActiveToDead();
      }
      if (cm.activeChat != null) {
        ConversationViewController _cvc = cvc(cm.activeChat!.chat);
        _cvc.lastFocusedNode.unfocus();
      }
      if (kIsDesktop) {
        windowFocused = false;
      }
    }
    
    if (!kIsDesktop && !kIsWeb) {
      IsolateNameServer.removePortNameMapping('bg_isolate');
      SocketSvc.disconnect();
    }
  }

  void closeBubble() {
    // UI-dependent: Chat controller management
    if (isUiThread) {
      cm.setActiveToDead();
    }
    SocketSvc.disconnect();
  }
}