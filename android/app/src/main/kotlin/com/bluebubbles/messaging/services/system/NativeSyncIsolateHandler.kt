package com.bluebubbles.messaging.services.system

import android.content.Context
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import com.bluebubbles.messaging.utils.PersistentLog
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
            PersistentLog.d(context, Constants.logTag, "Sync isolate: close requested (engine present: ${engine != null})")
            engine?.destroy()
            engine = null
            mainresult.success(null)
            return
        }

        if (engine != null) {
            PersistentLog.d(context, Constants.logTag, "Sync isolate: engine already running, not starting another")
            mainresult.success(null)
            return
        }

        try {
            // io.flutter.view.FlutterMain was removed in newer Flutter; FlutterLoader is
            // the supported entry point (see DartWorker, which upstream already migrated).
            val flutterLoader = FlutterLoader()
            flutterLoader.startInitialization(context)
            flutterLoader.ensureInitializationComplete(context, null)

            PersistentLog.d(context, Constants.logTag, "Sync isolate: loading callback info")
            val info = ApplicationInfoLoader.load(context)
            val workerEngine = FlutterEngine(context)
            engine = workerEngine
            MethodChannel(workerEngine.dartExecutor.binaryMessenger, Constants.methodChannel).setMethodCallHandler {
                    call, result -> run {
                if (call.method == "ready") {
                    PersistentLog.d(context, Constants.logTag, "Sync isolate: Dart engine is ready")
                    mainresult.success(null)
                } else if (call.method == "exit") {
                    PersistentLog.d(context, Constants.logTag, "Sync isolate: Dart asked to exit")
                    workerEngine.destroy()
                    engine = null
                } else {
                    MethodCallHandler().methodCallHandler(call, result, context)
                }
            }
            }
            // Upstream dropped the "flutter." key prefix (SettingsHelper.PREFIX == ""),
            // and the Dart side now writes this via PrefsSvc as "backgroundSyncIsolate".
            // The prefixed key is still read as a fallback for installs upgraded from
            // an older OpenBubbles build.
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", 0)
            var handle = prefs.getLong("backgroundSyncIsolate", -1)
            if (handle == -1L) handle = prefs.getLong("flutter.backgroundSyncIsolate", -1)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
            if (callbackInfo == null) {
                PersistentLog.e(context, Constants.logTag, "Sync isolate: no Dart callback for handle $handle")
                workerEngine.destroy()
                engine = null
                mainresult.error("500", "Sync isolate callback not registered (handle $handle)", null)
                return
            }
            val callback = DartExecutor.DartCallback(context.assets, info.flutterAssetsDir, callbackInfo)

            PersistentLog.d(context, Constants.logTag, "Sync isolate: executing Dart callback (handle $handle)")
            workerEngine.dartExecutor.executeDartCallback(callback)
        } catch (e: Exception) {
            PersistentLog.e(context, Constants.logTag, "Sync isolate: failed to start", e)
            engine?.destroy()
            engine = null
            mainresult.error("500", "Sync isolate failed to start: ${e.message}", null)
        }
    }
}