package com.bluebubbles.messaging.services.system

import android.app.Activity
import android.content.Context
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.utils.PersistentLog
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Reports what Android itself says about the keyboard: whether the IME is visible and how
/// many pixels it insets the window by. Dart compares this with the insets the Flutter engine
/// last handed it, to tell an engine that kept a stale keyboard inset (blank space where the
/// keyboard was) from a keyboard that really is still up.
///
/// With "reapply": true it also asks the window to dispatch its insets again, which makes
/// FlutterView recompute the viewport metrics from the current window state.
class ImeStateHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag = "ime-state"
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val activity = context as? Activity
        if (activity == null) {
            result.success(null)
            return
        }
        val decor = activity.window.decorView
        val insets = ViewCompat.getRootWindowInsets(decor)
        val bottom = insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        val visible = insets?.isVisible(WindowInsetsCompat.Type.ime()) ?: false
        val reapply = call.argument<Boolean>("reapply") ?: false
        if (reapply) {
            PersistentLog.d(context, Constants.logTag, "IME state: visible=$visible bottom=$bottom; re-dispatching window insets")
            decor.requestApplyInsets()
        }
        result.success(mapOf("visible" to visible, "bottom" to bottom))
    }
}
