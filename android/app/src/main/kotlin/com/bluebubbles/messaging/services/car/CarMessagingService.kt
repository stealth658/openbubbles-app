package com.bluebubbles.messaging.services.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.utils.PersistentLog

/// Android Auto entry point for templated messaging (Car App Library, category
/// MESSAGING). The host binds here when the phone is connected to a car; the
/// session hands back a [ConversationListScreen] that draws the app's recent
/// conversations from [CarConversationStore].
///
/// This complements, and does not replace, the MessagingStyle notifications:
/// those still drive "new message" alerts and read-aloud on the car; this adds
/// the conversation list you can browse back into.
///
/// Logging here is deliberately chatty. On a real car the host once showed the
/// notification-only "No new messages during this drive" screen while the
/// desktop head unit showed the template, and the app log had no trace of the
/// host at all, so it was impossible to tell whether the host never bound, bound
/// and failed validation, or bound and asked for a session that then failed.
/// The three stages now each leave a line: service created (host bound),
/// validator requested (host is being checked), session created (validation
/// passed). `onBind` itself is final in CarAppService, so `onCreate` is the
/// earliest hook we get.
class CarMessagingService : CarAppService() {

    override fun onCreate() {
        super.onCreate()
        PersistentLog.d(applicationContext, Constants.logTag, "Android Auto: CarMessagingService created (host is binding)")
    }

    override fun onDestroy() {
        PersistentLog.d(applicationContext, Constants.logTag, "Android Auto: CarMessagingService destroyed")
        super.onDestroy()
    }

    override fun createHostValidator(): HostValidator {
        // Debug builds accept any host so the Desktop Head Unit works. Release builds
        // use the library's allowlist of Google-signed Android Auto hosts -- the
        // templates carry message text, so an arbitrary app must not be able to bind.
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        PersistentLog.d(
            applicationContext,
            Constants.logTag,
            "Android Auto: host validator requested (debuggable=$debuggable, using ${if (debuggable) "allow-all" else "Google host allowlist"})",
        )
        return if (debuggable) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session {
        PersistentLog.d(applicationContext, Constants.logTag, "Android Auto session created")
        return CarMessagingSession()
    }
}

class CarMessagingSession : Session(), DefaultLifecycleObserver {

    init {
        lifecycle.addObserver(this)
    }

    override fun onCreateScreen(intent: Intent): Screen {
        val ctx = carContext.applicationContext
        val host = try { carContext.hostInfo } catch (e: Exception) { null }
        PersistentLog.d(
            ctx,
            Constants.logTag,
            "Android Auto: onCreateScreen host=${host?.packageName ?: "?"} apiLevel=${carContext.carAppApiLevel} intent=${intent.action} ${intent.dataString ?: ""}",
        )
        // Fresh snapshot from Dart on every session start; the screen renders the
        // cached list (if any) immediately and re-renders when the snapshot lands.
        CarConversationStore.refresh(ctx)
        return ConversationListScreen(carContext)
    }

    override fun onNewIntent(intent: Intent) {
        PersistentLog.d(carContext.applicationContext, Constants.logTag, "Android Auto: onNewIntent ${intent.action} ${intent.dataString ?: ""}")
        super.onNewIntent(intent)
    }

    override fun onStart(owner: LifecycleOwner) {
        PersistentLog.d(carContext.applicationContext, Constants.logTag, "Android Auto: session started (visible on car)")
    }

    override fun onStop(owner: LifecycleOwner) {
        PersistentLog.d(carContext.applicationContext, Constants.logTag, "Android Auto: session stopped")
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PersistentLog.d(carContext.applicationContext, Constants.logTag, "Android Auto: session destroyed")
    }
}
