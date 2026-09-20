package com.bluebubbles.messaging.services.car

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.messaging.model.CarMessage
import androidx.car.app.messaging.model.ConversationCallback
import androidx.car.app.messaging.model.ConversationItem
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Template
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import java.io.File
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.services.backend_ui_interop.DartWorkManager
import com.bluebubbles.messaging.utils.PersistentLog

/// The car-screen conversation list. One [ConversationItem] per recent chat; the
/// host renders each with play / reply / mark-as-read on its own, so the only
/// behaviour we own is what those callbacks do -- and they route to exactly the
/// same Dart workers the notification actions use (ReplyChat / MarkChatRead).
class ConversationListScreen(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {

    private val self: Person = Person.Builder().setName("You").setKey("self").build()

    private val storeListener: () -> Unit = {
        // Store changes arrive on arbitrary threads; invalidate() must run on main.
        carContext.mainExecutor.execute { invalidate() }
    }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        CarConversationStore.addListener(storeListener)
    }

    override fun onStop(owner: LifecycleOwner) {
        CarConversationStore.removeListener(storeListener)
    }

    override fun onGetTemplate(): Template {
        val ctx = carContext.applicationContext
        val conversations = CarConversationStore.current(ctx)

        val list = ItemList.Builder().setNoItemsMessage("No recent conversations")
        var shown = 0
        for (c in conversations) {
            // One malformed conversation must not take the whole screen down.
            val item = try { buildItem(c) } catch (e: Exception) {
                PersistentLog.w(ctx, Constants.logTag, "Android Auto: skipping conversation ${c.guid}", e)
                null
            } ?: continue
            list.addItem(item)
            shown++
        }
        PersistentLog.d(ctx, Constants.logTag, "Android Auto: rendering conversation list ($shown of ${conversations.size} conversations)")

        return ListTemplate.Builder()
            .setTitle("Messages")
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(list.build())
            .build()
    }

    private fun buildItem(c: CarConversationData): ConversationItem? {
        if (c.messages.isEmpty()) return null
        val ctx = carContext.applicationContext

        // Oldest -> newest, as the library requires. The snapshot is already in that
        // order and the store appends at the end, but sort defensively.
        val messages = c.messages.sortedBy { it.date }.map { m ->
            val sender = if (m.isFromMe) self else Person.Builder().setName(m.sender).setKey(m.senderKey).build()
            CarMessage.Builder()
                .setBody(CarText.create(m.text))
                .setSender(sender)
                .setReceivedTimeEpochMillis(m.date)
                .setRead(!c.hasUnread || m.isFromMe)
                .build()
        }

        val lastGuid = c.messages.last().guid
        val callback = object : ConversationCallback {
            override fun onMarkAsRead() {
                PersistentLog.d(ctx, Constants.logTag, "Android Auto: mark as read ${c.guid}")
                CarConversationStore.markRead(ctx, c.guid)
                DartWorkManager.createWorker(ctx, "MarkChatRead", hashMapOf("chatGuid" to c.guid)) {}
            }

            override fun onTextReply(replyText: String) {
                PersistentLog.d(ctx, Constants.logTag, "Android Auto: reply to ${c.guid}")
                DartWorkManager.createWorker(
                    ctx,
                    "ReplyChat",
                    hashMapOf("chatGuid" to c.guid, "messageGuid" to lastGuid, "text" to replyText),
                ) { succeeded ->
                    if (succeeded) {
                        CarConversationStore.recordOutgoing(ctx, c.guid, replyText)
                    } else {
                        PersistentLog.e(ctx, Constants.logTag, "Android Auto: reply to ${c.guid} failed to send")
                    }
                }
            }
        }

        return ConversationItem.Builder(c.guid, CarText.create(c.title), self, messages, callback)
            .setGroupConversation(c.isGroup)
            .setIcon(iconFor(c))
            .build()
    }

    /// Without an explicit icon the host falls back to the initial of the *self*
    /// person, so every row showed "Y" for "You". Prefer the rendered avatar the
    /// phone uses (contact photo / group composite), else initials from the title.
    private fun iconFor(c: CarConversationData): CarIcon {
        val bmp = c.avatarPath?.let { loadAvatar(it) } ?: initialsBitmap(c.title)
        return CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
    }

    private fun loadAvatar(path: String): Bitmap? = try {
        val f = File(path)
        if (!f.exists()) null else BitmapFactory.decodeFile(path)?.let { src ->
            // Keep the host's IPC payload small; 128px is plenty for a list row.
            if (src.width > AVATAR_PX) Bitmap.createScaledBitmap(src, AVATAR_PX, AVATAR_PX, true) else src
        }
    } catch (e: Exception) { null }

    private fun initialsBitmap(title: String): Bitmap {
        val initials = title.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            .take(2).joinToString("") { it.first().uppercaseChar().toString() }
            .ifEmpty { "?" }
        val bmp = Bitmap.createBitmap(AVATAR_PX, AVATAR_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(0x4A, 0x90, 0xE2) }
        canvas.drawCircle(AVATAR_PX / 2f, AVATAR_PX / 2f, AVATAR_PX / 2f, bg)
        val fg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = AVATAR_PX * 0.42f
            textAlign = Paint.Align.CENTER
            isFakeBoldText = true
        }
        val bounds = Rect()
        fg.getTextBounds(initials, 0, initials.length, bounds)
        canvas.drawText(initials, AVATAR_PX / 2f, AVATAR_PX / 2f - bounds.exactCenterY(), fg)
        return bmp
    }

    companion object {
        private const val AVATAR_PX = 128
    }
}
