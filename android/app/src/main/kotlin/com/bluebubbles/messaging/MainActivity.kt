package com.bluebubbles.messaging

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import com.bluebubbles.messaging.services.foreground.ForegroundServiceBroadcastReceiver
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.services.extension.KeyboardViewFactory
import com.bluebubbles.messaging.services.extension.LiveExtensionFactory
import com.bluebubbles.messaging.services.rustpush.APNService
import com.bluebubbles.messaging.services.system.CreateDocumentHandler
import com.bluebubbles.messaging.services.system.EnableBTHandler
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.firebase.firestore.FirebaseFirestoreException
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private val engineLock = Any()
        @Volatile private var _engine: FlutterEngine? = null

        // Whether the Dart side of [_engine] has finished registering its method-call
        // handler (signaled via the "ready" method call — see MethodCallHandler).
        // Always reset to false alongside [_engine] itself so a stale "ready" from a
        // previous engine can never be mistaken for the current one's readiness.
        @Volatile private var _dartReady = false

        // NOTE (merge): upstream exposes these as getEngine()/isDartReady(). They are
        // properties here because OpenBubbles' rustpush services (APNService,
        // SIMInfoQuery) read `MainActivity.engine` / `MainActivity.engine_ready`
        // directly. Declaring both a `fun getEngine()` and a `val engine` would be a
        // JVM signature clash, so the property form is the single source of truth.
        val engine: FlutterEngine?
            get() = synchronized(engineLock) { _engine }

        val engine_ready: Boolean
            get() = synchronized(engineLock) { _dartReady }

        fun setEngine(newEngine: FlutterEngine?, context: Context) {
            synchronized(engineLock) {
                PersistentLog.d(
                    context,
                    Constants.logTag,
                    "MainActivity engine ${if (newEngine != null) "set (${newEngine.hashCode()})" else "cleared"} — resetting dartReady to false"
                )
                _engine = newEngine
                _dartReady = false
            }
        }

        fun setDartReady(ready: Boolean, context: Context) {
            synchronized(engineLock) {
                if (_dartReady != ready) {
                    PersistentLog.d(context, Constants.logTag, "MainActivity dartReady changing from $_dartReady to $ready")
                }
                _dartReady = ready
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // OpenBubbles talks to APNs itself; the push service must be running for the
        // whole life of the app, not just while a chat is open.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(Intent(this, APNService::class.java))
        } else {
            startService(Intent(this, APNService::class.java))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        setEngine(flutterEngine, this)
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Constants.methodChannel).setMethodCallHandler { call, result ->
            if (call.method == "engine-done") {
                PersistentLog.d(this, Constants.logTag, "Flutter engine reported done; destroying it")
                // this must be here in case another engine has been spawned in the meantime
                flutterEngine.destroy()
                if (engine === flutterEngine) {
                    setEngine(null, this)
                }
            }
            MethodCallHandler().methodCallHandler(call, result, this)
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("extension-keyboard", KeyboardViewFactory())
        flutterEngine.platformViewsController.registry.registerViewFactory("extension-live", LiveExtensionFactory())

        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            val cause = throwable.cause ?: throwable
            if (cause is FirebaseFirestoreException) {
                when (cause.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: PERMISSION_DENIED — missing or insufficient security rules (${cause.message})", cause)
                    FirebaseFirestoreException.Code.UNAVAILABLE ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: UNAVAILABLE — service unreachable, check network connectivity (${cause.message})", cause)
                    FirebaseFirestoreException.Code.UNAUTHENTICATED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: UNAUTHENTICATED — request not authenticated (${cause.message})", cause)
                    FirebaseFirestoreException.Code.NOT_FOUND ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: NOT_FOUND — document or collection does not exist (${cause.message})", cause)
                    FirebaseFirestoreException.Code.CANCELLED ->
                        PersistentLog.d(this, Constants.logTag, "Firestore: CANCELLED — listener was cancelled (${cause.message})")
                    FirebaseFirestoreException.Code.ALREADY_EXISTS ->
                        PersistentLog.w(this, Constants.logTag, "Firestore: ALREADY_EXISTS — document already exists (${cause.message})")
                    FirebaseFirestoreException.Code.RESOURCE_EXHAUSTED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: RESOURCE_EXHAUSTED — quota exceeded (${cause.message})", cause)
                    FirebaseFirestoreException.Code.FAILED_PRECONDITION ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: FAILED_PRECONDITION — operation rejected, check indexes or state (${cause.message})", cause)
                    FirebaseFirestoreException.Code.ABORTED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: ABORTED — transaction conflict or contention (${cause.message})", cause)
                    FirebaseFirestoreException.Code.INTERNAL ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: INTERNAL — internal server error (${cause.message})", cause)
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: DEADLINE_EXCEEDED — operation timed out (${cause.message})", cause)
                    else ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: unhandled error ${cause.code} (${cause.message})", cause)
                }
            } else {
                defaultHandler?.uncaughtException(thread, throwable)
            }
        }
    }

    override fun onDestroy() {
        PersistentLog.d(this, Constants.logTag, "BlueBubbles MainActivity is being destroyed")
        MethodCallHandler.clearNotificationListenerResult()
        setEngine(null, this)

        // If we are finishing "gracefully", the dart code would have started the foreground service.
        // If we are finishing because the system is destroying the activity, we need to start the foreground service
        // via a broadcast intent.
        if (isFinishing) {
            PersistentLog.d(this, Constants.logTag, "BlueBubbles activity is finishing")
        } else {
            PersistentLog.d(this, Constants.logTag, "BlueBubbles activity is being destroyed by the system")

            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", 0)
            val keepAppAlive: Boolean = prefs.getBoolean("keepAppAlive", false)

            // Create an intent to start the foreground service
            if (keepAppAlive) {
                PersistentLog.d(this, Constants.logTag, "Creating broadcast intent to restart the foreground service...")
                val broadcastIntent = Intent(this, ForegroundServiceBroadcastReceiver::class.java)
                broadcastIntent.setAction("restartservice");
                sendBroadcast(broadcastIntent);
            }
        }

        try {
            super.onDestroy()
        } catch (e: ConcurrentModificationException) {
            PersistentLog.e(this, Constants.logTag, "Caught ConcurrentModificationException when destroying MainActivity", e)
        } catch (e: Exception) {
            PersistentLog.e(this, Constants.logTag, "Caught unhandled Exception when destroying MainActivity", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == Constants.notificationListenerRequestCode) {
            MethodCallHandler.consumeNotificationListenerResult()?.success(resultCode == Activity.RESULT_OK)
        }
        if (requestCode == Constants.documentSaveRequestCode) {
            val result = CreateDocumentHandler.savedResult!!
            CreateDocumentHandler.savedResult = null
            val uri = data?.data
            if (uri == null) {
                result.success(null)
                return
            }

            try {
                val output = contentResolver.openOutputStream(uri)!!
                val input = FileInputStream(CreateDocumentHandler.savedPath!!)
                input.copyTo(output)
                output.close()
                input.close()
                result.success(null)
            } catch (e: Exception) {
                result.error("FILE_WRITE_ERROR", e.message, null)
            }
        }
        if (requestCode == Constants.enableBtRequestCode) {
            val result = EnableBTHandler.savedResult!!
            result.success(true)
        }
    }
}
