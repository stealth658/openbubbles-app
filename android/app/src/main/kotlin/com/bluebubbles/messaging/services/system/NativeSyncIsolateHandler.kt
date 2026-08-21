package com.bluebubbles.messaging.services.system

import android.content.Context
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.ApplicationInfoLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import io.flutter.embedding.engine.loader.FlutterLoader
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class NativeSyncIsolateHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag = "native-sync-isolate"

        var engine: FlutterEngine? = null
    }

    override fun handleMethodCall(
        call: MethodCall,
        mainresult: MethodChannel.Result,
        mainContext: Context
    ) {
        val context = mainContext.applicationContext

        var param = call.argument<Boolean>("close") ?: false
        if (param) {
            engine?.destroy()
            engine = null
            mainresult.success(null)
            return
        }

        if (engine != null) {
            mainresult.success(null)
            return
        }

        // io.flutter.view.FlutterMain was removed in newer Flutter; FlutterLoader is
        // the supported entry point (see DartWorker, which upstream already migrated).
        val flutterLoader = FlutterLoader()
        flutterLoader.startInitialization(context)
        flutterLoader.ensureInitializationComplete(context, null)

        Log.d(Constants.logTag, "Loading callback info")
        val info = ApplicationInfoLoader.load(context)
        val workerEngine = FlutterEngine(context)
        engine = workerEngine
        MethodChannel(workerEngine.dartExecutor.binaryMessenger, Constants.methodChannel).setMethodCallHandler {
                call, result -> run {
            if (call.method == "ready") {
                Log.d(Constants.logTag, "Dart engine is ready!")
                mainresult.success(null)
            } else if (call.method == "exit") {
                workerEngine.destroy()
                engine = null
            } else {
                MethodCallHandler().methodCallHandler(call, result, context)
            }
        }
        }
        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(run {
            // Upstream dropped the "flutter." key prefix (SettingsHelper.PREFIX == ""),
            // and the Dart side now writes this via PrefsSvc as "backgroundSyncIsolate".
            // The prefixed key is still read as a fallback for installs upgraded from
            // an older OpenBubbles build.
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", 0)
            val handle = prefs.getLong("backgroundSyncIsolate", -1)
            if (handle != -1L) handle else prefs.getLong("flutter.backgroundSyncIsolate", -1)
        })
        val callback = DartExecutor.DartCallback(context.assets, info.flutterAssetsDir, callbackInfo)

        Log.d(Constants.logTag, "Executing Dart callback")
        workerEngine.dartExecutor.executeDartCallback(callback)
    }
}